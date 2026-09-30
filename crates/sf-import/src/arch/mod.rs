//! Graph builders for supported external architectures (ADR-0015).
//!
//! Each builder reads hyperparameters from the tensor shapes in a state
//! dictionary, checks every tensor it uses, and emits a ScaleForge graph
//! whose parameters are those tensors. The graphs use only the standard
//! operator set, so the whole ScaleForge engine (tiling, memory planning,
//! backends) applies to them unchanged.

pub mod rrdbnet;
pub mod srvgg;

use sf_core::{Error, Result};
use sf_graph::{Graph, Op, ValueRef};

use crate::torch::StateDict;

/// Collects parameters in graph order while building.
pub(crate) struct Builder<'a> {
    pub graph: Graph,
    pub weights: Vec<Vec<f32>>,
    sd: &'a StateDict,
}

impl<'a> Builder<'a> {
    pub fn new(graph: Graph, sd: &'a StateDict) -> Self {
        Builder { graph, weights: Vec::new(), sd }
    }

    /// Adds the tensor `name` as a parameter, checking its dimensions.
    pub fn param(&mut self, name: &str, dims: &[usize]) -> Result<ValueRef> {
        let t = self
            .sd
            .get(name)
            .ok_or_else(|| Error::invalid_input(format!("import: missing tensor {name:?}")))?;
        if t.dims != dims {
            return Err(Error::invalid_input(format!(
                "import: tensor {name:?} has dims {:?}, expected {dims:?}",
                t.dims
            )));
        }
        let d32: Vec<u32> = dims.iter().map(|&d| d as u32).collect();
        let r = self.graph.param(name, &d32);
        self.weights.push(t.data.clone());
        Ok(r)
    }

    /// A 3×3 (or k×k) convolution with bias named `prefix.weight` / `prefix.bias`.
    pub fn conv(&mut self, x: ValueRef, prefix: &str, cin: usize, cout: usize, k: usize) -> Result<ValueRef> {
        let w = self.param(&format!("{prefix}.weight"), &[cout, cin, k, k])?;
        let b = self.param(&format!("{prefix}.bias"), &[cout])?;
        Ok(self.graph.node(
            Op::Conv2d {
                out_channels: cout as u32,
                kernel: k as u32,
                stride: 1,
                depthwise: false,
                bias: true,
            },
            &[x, w, b],
        ))
    }
}

/// Dimensions of a tensor, or an error naming it.
pub(crate) fn dims<'s>(sd: &'s StateDict, name: &str) -> Result<&'s [usize]> {
    sd.get(name)
        .map(|t| t.dims.as_slice())
        .ok_or_else(|| Error::invalid_input(format!("import: missing tensor {name:?}")))
}
