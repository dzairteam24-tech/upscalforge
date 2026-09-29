//! Model runtime: loading validated `.sfm` models, exposing their metadata
//! and derived locality, and keeping their weights resident on a device.

use std::path::{Path, PathBuf};

use sf_compute::{Buffer, Event};
use sf_core::json::Object;
use sf_core::{Error, Limits, Result};
use sf_graph::sfm::{self, ModelFile};
use sf_graph::{Locality, locality};

use crate::vram::{Pool, TrackedBuffer, VramManager};

/// Metadata every ScaleForge model must declare.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelInfo {
    /// Display name.
    pub name: String,
    /// `scaleforge` (trained by our system) or `external` (ADR-0015).
    pub provenance: String,
    /// Licence identifier.
    pub licence: String,
    /// `commercial` or `non-commercial`.
    pub licence_scope: String,
    /// Output scale (1, 2, 4 or 8).
    pub scale: u32,
    /// Architecture identifier.
    pub architecture: String,
}

impl ModelInfo {
    fn from_metadata(m: &Object) -> Result<ModelInfo> {
        let s = |k: &str| -> Result<String> {
            m.get(k)
                .and_then(|v| v.as_str())
                .map(str::to_string)
                .ok_or_else(|| Error::model_invalid(format!("model metadata lacks {k:?}")))
        };
        let scale = m
            .get("scale")
            .and_then(|v| v.as_u64())
            .filter(|s| [1, 2, 4, 8].contains(s))
            .ok_or_else(|| Error::model_invalid("model metadata lacks a valid \"scale\""))?;
        let scope = s("licence_scope")?;
        if scope != "commercial" && scope != "non-commercial" {
            return Err(Error::model_invalid(format!("unknown licence_scope {scope:?}")));
        }
        Ok(ModelInfo {
            name: s("name")?,
            provenance: s("provenance")?,
            licence: s("licence")?,
            licence_scope: scope,
            scale: scale as u32,
            architecture: s("architecture")?,
        })
    }

    /// True for models not trained by ScaleForge.
    pub fn is_external(&self) -> bool {
        self.provenance != "scaleforge"
    }
}

/// A validated model file (host only).
#[derive(Debug, Clone)]
pub struct ModelHandle {
    /// Source path.
    pub path: PathBuf,
    /// Declared metadata.
    pub info: ModelInfo,
    /// Locality derived from the graph (never trusted from metadata).
    pub locality: Locality,
    /// Graph and weights.
    pub file: ModelFile,
}

impl ModelHandle {
    /// Reads and validates a model file.
    pub fn load(path: &Path, limits: &Limits) -> Result<ModelHandle> {
        let meta = std::fs::metadata(path).map_err(|e| Error::from(e).context(path.display()))?;
        if meta.len() > limits.max_model_bytes {
            return Err(Error::limit_exceeded(format!("{} exceeds the model size limit", path.display())));
        }
        let bytes = std::fs::read(path).map_err(|e| Error::from(e).context(path.display()))?;
        let file = sfm::read(&bytes, limits).map_err(|e| e.context(path.display()))?;
        let info = ModelInfo::from_metadata(&file.metadata)?;
        let locality = locality(&file.graph)?;
        let out_scale = locality.outputs.first().copied().flatten().map(|o| 1u32 << (-o.spacing_log2).max(0));
        if out_scale != Some(info.scale) {
            return Err(Error::model_invalid(format!(
                "declared scale {} does not match the graph's output scale {:?}",
                info.scale, out_scale
            )));
        }
        Ok(ModelHandle { path: path.to_path_buf(), info, locality, file })
    }

    /// Uploads the weights to the device managed by `vram`.
    pub fn upload(&self, vram: &VramManager) -> Result<ResidentModel> {
        let mut queue = vram.device().create_queue()?;
        let mut weights = Vec::with_capacity(self.file.weights.len());
        for w in &self.file.weights {
            let b = vram.allocate(Pool::Weights, w.len() as u64 * 4)?;
            queue.upload(b.buffer(), w)?;
            weights.push(b);
        }
        let ready = queue.signal();
        Ok(ResidentModel { weights, ready })
    }
}

/// Weights resident on a device; released when dropped.
pub struct ResidentModel {
    weights: Vec<TrackedBuffer>,
    ready: Event,
}

impl ResidentModel {
    /// Weight buffers in parameter order.
    pub fn buffers(&self) -> Vec<&Buffer> {
        self.weights.iter().map(TrackedBuffer::buffer).collect()
    }

    /// Event marking upload completion.
    pub fn ready(&self) -> Event {
        self.ready
    }
}

/// One entry of a model directory listing.
#[derive(Debug, Clone)]
pub struct CatalogEntry {
    /// File path.
    pub path: PathBuf,
    /// Metadata, or the reason the file is not usable.
    pub info: std::result::Result<ModelInfo, String>,
}

/// Lists `.sfm` files in a directory, validating each. Invalid files are
/// reported, not fatal.
pub fn scan(dir: &Path, limits: &Limits) -> Result<Vec<CatalogEntry>> {
    let mut out = Vec::new();
    let rd = std::fs::read_dir(dir).map_err(|e| Error::from(e).context(dir.display()))?;
    let mut paths: Vec<PathBuf> = rd
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "sfm"))
        .collect();
    paths.sort();
    for p in paths {
        let info = ModelHandle::load(&p, limits).map(|h| h.info).map_err(|e| e.to_string());
        out.push(CatalogEntry { path: p, info });
    }
    Ok(out)
}
