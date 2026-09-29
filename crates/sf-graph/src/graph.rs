//! Graph structure, construction and structural validation.

use sf_core::{Error, Result};

use crate::op::Op;

/// What a graph is used for. Each role has its own validation rules.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum GraphRole {
    /// Runs per tile. No value derived from a spatial reduction may reach a
    /// tensor output; this is what makes tiling exact.
    Main,
    /// Runs once on a bounded analysis summary; reductions allowed.
    Context,
}

/// Kind of a graph input.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum InputKind {
    /// A spatial tensor with a fixed channel count. `spacing_log2` gives its
    /// pixel spacing relative to the primary input: 0 for the image itself,
    /// 4 for a map at 1/16 resolution.
    Spatial {
        /// Channels.
        channels: u32,
        /// log2 of the pixel spacing relative to the primary input.
        spacing_log2: i32,
    },
    /// A vector `[N, channels]`.
    Vector {
        /// Channels.
        channels: u32,
    },
    /// A single runtime scalar.
    Scalar,
}

/// A declared graph input.
#[derive(Debug, Clone, PartialEq)]
pub struct InputDecl {
    /// Name, unique among inputs.
    pub name: String,
    /// Kind and fixed dimensions.
    pub kind: InputKind,
}

/// A declared parameter (weight tensor), in row-major order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParamDecl {
    /// Name, unique among parameters.
    pub name: String,
    /// Dimensions, e.g. `[out, in, k, k]` for a convolution weight.
    pub dims: Vec<u32>,
}

impl ParamDecl {
    /// Number of elements.
    pub fn elements(&self) -> u64 {
        self.dims.iter().map(|&d| u64::from(d)).product()
    }
}

/// Kind of a graph output.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum OutputKind {
    /// A result tensor (image or features).
    Tensor,
    /// Per-tile statistics (e.g. for quality control); may derive from
    /// spatial reductions.
    Statistics,
}

/// A declared graph output.
#[derive(Debug, Clone, PartialEq)]
pub struct OutputDecl {
    /// Name, unique among outputs.
    pub name: String,
    /// The value that is output.
    pub value: ValueRef,
    /// Output kind.
    pub kind: OutputKind,
}

/// Reference to a value: a graph input, a parameter, or a node's output.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ValueRef {
    /// The i-th input.
    Input(u32),
    /// The i-th parameter.
    Param(u32),
    /// The output of the i-th node.
    Node(u32),
}

/// One operation.
#[derive(Debug, Clone, PartialEq)]
pub struct Node {
    /// The operator.
    pub op: Op,
    /// Operand references, in the operator's documented order.
    pub inputs: Vec<ValueRef>,
}

/// A computation graph. Nodes are stored in topological order: a node may
/// only reference inputs, parameters and *earlier* nodes.
#[derive(Debug, Clone, PartialEq)]
pub struct Graph {
    /// Role, which selects validation rules.
    pub role: GraphRole,
    /// Declared inputs.
    pub inputs: Vec<InputDecl>,
    /// Declared parameters.
    pub params: Vec<ParamDecl>,
    /// Nodes in topological order.
    pub nodes: Vec<Node>,
    /// Declared outputs.
    pub outputs: Vec<OutputDecl>,
}

impl Graph {
    /// An empty graph.
    pub fn new(role: GraphRole) -> Graph {
        Graph { role, inputs: Vec::new(), params: Vec::new(), nodes: Vec::new(), outputs: Vec::new() }
    }

    /// Declares an input and returns a reference to it.
    pub fn input(&mut self, name: impl Into<String>, kind: InputKind) -> ValueRef {
        self.inputs.push(InputDecl { name: name.into(), kind });
        ValueRef::Input(index(self.inputs.len() - 1))
    }

    /// Declares a parameter and returns a reference to it.
    pub fn param(&mut self, name: impl Into<String>, dims: &[u32]) -> ValueRef {
        self.params.push(ParamDecl { name: name.into(), dims: dims.to_vec() });
        ValueRef::Param(index(self.params.len() - 1))
    }

    /// Appends a node and returns a reference to its output.
    pub fn node(&mut self, op: Op, inputs: &[ValueRef]) -> ValueRef {
        self.nodes.push(Node { op, inputs: inputs.to_vec() });
        ValueRef::Node(index(self.nodes.len() - 1))
    }

