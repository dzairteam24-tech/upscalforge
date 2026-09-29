//! The ScaleForge engine and public API.
//!
//! [`Engine`] runs [`JobRequest`]s and returns [`JobReport`]s explaining
//! every decision. Interfaces (CLI, a future GUI) use only this API.

pub mod export;
pub mod hostmem;
pub mod imageops;
mod pipeline;
pub mod qc;
pub mod report;
pub mod runtime;
pub mod strategy;
pub mod tiling;
pub mod vram;

pub use pipeline::{Engine, EngineConfig, ExportProfile, JobReport, JobRequest};
pub use strategy::{Controls, Mode};
