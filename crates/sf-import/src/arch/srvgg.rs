//! The compact VGG-style network used by Real-ESRGAN "general" models: a
//! plain stack of 3×3 convolutions with per-channel PReLU, a final
//! depth-to-space upsampling, and a nearest-neighbour upsampled copy of the
//! input added as a residual.

use sf_core::{Error, Result};
use sf_graph::{Graph, GraphRole, InputKind, Op, OutputKind};

use super::{Builder, dims};
use crate::torch::StateDict;

/// Recognises the architecture from its tensor names.
pub fn matches(sd: &StateDict) -> bool {
    sd.contains_key("body.0.weight") && sd.get("body.1.weight").is_some_and(|t| t.dims.len() == 1)
}

/// Builds the graph. Returns (graph, weights, scale).
pub fn build(sd: &StateDict) -> Result<(Graph, Vec<Vec<f32>>, u32)> {
    let first = dims(sd, "body.0.weight")?;
    let (nf, in_ch) = (first[0], first[1]);
    // Layers alternate conv (even index) and PReLU (odd index); the last
    // conv has no activation.
    let last = (0..).take_while(|i| sd.contains_key(&format!("body.{i}.weight"))).count() - 1;
    if last % 2 != 0 || last < 2 {
        return Err(Error::invalid_input("import: unexpected SRVGG layer layout"));
    }
    let out = dims(sd, &format!("body.{last}.weight"))?[0];
    let r2 = out / in_ch;
    let scale = match r2 {
        4 => 2u32,
        16 => 4,
        _ => {
            return Err(Error::unsupported(format!(
                "import: SRVGG output of {out} channels for {in_ch} inputs"
            )));
        }
    };
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("image", InputKind::Spatial { channels: in_ch as u32, spacing_log2: 0 });
    let mut b = Builder::new(g, sd);
    let mut h = b.conv(x, "body.0", in_ch, nf, 3)?;
    let mut i = 1;
    while i < last {
        let slope = b.param(&format!("body.{i}.weight"), &[nf])?;
        h = b.graph.node(Op::PRelu, &[h, slope]);
        if i + 1 < last {
            h = b.conv(h, &format!("body.{}", i + 1), nf, nf, 3)?;
        }
        i += 2;
    }
    let y = b.conv(h, &format!("body.{last}"), nf, out, 3)?;
    let y = b.graph.node(Op::PixelShuffle { factor: scale }, &[y]);
    let mut base = x;
    for _ in 0..scale.trailing_zeros() {
        base = b.graph.node(Op::UpsampleNearest2, &[base]);
    }
    let y = b.graph.node(Op::Add, &[y, base]);
    let y = b.graph.node(Op::Clamp { lo: 0.0, hi: 1.0 }, &[y]);
    b.graph.output("image", y, OutputKind::Tensor);
    Ok((b.graph, b.weights, scale))
}
