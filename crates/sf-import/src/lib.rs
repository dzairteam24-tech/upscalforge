//! Import of external pretrained weights (ADR-0015).
//!
//! External models are an optional, clearly labelled add-on. They run on
//! the ScaleForge engine, but they are not ScaleForge models. This crate
//! converts supported PyTorch weight files into `.sfm` files that record
//! their provenance, licence and licence scope.
//!
//! Supported architectures: the Real-ESRGAN RRDB network (x4plus, x2plus)
//! and the compact SRVGG network (general models). Attention-based
//! architectures (SwinIR, HAT) need additional operators and are
//! **INCOMPLETE**.

pub mod arch;
pub mod pickle;
pub mod torch;
mod zip;

use sf_core::json::Object;
use sf_core::{Error, Limits, Result};
use sf_graph::sfm::{self, ModelFile};

/// Provenance and licensing recorded in an imported model.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Provenance {
    /// Model family, e.g. "Real-ESRGAN".
    pub family: String,
    /// Licence identifier, e.g. "BSD-3-Clause".
    pub licence: String,
    /// `commercial` or `non-commercial`.
    pub licence_scope: String,
    /// Where the weights came from (URL or description).
    pub source: String,
}

/// Known external families and their verified licences
/// (`docs/design/06-external-models.md`).
pub fn known_provenance(architecture: &str) -> Option<Provenance> {
    match architecture {
        "rrdbnet" | "srvgg" => Some(Provenance {
            family: "Real-ESRGAN".into(),
            licence: "BSD-3-Clause".into(),
            licence_scope: "commercial".into(),
            source: "https://github.com/xinntao/Real-ESRGAN (official releases)".into(),
        }),
        _ => None,
    }
}

/// The result of an import.
#[derive(Debug, Clone)]
pub struct Imported {
    /// Architecture identifier ("rrdbnet" or "srvgg").
    pub architecture: &'static str,
    /// Output scale.
    pub scale: u32,
    /// The model, ready to write as `.sfm`.
    pub model: ModelFile,
}

/// Converts PyTorch weight bytes into a ScaleForge model. `name` is the
/// model's display name; `sha256` of the source file is recorded.
pub fn import_pth(bytes: &[u8], name: &str, limits: &Limits) -> Result<Imported> {
    let sd = torch::load(bytes, limits)?;
    let (architecture, (graph, weights, scale)) = if arch::rrdbnet::matches(&sd) {
        ("rrdbnet", arch::rrdbnet::build(&sd)?)
    } else if arch::srvgg::matches(&sd) {
        ("srvgg", arch::srvgg::build(&sd)?)
    } else {
        return Err(Error::unsupported(
            "import: architecture not recognised (supported: Real-ESRGAN RRDBNet and SRVGG; SwinIR/HAT are INCOMPLETE)",
        ));
    };
    let prov = known_provenance(architecture).expect("known architecture");
    let mut m = Object::new();
    m.insert("name", name);
    m.insert("provenance", "external");
    m.insert("family", prov.family.as_str());
    m.insert("architecture", architecture);
    m.insert("licence", prov.licence.as_str());
    m.insert("licence_scope", prov.licence_scope.as_str());
    m.insert("source", prov.source.as_str());
    m.insert("source_sha256", sf_core::sha256::sha256_hex(bytes));
    m.insert("scale", u64::from(scale));
    m.insert("input", "rgb, encoded values in [0, 1]");
    m.insert(
        "training",
        "pretrained by a third party; not trained by ScaleForge (ADR-0015 optional external model)",
    );
    let model = ModelFile { metadata: m, graph, weights };
    // Round-trip through the writer's validation.
    sfm::write(&model)?;
    Ok(Imported { architecture, scale, model })
}

#[cfg(test)]
mod tests;
