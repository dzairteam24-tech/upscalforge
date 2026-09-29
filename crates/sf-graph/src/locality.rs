//! Receptive-field and alignment analysis.
//!
//! For every spatial value, the analysis tracks its pixel **spacing** in
//! primary-input pixels (a power of two, `2^e`), and its **radius**: how
//! far, in primary-input pixels, the inputs that influence one output pixel
//! extend beyond that pixel's own footprint.
//!
//! Tiling uses these derived values. A halo of `ceil(radius)` input pixels
//! around a tile core makes every core pixel see exactly the inputs it would
//! see in a whole-image run. Tile origins must be multiples of `alignment`
//! so that every downsampled grid lines up.
//!
//! Rules per operator (with `S` the operand's spacing):
//! - conv `k`, stride `s`: `r + (k / 2)·S`; spacing `S·s`. A stride-2
//!   window reaches less far on one side, so the symmetric bound is
//!   conservative.
//! - 2×2 average pool, space-to-depth: `r` (the window is exactly the new
//!   footprint); spacing `2S`.
//! - nearest ×2 upsample: `r + S/2`; spacing `S/2`. Depth-to-space by
//!   `f`: `r + S·(f−1)/f`; spacing `S/f`. (The output pixel covers 1/f of
//!   its source pixel, so the source reaches at most `S·(f−1)/f` beyond it.)
//! - element-wise and channel ops: the maximum over operands, which must
//!   share one spacing.

use sf_core::{Error, Result};

use crate::graph::{Graph, InputKind, OutputKind, ValueRef, validate};
use crate::op::Op;

/// Locality of one tensor output.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct OutputLocality {
    /// log2 of the output's pixel spacing in primary-input pixels
    /// (−2 for a 4x upscaler's output).
    pub spacing_log2: i32,
    /// Receptive radius beyond the pixel footprint, in primary-input pixels.
    pub radius: f64,
}

impl OutputLocality {
    /// Halo in primary-input pixels needed for exact tiling.
    pub fn halo(&self) -> u32 {
        self.radius.ceil() as u32
    }
}

/// Locality of a graph.
#[derive(Debug, Clone, PartialEq)]
pub struct Locality {
    /// One entry per graph output (`None` for non-spatial outputs).
    pub outputs: Vec<Option<OutputLocality>>,
    /// Tile origins and canonical image sizes must be multiples of this.
    pub alignment: u32,
}

impl Locality {
    /// The largest halo over all spatial tensor outputs.
    pub fn max_halo(&self) -> u32 {
        self.outputs.iter().flatten().map(OutputLocality::halo).max().unwrap_or(0)
    }
}

#[derive(Clone, Copy)]
struct Spatial {
    e: i32,
    r: f64,
}

fn spacing(e: i32) -> f64 {
    2f64.powi(e)
}

/// Derives the locality of a `Main` graph from its structure.
pub fn locality(graph: &Graph) -> Result<Locality> {
    validate(graph)?;
    let mut max_e = 0i32;
    let input_loc: Vec<Option<Spatial>> = graph
        .inputs
        .iter()
        .map(|d| match d.kind {
            InputKind::Spatial { spacing_log2, .. } => {
                max_e = max_e.max(spacing_log2);
                Some(Spatial { e: spacing_log2, r: 0.0 })
            }
            _ => None,
        })
        .collect();

    let mut node_loc: Vec<Option<Spatial>> = Vec::with_capacity(graph.nodes.len());
    for (i, node) in graph.nodes.iter().enumerate() {
        let get = |r: ValueRef| match r {
            ValueRef::Input(j) => input_loc[j as usize],
            ValueRef::Node(j) => node_loc[j as usize],
            ValueRef::Param(_) => None,
        };
        let first = get(node.inputs[0]);
        let loc = match &node.op {
            Op::Conv2d { kernel, stride, .. } => {
                let s = first.ok_or_else(|| non_spatial(i))?;
                Some(Spatial {
                    e: s.e + stride.trailing_zeros() as i32,
                    r: s.r + f64::from(kernel / 2) * spacing(s.e),
                })
            }
            Op::AvgPool2 => {
                let s = first.ok_or_else(|| non_spatial(i))?;
                Some(Spatial { e: s.e + 1, r: s.r })
            }
            Op::PixelUnshuffle { factor } => {
                let s = first.ok_or_else(|| non_spatial(i))?;
                Some(Spatial { e: s.e + factor.trailing_zeros() as i32, r: s.r })
            }
            Op::UpsampleNearest2 => {
                let s = first.ok_or_else(|| non_spatial(i))?;
                Some(Spatial { e: s.e - 1, r: s.r + spacing(s.e) / 2.0 })
            }
            Op::PixelShuffle { factor } => {
                let s = first.ok_or_else(|| non_spatial(i))?;
                let f = f64::from(*factor);
                Some(Spatial {
                    e: s.e - factor.trailing_zeros() as i32,
                    r: s.r + spacing(s.e) * (f - 1.0) / f,
                })
            }
            Op::GlobalMean | Op::Linear { .. } => None,
            _ => {
                // Element-wise / channel operators over any spatial operands.
                let mut acc: Option<Spatial> = None;
                for &r in &node.inputs {
                    if let Some(s) = get(r) {
                        acc = Some(match acc {
                            None => s,
                            Some(a) if a.e == s.e => Spatial { e: a.e, r: a.r.max(s.r) },
                            Some(a) => {
                                return Err(Error::model_invalid(format!(
                                    "node {i} ({}) combines spacings 2^{} and 2^{}",
                                    node.op.name(),
                                    a.e,
                                    s.e
                                )));
                            }
                        });
                    }
                }
                acc
            }
        };
        if let Some(s) = loc {
            max_e = max_e.max(s.e);
        }
        node_loc.push(loc);
    }

    let outputs = graph
        .outputs
        .iter()
        .map(|o| {
            if o.kind != OutputKind::Tensor {
                return None;
            }
            let s = match o.value {
                ValueRef::Input(j) => input_loc[j as usize],
                ValueRef::Node(j) => node_loc[j as usize],
                ValueRef::Param(_) => None,
            }?;
            Some(OutputLocality { spacing_log2: s.e, radius: s.r })
        })
        .collect();
    let alignment =
        1u32.checked_shl(max_e.max(0) as u32).ok_or_else(|| Error::model_invalid("alignment overflow"))?;
    Ok(Locality { outputs, alignment })
}

fn non_spatial(node: usize) -> Error {
    Error::model_invalid(format!("node {node}: spatial operator applied to a non-spatial value"))
}
