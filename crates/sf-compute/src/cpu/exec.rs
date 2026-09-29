//! Graph execution on the CPU.

use std::any::Any;
use std::ops::Range;
use std::sync::RwLockReadGuard;

use sf_core::{Error, Result};
use sf_graph::{Graph, MemoryPlan, Op, Shape, Shapes, ValueRef, infer_shapes, plan_memory};

use super::{cpu_buffer, kernels, poisoned};
use crate::{Binding, Bindings, Buffer, Executable, MemoryRequirement, Precision};

/// A graph compiled for fixed input shapes.
pub(super) struct CpuExecutable {
    graph: Graph,
    shapes: Shapes,
    plan: MemoryPlan,
    threads: usize,
}

impl CpuExecutable {
    pub(super) fn build(
        graph: &Graph,
        inputs: &[Shape],
        precision: Precision,
        threads: usize,
    ) -> Result<Self> {
        if precision != Precision::F32 {
            return Err(Error::unsupported("the cpu backend executes f32 only"));
        }
        let shapes = infer_shapes(graph, inputs)?;
        let plan = plan_memory(graph, &shapes, 4);
        Ok(CpuExecutable { graph: graph.clone(), shapes, plan, threads })
    }

    fn slot_range(&self, node: usize) -> Range<usize> {
        let start = (self.plan.slots[node].offset / 4) as usize;
        start..start + self.shapes.nodes[node].elements() as usize
    }

    fn param_len(&self, i: usize) -> usize {
        self.graph.params[i].elements() as usize
    }

    /// Checks that `b` matches this executable: counts, kinds, sizes and
    /// aliasing. Called before any work or bookkeeping happens.
    pub(super) fn check_bindings(&self, b: &Bindings<'_>) -> Result<()> {
        let g = &self.graph;
        let count = |what: &str, got: usize, want: usize| {
            if got == want {
                Ok(())
            } else {
                Err(Error::invalid_input(format!("{want} {what} bindings expected, {got} given")))
            }
        };
        count("input", b.inputs.len(), g.inputs.len())?;
        count("parameter", b.params.len(), g.params.len())?;
        count("output", b.outputs.len(), g.outputs.len())?;
        let too_small = |what: String, have: u64, need: u64| {
            if have >= need {
                Ok(())
            } else {
                Err(Error::invalid_input(format!("{what} holds {have} bytes, {need} needed")))
            }
        };
        too_small("arena".into(), b.arena.size_bytes(), self.plan.arena_bytes)?;

        let mut bound: Vec<&Buffer> = Vec::new();
        for (i, (binding, shape)) in b.inputs.iter().zip(&self.shapes.inputs).enumerate() {
            match (binding, shape) {
                (Binding::Scalar(_), Shape::Scalar) => {}
                (Binding::Buffer(buf), s) if *s != Shape::Scalar => {
                    too_small(format!("input {i}"), buf.size_bytes(), s.elements() * 4)?;
                    bound.push(buf);
                }
                _ => return Err(Error::invalid_input(format!("input {i} binding does not match its kind"))),
            }
        }
        for (i, p) in b.params.iter().enumerate() {
            too_small(format!("parameter {i}"), p.size_bytes(), self.param_len(i) as u64 * 4)?;
        }
        for (i, (o, decl)) in b.outputs.iter().zip(&g.outputs).enumerate() {
            let s = self.value_shape(decl.value)?;
            too_small(format!("output {i}"), o.size_bytes(), s.elements() * 4)?;
        }
        bound.extend(b.params.iter().copied());
        if bound.iter().chain(&b.outputs).any(|x| x.same_as(b.arena)) {
            return Err(Error::invalid_input("the arena must not alias another bound buffer"));
        }
        for o in &b.outputs {
            if bound.iter().any(|x| x.same_as(o)) {
                return Err(Error::invalid_input("an output buffer must not alias an input or parameter"));
            }
        }
        Ok(())
    }