    /// Declares an output.
    pub fn output(&mut self, name: impl Into<String>, value: ValueRef, kind: OutputKind) {
        self.outputs.push(OutputDecl { name: name.into(), value, kind });
    }
}

fn index(i: usize) -> u32 {
    u32::try_from(i).expect("graph element count exceeds u32")
}

fn invalid(msg: String) -> Error {
    Error::model_invalid(msg)
}

/// Checks the graph's structure: unique names, reference validity and
/// topological order, operator arity, where parameters may appear, and role
/// rules. Shape consistency is checked by [`crate::infer_shapes`].
pub fn validate(graph: &Graph) -> Result<()> {
    unique_names("input", graph.inputs.iter().map(|d| d.name.as_str()))?;
    unique_names("parameter", graph.params.iter().map(|d| d.name.as_str()))?;
    unique_names("output", graph.outputs.iter().map(|d| d.name.as_str()))?;
    if graph.outputs.is_empty() {
        return Err(invalid("graph has no outputs".into()));
    }
    for p in &graph.params {
        if p.dims.is_empty() || p.dims.contains(&0) {
            return Err(invalid(format!("parameter {:?} has invalid dimensions {:?}", p.name, p.dims)));
        }
    }

    let check_ref = |r: ValueRef, before_node: usize| -> Result<()> {
        let ok = match r {
            ValueRef::Input(i) => (i as usize) < graph.inputs.len(),
            ValueRef::Param(i) => (i as usize) < graph.params.len(),
            ValueRef::Node(i) => (i as usize) < before_node,
        };
        if ok { Ok(()) } else { Err(invalid(format!("reference {r:?} is out of range or not yet defined"))) }
    };

    for (i, node) in graph.nodes.iter().enumerate() {
        let (lo, hi) = node.op.arity();
        if node.inputs.len() < lo || node.inputs.len() > hi {
            return Err(invalid(format!(
                "node {i} ({}) has {} inputs, expected {lo}..={hi}",
                node.op.name(),
                node.inputs.len()
            )));
        }
        for (slot, &r) in node.inputs.iter().enumerate() {
            check_ref(r, i)?;
            let is_param = matches!(r, ValueRef::Param(_));
            if is_param != param_slot(&node.op, slot) && !param_or_value_slot(&node.op, slot) {
                return Err(invalid(format!(
                    "node {i} ({}) input {slot} must {}be a parameter",
                    node.op.name(),
                    if is_param { "not " } else { "" }
                )));
            }
        }
    }
    for out in &graph.outputs {
        check_ref(out.value, graph.nodes.len())?;
    }

    if graph.role == GraphRole::Main {
        check_main_locality(graph)?;
    }
    Ok(())
}

/// Slots that must hold parameters (weights, biases, slopes).
fn param_slot(op: &Op, slot: usize) -> bool {
    match op {
        Op::Conv2d { .. } | Op::Linear { .. } => slot >= 1,
        Op::PRelu => slot == 1,
        _ => false,
    }
}

/// Slots that accept either a parameter or a computed value.
fn param_or_value_slot(op: &Op, slot: usize) -> bool {
    matches!(op, Op::AffineChannel) && slot >= 1
}

fn unique_names<'a>(what: &str, names: impl Iterator<Item = &'a str>) -> Result<()> {
    let mut seen = std::collections::HashSet::new();
    for n in names {
        if n.is_empty() {
            return Err(invalid(format!("{what} with an empty name")));
        }
        if !seen.insert(n) {
            return Err(invalid(format!("duplicate {what} name {n:?}")));
        }
    }
    Ok(())
}

/// Main-role rule: no value derived from a spatial reduction may reach a
/// `Tensor` output.
fn check_main_locality(graph: &Graph) -> Result<()> {
    let mut tainted = vec![false; graph.nodes.len()];
    for (i, node) in graph.nodes.iter().enumerate() {
        tainted[i] = node.op.is_spatial_reduction()
            || node.inputs.iter().any(|r| matches!(r, ValueRef::Node(j) if tainted[*j as usize]));
    }
    for out in &graph.outputs {
        if out.kind == OutputKind::Tensor
            && let ValueRef::Node(j) = out.value
            && tainted[j as usize]
        {
            return Err(invalid(format!(
                "main graph output {:?} depends on a spatial reduction; this would break tile exactness",
                out.name
            )));
        }
    }
    Ok(())
}
