//! Source consistency and quality control.
//!
//! Consistency: the output, downscaled back to the input size, should agree
//! with the input at low frequencies. [`consistency_correct`] adds the
//! (upsampled) low-frequency residual, weighted per mode. [`check`]
//! measures what remains, together with colour shift and halo overshoot,
//! and compares each against a per-mode limit.

use sf_image::resample::{Filter, resize};

use crate::imageops::Pixels;
use crate::strategy::Mode;

/// Low-pass scale of the consistency comparison, in input pixels.
const LOWPASS_SIGMA: f32 = 1.0;

fn per_channel_lowpass(p: &Pixels) -> Vec<Vec<f32>> {
    let planar = p.to_planar();
    let n = p.width * p.height;
    (0..p.channels)
        .map(|c| sf_classic::gaussian(&planar[c * n..(c + 1) * n], p.width, p.height, LOWPASS_SIGMA))
        .collect()
}

fn downscaled(out: &Pixels, w: usize, h: usize) -> Pixels {
    Pixels {
        width: w,
        height: h,
        channels: out.channels,
        data: resize(&out.data, out.width, out.height, out.channels, w, h, Filter::Area),
    }
}

/// Low-frequency residual `LP(input) − LP(downscale(output))`, per channel.
fn residual(input: &Pixels, output: &Pixels) -> Vec<Vec<f32>> {
    let d = downscaled(output, input.width, input.height);
    let (a, b) = (per_channel_lowpass(input), per_channel_lowpass(&d));
    a.iter().zip(&b).map(|(x, y)| x.iter().zip(y).map(|(p, q)| p - q).collect()).collect()
}

/// Adds `weight` × the upsampled low-frequency residual to `output`.
pub fn consistency_correct(input: &Pixels, output: &mut Pixels, weight: f32) {
    if weight <= 0.0 || input.channels != output.channels {
        return;
    }
    let r = residual(input, output);
    let n = input.width * input.height;
    let mut planar = vec![0f32; n * input.channels];
    for (c, plane) in r.iter().enumerate() {
        planar[c * n..(c + 1) * n].copy_from_slice(plane);
    }
    let inter = Pixels::from_planar(&planar, input.width, input.height, input.channels);
    let up = resize(
        &inter.data,
        input.width,
        input.height,
        input.channels,
        output.width,
        output.height,
        Filter::Bilinear,
    );
    for (o, u) in output.data.iter_mut().zip(up) {
        *o += weight * u;
    }
}

/// Result of one check.
#[derive(Debug, Clone, PartialEq)]
pub struct Check {
    /// Check name.
    pub name: &'static str,
    /// Measured value.
    pub value: f64,
    /// Limit for the mode.
    pub limit: f64,
    /// `true` if the value is within the limit.
    pub pass: bool,
    /// What the value means.
    pub unit: &'static str,
}

/// Quality-control results.
#[derive(Debug, Clone, PartialEq)]
pub struct QcReport {
    /// Individual checks.
    pub checks: Vec<Check>,
    /// Notes on things QC cannot measure (e.g. faces).
    pub notes: Vec<String>,
}

impl QcReport {
    /// True if every check passed.
    pub fn passed(&self) -> bool {
        self.checks.iter().all(|c| c.pass)
    }
}