    /// Runs the graph. Bindings are validated before any work starts.
    pub(super) fn run(&self, b: &Bindings<'_>) -> Result<()> {
        self.check_bindings(b)?;
        let g = &self.graph;
        let scalars: Vec<Option<f32>> = b
            .inputs
            .iter()
            .map(|x| match x {
                Binding::Scalar(v) => Some(*v),
                Binding::Buffer(_) => None,
            })
            .collect();

        // Take all locks up front: reads for inputs and parameters, the
        // arena for writing.
        let input_guards: Vec<Option<RwLockReadGuard<'_, Vec<f32>>>> = b
            .inputs
            .iter()
            .map(|x| match x {
                Binding::Buffer(buf) => read_guard(buf).map(Some),
                Binding::Scalar(_) => Ok(None),
            })
            .collect::<Result<_>>()?;
        let param_guards: Vec<RwLockReadGuard<'_, Vec<f32>>> =
            b.params.iter().map(|p| read_guard(p)).collect::<Result<_>>()?;
        let mut arena = cpu_buffer(b.arena)?.data.write().map_err(|_| poisoned())?;

        for (i, node) in g.nodes.iter().enumerate() {
            let out_range = self.slot_range(i);
            let (left, rest) = arena.split_at_mut(out_range.start);
            let (out, right) = rest.split_at_mut(out_range.len());
            let right_start = out_range.end;
            let value = |r: ValueRef| -> Result<&[f32]> {
                Ok(match r {
                    ValueRef::Input(j) => {
                        let len = self.shapes.inputs[j as usize].elements() as usize;
                        let guard = input_guards[j as usize]
                            .as_ref()
                            .ok_or_else(|| Error::internal("scalar used as a tensor"))?;
                        &guard[..len]
                    }
                    ValueRef::Param(j) => &param_guards[j as usize][..self.param_len(j as usize)],
                    ValueRef::Node(j) => {
                        let r = self.slot_range(j as usize);
                        if r.end <= out_range.start {
                            &left[r]
                        } else if r.start >= right_start {
                            &right[r.start - right_start..r.end - right_start]
                        } else {
                            return Err(Error::internal(format!(
                                "memory plan overlaps node {j} with node {i}"
                            )));
                        }
                    }
                })
            };
            let shape = |r: ValueRef| -> Shape { self.value_shape(r).unwrap_or(Shape::Scalar) };
            let scalar = |r: ValueRef| -> Result<f32> {
                match r {
                    ValueRef::Input(j) => {
                        scalars[j as usize].ok_or_else(|| Error::internal("tensor used as a scalar"))
                    }
                    _ => Err(Error::internal("scalar operand is not an input")),
                }
            };
            self.dispatch(i, &node.op, &node.inputs, out, &value, &shape, &scalar)?;
        }

        // Copy graph outputs into their buffers.
        for (o, decl) in b.outputs.iter().zip(&g.outputs) {
            let len = self.value_shape(decl.value)?.elements() as usize;
            let src: &[f32] = match decl.value {
                ValueRef::Node(j) => &arena[self.slot_range(j as usize)],
                ValueRef::Input(j) => {
                    &input_guards[j as usize].as_ref().ok_or_else(|| Error::internal("scalar output"))?[..len]
                }
                ValueRef::Param(j) => &param_guards[j as usize][..len],
            };
            let mut dst = cpu_buffer(o)?.data.write().map_err(|_| poisoned())?;
            dst[..len].copy_from_slice(src);
        }
        Ok(())
    }

    fn value_shape(&self, r: ValueRef) -> Result<Shape> {
        self.shapes.value(&self.graph, r).ok_or_else(|| Error::internal(format!("{r:?} has no shape")))
    }

