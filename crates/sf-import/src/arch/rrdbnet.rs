//! The RRDB network used by the Real-ESRGAN "x4plus"/"x2plus" models: a
//! feature extractor of residual-in-residual dense blocks followed by two
//! nearest-neighbour ×2 upsampling stages.
//!
//! The ×2 and ×1 variants first apply space-to-depth (factor 2 or 4) to
//! the input, so the fixed ×4 upsampler yields an overall ×2 or ×1.

use sf_core::{Error, Result};
use sf_graph::{Activation, Graph, GraphRole, InputKind, Op, OutputKind, ValueRef};

use super::{Builder, dims};
use crate::torch::StateDict;

const SLOPE: f32 = 0.2;
/// Residual scaling inside the dense blocks.
const RESIDUAL: f32 = 0.2;

/// Recognises the architecture from its tensor names.
pub fn matches(sd: &StateDict) -> bool {
    sd.contains_key("conv_first.weight") && sd.contains_key("body.0.rdb1.conv1.weight")
}

fn lrelu(b: &mut Builder<'_>, x: ValueRef) -> ValueRef {
    b.graph.node(Op::Activation(Activation::LeakyRelu(SLOPE)), &[x])
}

fn scaled_residual(b: &mut Builder<'_>, out: ValueRef, x: ValueRef) -> ValueRef {
    let s = b.graph.node(Op::ScaleConst { factor: RESIDUAL }, &[out]);
    b.graph.node(Op::Add, &[s, x])
}

fn dense_block(b: &mut Builder<'_>, x: ValueRef, prefix: &str, nf: usize, gc: usize) -> Result<ValueRef> {
    let mut feats = vec![x];
    let mut channels = nf;
    for i in 1..=4 {
        let input = if feats.len() == 1 { feats[0] } else { b.graph.node(Op::Concat, &feats) };
        let y = b.conv(input, &format!("{prefix}.conv{i}"), channels, gc, 3)?;
        feats.push(lrelu(b, y));
        channels += gc;
    }
    let input = b.graph.node(Op::Concat, &feats);
    let y = b.conv(input, &format!("{prefix}.conv5"), channels, nf, 3)?;
    Ok(scaled_residual(b, y, x))
}

/// Builds the graph. Returns (graph, weights, overall scale).
pub fn build(sd: &StateDict) -> Result<(Graph, Vec<Vec<f32>>, u32)> {
    let first = dims(sd, "conv_first.weight")?;
    let (nf, in_ch) = (first[0], first[1]);
    let gc = dims(sd, "body.0.rdb1.conv1.weight")?[0];
    let out_ch = dims(sd, "conv_last.weight")?[0];
    let blocks = (0..).take_while(|i| sd.contains_key(&format!("body.{i}.rdb1.conv1.weight"))).count();
    let (unshuffle, scale) = match in_ch {
        3 => (None, 4u32),
        12 => (Some(2), 2),
        48 => (Some(4), 1),
        other => return Err(Error::unsupported(format!("import: RRDBNet with {other} input channels"))),
    };
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("image", InputKind::Spatial { channels: 3, spacing_log2: 0 });
    let mut b = Builder::new(g, sd);
    let mut h = x;
    if let Some(f) = unshuffle {
        h = b.graph.node(Op::PixelUnshuffle { factor: f }, &[h]);
    }
    let feat = b.conv(h, "conv_first", in_ch, nf, 3)?;
    let mut body = feat;
    for i in 0..blocks {
        let inner = body;
        let mut y = inner;
        for r in 1..=3 {
            y = dense_block(&mut b, y, &format!("body.{i}.rdb{r}"), nf, gc)?;
        }
        body = scaled_residual(&mut b, y, inner);
    }
    let body = b.conv(body, "conv_body", nf, nf, 3)?;
    let mut f = b.graph.node(Op::Add, &[feat, body]);
    for up in ["conv_up1", "conv_up2"] {
        let u = b.graph.node(Op::UpsampleNearest2, &[f]);
        let c = b.conv(u, up, nf, nf, 3)?;
        f = lrelu(&mut b, c);
    }
    let hr = b.conv(f, "conv_hr", nf, nf, 3)?;
    let hr = lrelu(&mut b, hr);
    let out = b.conv(hr, "conv_last", nf, out_ch, 3)?;
    let out = b.graph.node(Op::Clamp { lo: 0.0, hi: 1.0 }, &[out]);
    b.graph.output("image", out, OutputKind::Tensor);
    Ok((b.graph, b.weights, scale))
}