/// Runs the output checks. Values are in 8-bit code levels unless stated.
pub fn check(input: &Pixels, output: &Pixels, mode: Mode, tiling_note: &str) -> QcReport {
    let r = residual(input, output);
    let n = (input.width * input.height * input.channels) as f64;
    let rms = (r.iter().flatten().map(|&v| f64::from(v).powi(2)).sum::<f64>() / n).sqrt() * 255.0;
    let color = r
        .iter()
        .map(|plane| (plane.iter().map(|&v| f64::from(v)).sum::<f64>() / plane.len() as f64).abs() * 255.0)
        .fold(0.0, f64::max);
    // Halo overshoot: output samples beyond the range of the 2×2 source
    // neighbourhood by more than 8 levels.
    let s = output.width as f32 / input.width as f32;
    let c = input.channels;
    let mut over = 0usize;
    for y in 0..output.height {
        let sy = ((y as f32 + 0.5) / s - 0.5).max(0.0);
        let (y0, y1) = (sy.floor() as usize, (sy.floor() as usize + 1).min(input.height - 1));
        for x in 0..output.width {
            let sx = ((x as f32 + 0.5) / s - 0.5).max(0.0);
            let (x0, x1) = (sx.floor() as usize, (sx.floor() as usize + 1).min(input.width - 1));
            for ch in 0..c {
                let v = |xx: usize, yy: usize| input.data[(yy * input.width + xx) * c + ch];
                let (a, b, cc, d) = (v(x0, y0), v(x1, y0), v(x0, y1), v(x1, y1));
                let lo = a.min(b).min(cc).min(d) - 8.0 / 255.0;
                let hi = a.max(b).max(cc).max(d) + 8.0 / 255.0;
                let o = output.data[(y * output.width + x) * c + ch];
                if o < lo || o > hi {
                    over += 1;
                }
            }
        }
    }
    let overshoot = over as f64 / output.data.len() as f64;
    let (rms_limit, halo_limit) = match mode {
        Mode::Faithful => (2.0, 0.005),
        Mode::Balanced => (3.0, 0.02),
        Mode::Reconstruction { .. } => (6.0, 0.08),
    };
    let checks = vec![
        Check {
            name: "consistency_rms",
            value: rms,
            limit: rms_limit,
            pass: rms <= rms_limit,
            unit: "8-bit levels (low-pass residual)",
        },
        Check {
            name: "colour_shift",
            value: color,
            limit: 1.5,
            pass: color <= 1.5,
            unit: "8-bit levels (max channel mean offset)",
        },
        Check {
            name: "halo_overshoot",
            value: overshoot,
            limit: halo_limit,
            pass: overshoot <= halo_limit,
            unit: "fraction of samples",
        },
    ];
    let notes = vec![
        tiling_note.to_string(),
        "facial distortion: not measured (face detection INCOMPLETE)".into(),
        "repeated textures: not measured in v1".into(),
    ];
    QcReport { checks, notes }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ramp(w: usize, h: usize) -> Pixels {
        let mut data = Vec::new();
        for y in 0..h {
            for x in 0..w {
                data.extend([0.2 + 0.5 * x as f32 / w as f32, 0.3 + 0.3 * y as f32 / h as f32, 0.5]);
            }
        }
        Pixels { width: w, height: h, channels: 3, data }
    }

    #[test]
    fn consistent_upscale_passes_and_colour_shift_is_caught_and_corrected() {
        let lr = ramp(40, 30);
        let hr = Pixels {
            width: 80,
            height: 60,
            channels: 3,
            data: resize(&lr.data, 40, 30, 3, 80, 60, Filter::Bilinear),
        };
        let r = check(&lr, &hr, Mode::Faithful, "exact tiling");
        assert!(r.passed(), "{r:?}");

        // Shift red by +10 levels: colour shift fails, then correction fixes it.
        let mut shifted = hr.clone();
        for px in shifted.data.chunks_mut(3) {
            px[0] += 10.0 / 255.0;
        }
        let r = check(&lr, &shifted, Mode::Faithful, "");
        assert!(!r.passed());
        assert!(r.checks.iter().any(|c| c.name == "colour_shift" && !c.pass));
        consistency_correct(&lr, &mut shifted, 1.0);
        let r = check(&lr, &shifted, Mode::Faithful, "");
        assert!(r.checks.iter().find(|c| c.name == "colour_shift").unwrap().value < 0.5, "{r:?}");
    }

    #[test]
    fn halos_are_detected() {
        let lr = ramp(20, 20);
        let mut hr = Pixels {
            width: 40,
            height: 40,
            channels: 3,
            data: resize(&lr.data, 20, 20, 3, 40, 40, Filter::Bilinear),
        };
        for (i, v) in hr.data.iter_mut().enumerate() {
            if i % 7 == 0 {
                *v += 0.2;
            }
        }
        let r = check(&lr, &hr, Mode::Balanced, "");
        assert!(r.checks.iter().any(|c| c.name == "halo_overshoot" && !c.pass), "{r:?}");
    }
}
