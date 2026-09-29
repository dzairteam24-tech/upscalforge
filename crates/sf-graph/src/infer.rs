//! Shape inference.

use sf_core::{Error, Result};

use crate::graph::{Graph, InputKind, ValueRef, validate};
use crate::op::Op;
use crate::shape::Shape;

/// Shapes of all inputs and node outputs for one concrete set of inputs.
#[derive(Debug, Clone, PartialEq)]
pub struct Shapes {
    /// Shape of each graph input.
    pub inputs: Vec<Shape>,
    /// Output shape of each node.
    pub nodes: Vec<Shape>,
}

impl Shapes {
    /// Shape of a value. One-dimensional parameters act as `[1, C]` vectors.
    /// Other parameters have no value shape.
    pub fn value(&self, graph: &Graph, r: ValueRef) -> Option<Shape> {
        match r {
            ValueRef::Input(i) => self.inputs.get(i as usize).copied(),
            ValueRef::Node(i) => self.nodes.get(i as usize).copied(),
            ValueRef::Param(i) => match graph.params.get(i as usize)?.dims.as_slice() {
                [c] => Some(Shape::Vector { n: 1, c: *c }),
                _ => None,
            },
        }
    }
}

fn bad(node: usize, op: &Op, msg: impl std::fmt::Display) -> Error {
    Error::model_invalid(format!("node {node} ({}): {msg}", op.name()))
}

