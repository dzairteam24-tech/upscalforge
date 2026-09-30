//! Image analysis for ScaleForge.
//!
//! [`analyze`] measures an image before processing. Every value in the
//! [`AnalysisReport`] names the estimator that produced it. Quantities no
//! estimator exists for yet are listed in `unavailable`, never guessed.
//! [`metrics`] provides full-reference quality metrics.
//!
//! Units: intensities are 8-bit code values (0–255) of the encoded image.

pub mod metrics;
mod plane;

use sf_image::{Image, jpeg};

pub use plane::Plane;

/// A measured value with the estimator that produced it.
#[derive(Debug, Clone, PartialEq)]
pub struct Measurement {
    /// The value.
    pub value: f64,
    /// Estimator identifier and version.
    pub estimator: &'static str,
}

/// Luma exposure statistics.
#[derive(Debug, Clone, PartialEq)]
pub struct Exposure {
    /// 1st, 50th and 99th luma percentiles.
    pub p1: f64,
    /// Median luma.
    pub p50: f64,
    /// 99th percentile.
    pub p99: f64,
    /// Fraction of pixels at or below 1.
    pub clipped_dark: f64,
    /// Fraction of pixels at or above 254.
    pub clipped_bright: f64,
}

/// The result of [`analyze`].
#[derive(Debug, Clone, PartialEq)]
pub struct AnalysisReport {
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// Luma noise standard deviation.
    pub noise_sigma: Measurement,
    /// Noise by intensity band: (band centre, sigma), for bands with enough
    /// flat area.
    pub noise_by_level: Vec<(f64, f64)>,
    /// JPEG quality estimated from the file's own quantisation tables, when
    /// the source is a JPEG whose tables follow the common scaling rule.
    pub jpeg_quality: Option<Measurement>,
    /// Blocking strength on an 8-pixel grid: ~1 none, > 1.3 visible.
    pub blockiness: Measurement,
    /// Median 10–90 % edge rise distance in pixels (larger = blurrier).
    pub edge_width: Option<Measurement>,
    /// Exposure statistics.
    pub exposure: Exposure,
    /// RMS contrast of luma (0–1).
    pub contrast: f64,
    /// Grey-world colour balance in linear light: (R/G, B/G) of mean
    /// mid-tone colour; (1, 1) is neutral. `None` for greyscale.
    pub color_balance: Option<(f64, f64)>,
    /// Fraction of 8×8 blocks with detail clearly above the noise.
    pub texture_density: f64,
    /// Quantities requested by the specification without an estimator yet.
    pub unavailable: Vec<(&'static str, &'static str)>,
}

/// Analyses an image.
pub fn analyze(image: &Image) -> AnalysisReport {
    let luma = Plane::luma(&image.buffer);
    let noise = plane::noise(&luma);
    let exposure = plane::exposure(&luma);
    let jpeg_quality = image.meta.jpeg.as_ref().and_then(|info| {
        let table = info.quant_tables.iter().find(|t| t.0 == 0)?;
        let (q, err) = jpeg::estimate_quality(&table.1)?;
        (err < 2.0).then_some(Measurement { value: f64::from(q), estimator: "quant-table-fit/1" })
    });
    AnalysisReport {
        width: image.buffer.width(),
        height: image.buffer.height(),
        noise_sigma: Measurement { value: noise.0, estimator: "flat-block-laplacian/1" },
        noise_by_level: noise.1,
        jpeg_quality,
        blockiness: Measurement { value: plane::blockiness(&luma), estimator: "grid-8-ratio/1" },
        edge_width: plane::edge_width(&luma)
            .map(|v| Measurement { value: v, estimator: "edge-rise-10-90/1" }),
        exposure,
        contrast: plane::rms_contrast(&luma),
        color_balance: plane::color_balance(&image.buffer),
        texture_density: plane::texture_density(&luma, noise.0),
        unavailable: vec![
            ("face_presence", "requires a trained face detector (INCOMPLETE)"),
            ("motion_blur_direction", "estimator not yet validated (research)"),
            ("effective_resolution", "estimator not yet validated (research)"),
            ("subject_characteristics", "requires a trained segmentation model (INCOMPLETE)"),
        ],
    }
}

#[cfg(test)]
mod tests;
