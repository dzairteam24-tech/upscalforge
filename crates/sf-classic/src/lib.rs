//! Classical (non-learned) image restoration and upscaling.
//!
//! This is the primary processing path of ScaleForge (ADR-0015). It needs no
//! model and no training. Every operation takes explicit, physically
//! meaningful parameters, which the strategy engine derives from analysis:
//!
//! - [`denoise`]: stationary wavelet shrinkage in an opponent colour space,
//!   calibrated to a measured noise sigma;
//! - [`deblock`]: adaptive smoothing across 8-pixel block boundaries,
//!   limited by the JPEG quantisation step;
//! - [`upscale`]: Lanczos-3 interpolation with an anti-ringing clamp;
//! - [`sharpen`]: unsharp masking of luma with a halo limiter;
//! - [`tone`]: white balance, exposure and contrast.
//!
//! All functions work on interleaved `f32` samples in 0–1 (encoded values)
//! with 1 or 3 colour channels. Alpha is handled by the caller.
//!
//! Limitation: classical methods restore only what the data supports. They
//! cannot synthesise lost detail; that is what learned models are for.

mod denoise;
mod enhance;

pub use denoise::{deblock, denoise};
pub use enhance::{Tone, sharpen, tone, upscale};

#[cfg(test)]
mod tests;