/// Validates the graph, then infers every node's output shape for the given
/// input shapes.
///
/// Inputs that contradict their declarations give `InvalidInput`. An
/// incompatibility found at a node (including one caused by an unusual
/// combination of valid inputs) gives `ModelInvalid`, naming the node.
pub fn infer_shapes(graph: &Graph, inputs: &[Shape]) -> Result<Shapes> {
    validate(graph)?;
    if inputs.len() != graph.inputs.len() {
        return Err(Error::invalid_input(format!(
            "graph has {} inputs, {} shapes given",
            graph.inputs.len(),
            inputs.len()
        )));
    }
    for (decl, &shape) in graph.inputs.iter().zip(inputs) {
        let ok = match (decl.kind, shape) {
            (InputKind::Spatial { channels, .. }, Shape::Spatial { n, c, h, w }) => {
                c == channels && n > 0 && h > 0 && w > 0
            }
            (InputKind::Vector { channels }, Shape::Vector { n, c }) => c == channels && n > 0,
            (InputKind::Scalar, Shape::Scalar) => true,
            _ => false,
        };
        if !ok {
            return Err(Error::invalid_input(format!(
                "input {:?} expects {:?}, got {shape}",
                decl.name, decl.kind
            )));
        }
    }

    let mut shapes = Shapes { inputs: inputs.to_vec(), nodes: Vec::with_capacity(graph.nodes.len()) };
    for (i, node) in graph.nodes.iter().enumerate() {
        let op = &node.op;
        let value = |slot: usize| -> Result<Shape> {
            shapes
                .value(graph, node.inputs[slot])
                .ok_or_else(|| bad(i, op, format!("input {slot} has no tensor shape")))
        };
        let param_dims = |slot: usize| -> &[u32] {
            match node.inputs[slot] {
                ValueRef::Param(p) => &graph.params[p as usize].dims,
                _ => &[],
            }
        };
        let spatial = |slot: usize| -> Result<(u32, u32, u32, u32)> {
            match value(slot)? {
                Shape::Spatial { n, c, h, w } => Ok((n, c, h, w)),
                other => Err(bad(i, op, format!("input {slot} must be spatial, got {other}"))),
            }
        };
        let even = |h: u32, w: u32| -> Result<()> {
            if h.is_multiple_of(2) && w.is_multiple_of(2) {
                Ok(())
            } else {
                Err(bad(i, op, format!("requires even height and width, got {h}x{w}")))
            }
        };

        let out = match op {
            Op::Conv2d { out_channels, kernel, stride, depthwise, bias } => {
                let (n, c, h, w) = spatial(0)?;
                if ![1, 3, 5, 7].contains(kernel) {
                    return Err(bad(i, op, format!("kernel {kernel} is not one of 1, 3, 5, 7")));
                }
                if ![1, 2].contains(stride) {
                    return Err(bad(i, op, format!("stride {stride} is not 1 or 2")));
                }
                if *stride == 2 {
                    even(h, w)?;
                }
                let expected: Vec<u32> = if *depthwise {
                    if *out_channels != c {
                        return Err(bad(i, op, "depthwise convolution must keep the channel count"));
                    }
                    vec![c, 1, *kernel, *kernel]
                } else {
                    vec![*out_channels, c, *kernel, *kernel]
                };
                if param_dims(1) != expected.as_slice() {
                    return Err(bad(
                        i,
                        op,
                        format!("weight dims {:?}, expected {expected:?}", param_dims(1)),
                    ));
                }
                if *bias && param_dims(2) != [*out_channels] {
                    return Err(bad(
                        i,
                        op,
                        format!("bias dims {:?}, expected [{out_channels}]", param_dims(2)),
                    ));
                }
                Shape::Spatial { n, c: *out_channels, h: h / stride, w: w / stride }
            }
            Op::AvgPool2 => {
                let (n, c, h, w) = spatial(0)?;
                even(h, w)?;
                Shape::Spatial { n, c, h: h / 2, w: w / 2 }
            }
            Op::PixelUnshuffle2 => {
                let (n, c, h, w) = spatial(0)?;
                even(h, w)?;
                let c4 = c.checked_mul(4).ok_or_else(|| bad(i, op, "channel overflow"))?;
                Shape::Spatial { n, c: c4, h: h / 2, w: w / 2 }
            }
            Op::UpsampleNearest2 | Op::PixelShuffle2 => {
                let (n, c, h, w) = spatial(0)?;
                let c = if matches!(op, Op::PixelShuffle2) {
                    if !c.is_multiple_of(4) {
                        return Err(bad(i, op, format!("channels {c} not divisible by 4")));
                    }
                    c / 4
                } else {
                    c
                };
                let h2 = h.checked_mul(2).ok_or_else(|| bad(i, op, "height overflow"))?;
                let w2 = w.checked_mul(2).ok_or_else(|| bad(i, op, "width overflow"))?;
                Shape::Spatial { n, c, h: h2, w: w2 }
            }
            Op::Add | Op::Sub | Op::Mul => {
                let (a, b) = (value(0)?, value(1)?);
                if a != b || a == Shape::Scalar {
                    return Err(bad(i, op, format!("operand shapes {a} and {b} must match")));
                }
                a
            }
            Op::AffineChannel => {
                let (n, c, h, w) = spatial(0)?;
                for slot in [1, 2] {
                    match value(slot)? {
                        Shape::Vector { n: vn, c: vc } if vc == c && (vn == 1 || vn == n) => {}
                        other => {
                            return Err(bad(i, op, format!("input {slot} {other} must be [1 or {n}, {c}]")));
                        }
                    }
                }
                Shape::Spatial { n, c, h, w }
            }
            Op::Activation(_) | Op::Clamp { .. } => {
                if let Op::Clamp { lo, hi } = op
                    && !(lo.is_finite() && hi.is_finite() && lo <= hi)
                {
                    return Err(bad(i, op, format!("invalid bounds [{lo}, {hi}]")));
                }
                if let Op::Activation(crate::Activation::LeakyRelu(s)) = op
                    && !s.is_finite()
                {
                    return Err(bad(i, op, "non-finite slope"));
                }
                match value(0)? {
                    Shape::Scalar => return Err(bad(i, op, "scalar operand")),
                    s => s,
                }
            }
            Op::PRelu => {
                let (n, c, h, w) = spatial(0)?;
                if param_dims(1) != [c] {
                    return Err(bad(i, op, format!("slope dims {:?}, expected [{c}]", param_dims(1))));
                }
                Shape::Spatial { n, c, h, w }
            }
            Op::ScaleScalar => {
                if value(1)? != Shape::Scalar {
                    return Err(bad(i, op, "second operand must be a scalar input"));
                }
                match value(0)? {
                    Shape::Scalar => return Err(bad(i, op, "first operand must be a tensor")),
                    s => s,
                }
            }
            Op::Concat => {
                let (n, mut total, h, w) = spatial(0)?;
                for slot in 1..node.inputs.len() {
                    let (n2, c2, h2, w2) = spatial(slot)?;
                    if (n2, h2, w2) != (n, h, w) {
                        return Err(bad(i, op, "operands differ in batch or spatial size"));
                    }
                    total = total.checked_add(c2).ok_or_else(|| bad(i, op, "channel overflow"))?;
                }
                Shape::Spatial { n, c: total, h, w }
            }
            Op::SliceChannels { start, len } => {
                let (n, c, h, w) = spatial(0)?;
                if *len == 0 || start.checked_add(*len).is_none_or(|end| end > c) {
                    return Err(bad(i, op, format!("slice [{start}, +{len}) outside {c} channels")));
                }
                Shape::Spatial { n, c: *len, h, w }
            }
            Op::Crop { top, left, bottom, right } => {
                let (n, c, h, w) = spatial(0)?;
                let vert = u64::from(*top) + u64::from(*bottom);
                let horiz = u64::from(*left) + u64::from(*right);
                if vert >= u64::from(h) || horiz >= u64::from(w) {
                    return Err(bad(i, op, format!("crop removes the whole {h}x{w} tensor")));
                }
                Shape::Spatial { n, c, h: h - top - bottom, w: w - left - right }
            }
            Op::GlobalMean => {
                let (n, c, _, _) = spatial(0)?;
                Shape::Vector { n, c }
            }
            Op::Linear { out_features, bias } => {
                let (n, c) = match value(0)? {
                    Shape::Vector { n, c } => (n, c),
                    other => return Err(bad(i, op, format!("input must be a vector, got {other}"))),
                };
                if param_dims(1) != [*out_features, c] {
                    return Err(bad(
                        i,
                        op,
                        format!("weight dims {:?}, expected [{out_features}, {c}]", param_dims(1)),
                    ));
                }
                if *bias && param_dims(2) != [*out_features] {
                    return Err(bad(
                        i,
                        op,
                        format!("bias dims {:?}, expected [{out_features}]", param_dims(2)),
                    ));
                }
                Shape::Vector { n, c: *out_features }
            }
        };
        if out.elements() == 0 {
            return Err(bad(i, op, "produces an empty tensor"));
        }
        shapes.nodes.push(out);
    }
    Ok(shapes)
}