    #[allow(clippy::too_many_arguments)]
    fn dispatch<'v>(
        &self,
        node: usize,
        op: &Op,
        inputs: &[ValueRef],
        out: &mut [f32],
        value: &dyn Fn(ValueRef) -> Result<&'v [f32]>,
        shape: &dyn Fn(ValueRef) -> Shape,
        scalar: &dyn Fn(ValueRef) -> Result<f32>,
    ) -> Result<()> {
        let dims = |r: ValueRef| -> Result<kernels::Dims> {
            match shape(r) {
                Shape::Spatial { n, c, h, w } => Ok(kernels::Dims::new(n, c, h, w)),
                other => Err(Error::internal(format!("node {node}: expected spatial operand, got {other}"))),
            }
        };
        let x = value(inputs[0])?;
        match op {
            Op::Conv2d { out_channels, kernel, stride, depthwise, bias } => {
                let bias = if *bias { Some(value(inputs[2])?) } else { None };
                let conv = kernels::Conv {
                    out_channels: *out_channels as usize,
                    kernel: *kernel as usize,
                    stride: *stride as usize,
                    depthwise: *depthwise,
                };
                kernels::conv2d(x, dims(inputs[0])?, value(inputs[1])?, bias, out, conv, self.threads);
            }
            Op::AvgPool2 => kernels::avg_pool2(x, dims(inputs[0])?, out),
            Op::UpsampleNearest2 => kernels::upsample_nearest2(x, dims(inputs[0])?, out),
            Op::PixelShuffle { factor } => kernels::pixel_shuffle(x, dims(inputs[0])?, *factor as usize, out),
            Op::PixelUnshuffle { factor } => {
                kernels::pixel_unshuffle(x, dims(inputs[0])?, *factor as usize, out)
            }
            Op::ScaleConst { factor } => kernels::unary(x, out, |v| v * factor),
            Op::Add => kernels::binary(x, value(inputs[1])?, out, |a, b| a + b),
            Op::Sub => kernels::binary(x, value(inputs[1])?, out, |a, b| a - b),
            Op::Mul => kernels::binary(x, value(inputs[1])?, out, |a, b| a * b),
            Op::AffineChannel => {
                let d = dims(inputs[0])?;
                let batch_of = |r: ValueRef| match shape(r) {
                    Shape::Vector { n, .. } => n as usize,
                    _ => 1,
                };
                kernels::affine_channel(
                    x,
                    d,
                    (value(inputs[1])?, batch_of(inputs[1])),
                    (value(inputs[2])?, batch_of(inputs[2])),
                    out,
                );
            }
            Op::Activation(a) => kernels::activation(x, out, *a),
            Op::PRelu => kernels::prelu(x, dims(inputs[0])?, value(inputs[1])?, out),
            Op::Clamp { lo, hi } => kernels::unary(x, out, |v| v.clamp(*lo, *hi)),
            Op::ScaleScalar => {
                let s = scalar(inputs[1])?;
                kernels::unary(x, out, |v| v * s);
            }
            Op::Concat => {
                let parts: Vec<(&[f32], kernels::Dims)> =
                    inputs.iter().map(|&r| Ok((value(r)?, dims(r)?))).collect::<Result<_>>()?;
                kernels::concat(&parts, out);
            }
            Op::SliceChannels { start, len } => {
                kernels::slice_channels(x, dims(inputs[0])?, *start as usize, *len as usize, out)
            }
            Op::Crop { top, left, bottom, right } => kernels::crop(
                x,
                dims(inputs[0])?,
                [*top as usize, *left as usize, *bottom as usize, *right as usize],
                out,
            ),
            Op::GlobalMean => kernels::global_mean(x, dims(inputs[0])?, out),
            Op::Linear { out_features, bias } => {
                let (n, c) = match shape(inputs[0]) {
                    Shape::Vector { n, c } => (n as usize, c as usize),
                    other => return Err(Error::internal(format!("node {node}: linear on {other}"))),
                };
                let bias = if *bias { Some(value(inputs[2])?) } else { None };
                kernels::linear(x, n, c, value(inputs[1])?, bias, *out_features as usize, out);
            }
        }
        Ok(())
    }
}

fn read_guard(buf: &Buffer) -> Result<RwLockReadGuard<'_, Vec<f32>>> {
    cpu_buffer(buf)?.data.read().map_err(|_| poisoned())
}

impl Executable for CpuExecutable {
    fn memory(&self) -> MemoryRequirement {
        MemoryRequirement { arena_bytes: self.plan.arena_bytes, workspace_bytes: 0 }
    }

    fn as_any(&self) -> &dyn Any {
        self
    }
}
