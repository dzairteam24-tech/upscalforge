//! Static memory planning.
//!
//! Every node output gets a slot in one arena. Two tensors may share
//! addresses only if their lifetimes do not overlap. The plan is computed
//! before execution, so activation memory is known exactly in advance; the
//! VRAM manager's pre-flight checks rely on this.

use crate::graph::{Graph, ValueRef};
use crate::infer::Shapes;

/// Byte alignment of every slot (suits SIMD loads and GPU access).
pub const ARENA_ALIGNMENT: u64 = 256;

/// Placement of one node output.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Slot {
    /// Byte offset in the arena (a multiple of [`ARENA_ALIGNMENT`]).
    pub offset: u64,
    /// Bytes reserved (the tensor size rounded up to the alignment).
    pub bytes: u64,
    /// Index of the node that produces the tensor.
    pub first_use: usize,
    /// Index of the last node that reads it; `nodes.len()` for graph outputs.
    pub last_use: usize,
}

/// A complete memory plan.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MemoryPlan {
    /// Arena size needed.
    pub arena_bytes: u64,
    /// Slot for each node's output.
    pub slots: Vec<Slot>,
    /// Largest sum of simultaneously live tensors: a lower bound for any
    /// placement, reported to judge packing quality.
    pub peak_live_bytes: u64,
}

fn round_up(v: u64) -> u64 {
    v.div_ceil(ARENA_ALIGNMENT) * ARENA_ALIGNMENT
}

/// Plans node-output placement for elements of `element_bytes` each.
///
/// Placement is greedy: largest tensors first, each at the lowest offset
/// that does not collide with an already-placed tensor whose lifetime
/// overlaps.
pub fn plan_memory(graph: &Graph, shapes: &Shapes, element_bytes: u32) -> MemoryPlan {
    let n = graph.nodes.len();
    let mut last_use: Vec<usize> = (0..n).collect();
    for (i, node) in graph.nodes.iter().enumerate() {
        for r in &node.inputs {
            if let ValueRef::Node(j) = *r {
                last_use[j as usize] = last_use[j as usize].max(i);
            }
        }
    }
    for out in &graph.outputs {
        if let ValueRef::Node(j) = out.value {
            last_use[j as usize] = n;
        }
    }

    let mut slots: Vec<Slot> = (0..n)
        .map(|i| Slot {
            offset: 0,
            bytes: round_up(shapes.nodes[i].elements() * u64::from(element_bytes)),
            first_use: i,
            last_use: last_use[i],
        })
        .collect();

    let mut order: Vec<usize> = (0..n).collect();
    order.sort_by(|&a, &b| slots[b].bytes.cmp(&slots[a].bytes).then(a.cmp(&b)));
    let mut placed: Vec<usize> = Vec::with_capacity(n);
    let mut arena = 0u64;
    for &i in &order {
        let s = slots[i];
        let mut busy: Vec<(u64, u64)> = placed
            .iter()
            .map(|&j| slots[j])
            .filter(|o| o.first_use <= s.last_use && s.first_use <= o.last_use)
            .map(|o| (o.offset, o.offset + o.bytes))
            .collect();
        busy.sort_unstable();
        let mut offset = 0u64;
        for (start, end) in busy {
            if offset + s.bytes <= start {
                break;
            }
            offset = offset.max(end);
        }
        slots[i].offset = offset;
        arena = arena.max(offset + s.bytes);
        placed.push(i);
    }

    let mut peak = 0u64;
    for t in 0..=n {
        let live: u64 = slots.iter().filter(|s| s.first_use <= t && t <= s.last_use).map(|s| s.bytes).sum();
        peak = peak.max(live);
    }
    MemoryPlan { arena_bytes: arena, slots, peak_live_bytes: peak }
}
