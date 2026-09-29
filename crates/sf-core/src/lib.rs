//! Foundation types shared by every ScaleForge crate.
//!
//! This crate has no dependencies. It provides:
//! - [`Error`] / [`ErrorKind`]: the error taxonomy used across the engine;
//! - [`Limits`]: resource limits enforced by every parser and allocator;
//! - [`geometry`]: overflow-checked sizes and rectangles;
//! - [`Scale`] and [`DType`];
//! - [`json`]: a strict, limit-aware JSON reader and writer;
//! - [`Rng`]: a small deterministic generator for reproducible seeding;
//! - [`CancelToken`] and [`ProgressSink`] for long-running jobs.

pub mod cancel;
pub mod dtype;
pub mod error;
pub mod geometry;
pub mod json;
pub mod limits;
pub mod progress;
pub mod rng;
pub mod scale;

pub use cancel::CancelToken;
pub use dtype::DType;
pub use error::{DeviceErrorKind, Error, ErrorKind, Result};
pub use geometry::{Rect, Size};
pub use limits::Limits;
pub use progress::{NoProgress, ProgressEvent, ProgressSink};
pub use rng::Rng;
pub use scale::Scale;
