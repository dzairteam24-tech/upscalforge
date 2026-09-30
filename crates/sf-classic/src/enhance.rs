//! Upscaling, sharpening and tone correction.

use sf_image::color::{linear_to_srgb, srgb_to_linear};
use sf_image::resample::{Filter, resize};

use crate::par;

/// Upscales by `factor` with Lanczos-3, then clamps each output sample to
/// the range of the 2×2 source neighbourhood it lies in (plus a small
/// tolerance). The clamp removes the ringing halos that sinc-type filters
/// create at sharp edges, without softening the rest of the image.
pub fn upscale(data: &[f32], w: usize, h: usize, channels: usize, factor: usize) -> Vec<f32> {
    let (nw, nh) = (w * factor, h * factor);
    let mut out = resize(data, w, h, channels, nw, nh, Filter::Lanczos3);
    let tolerance = 1.0 / 255.0;
    par::rows(&mut out, nw * channels, |y, row| {
        let sy = ((y as f32 + 0.5) / factor as f32 - 0.5).max(0.0);
        let (y0, y1) = (sy.floor() as usize, (sy.floor() as usize + 1).min(h - 1));
        for x in 0..nw {
            let sx = ((x as f32 + 0.5) / factor as f32 - 0.5).max(0.0);
            let (x0, x1) = (sx.floor() as usize, (sx.floor() as usize + 1).min(w - 1));
            for c in 0..channels {
                let s = |xx: usize, yy: usize| data[(yy * w + xx) * channels + c];
                let (a, b, cc, d) = (s(x0, y0), s(x1, y0), s(x0, y1), s(x1, y1));
                let lo = a.min(b).min(cc).min(d) - tolerance;
                let hi = a.max(b).max(cc).max(d) + tolerance;
                let o = &mut row[x * channels + c];
                *o = o.clamp(lo, hi);
            }
        }
    });
    out
}

/// Separable Gaussian blur of a single plane (edges clamped).
pub fn gaussian(plane: &[f32], w: usize, h: usize, sigma: f32) -> Vec<f32> {
    let r = (3.0 * sigma).ceil().max(1.0) as isize;
    let k: Vec<f32> = (-r..=r).map(|i| (-(i * i) as f32 / (2.0 * sigma * sigma)).exp()).collect();
    let s: f32 = k.iter().sum();
    let k: Vec<f32> = k.iter().map(|v| v / s).collect();
    let cl = |v: isize, n: usize| v.clamp(0, n as isize - 1) as usize;
    let mut tmp = vec![0f32; w * h];
    par::rows(&mut tmp, w, |y, row| {
        for (x, t) in row.iter_mut().enumerate() {
            *t = (-r..=r).map(|i| k[(i + r) as usize] * plane[y * w + cl(x as isize + i, w)]).sum();
        }
    });
    let mut out = vec![0f32; w * h];
    par::rows(&mut out, w, |y, row| {
        for (x, o) in row.iter_mut().enumerate() {
            *o = (-r..=r).map(|i| k[(i + r) as usize] * tmp[cl(y as isize + i, h) * w + x]).sum();
        }
    });
    out
}

/// Sharpens luma by `amount` (0 = none, 1 = strong) at blur radius
/// `radius` pixels. The result may overshoot the local 3×3 range of the
/// original by at most `overshoot` (0–1 units). That limit is what
/// prevents halos. Colour channels receive the same luma change.
pub fn sharpen(
    data: &mut [f32],
    w: usize,
    h: usize,
    channels: usize,
    amount: f32,
    radius: f32,
    overshoot: f32,
) {
    if amount <= 0.0 {
        return;
    }
    let n = w * h;
    let luma: Vec<f32> = if channels == 1 {
        data.to_vec()
    } else {
        data.chunks(channels).map(|p| 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]).collect()
    };
    let blur = gaussian(&luma, w, h, radius.max(0.3));
    par::rows(&mut data[..n * channels], w * channels, |y, row| {
        for x in 0..w {
            let i = y * w + x;
            let (mut lo, mut hi) = (f32::MAX, f32::MIN);
            for yy in y.saturating_sub(1)..=(y + 1).min(h - 1) {
                for xx in x.saturating_sub(1)..=(x + 1).min(w - 1) {
                    lo = lo.min(luma[yy * w + xx]);
                    hi = hi.max(luma[yy * w + xx]);
                }
            }
            let target = (luma[i] + 2.0 * amount * (luma[i] - blur[i])).clamp(lo - overshoot, hi + overshoot);
            let delta = target - luma[i];
            for v in &mut row[x * channels..(x + 1) * channels] {
                *v += delta;
            }
        }
    });
}

/// Tone adjustments, applied in this order: white balance, then exposure
/// (both in linear light), then contrast (on encoded values).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Tone {
    /// Multipliers for red and blue relative to green (linear light).
    pub white_balance: (f32, f32),
    /// Exposure gain in linear light (1 = unchanged).
    pub exposure: f32,
    /// Contrast: 0 = unchanged, positive = S-curve around mid-grey.
    pub contrast: f32,
}

impl Default for Tone {
    fn default() -> Self {
        Tone { white_balance: (1.0, 1.0), exposure: 1.0, contrast: 0.0 }
    }
}

/// Applies [`Tone`] to sRGB-encoded samples.
pub fn tone(data: &mut [f32], channels: usize, t: Tone) {
    let s = t.contrast.clamp(0.0, 1.0);
    for px in data.chunks_mut(channels) {
        let gains: [f32; 3] =
            if channels >= 3 { [t.white_balance.0, 1.0, t.white_balance.1] } else { [1.0; 3] };
        for (c, v) in px.iter_mut().enumerate().take(channels.min(3)) {
            let lin = srgb_to_linear(v.clamp(0.0, 1.0)) * gains[c] * t.exposure;
            let mut e = linear_to_srgb(lin.clamp(0.0, 1.0));
            if s > 0.0 {
                // Smoothstep blend: steeper through the mid-tones, monotone.
                let curve = e * e * (3.0 - 2.0 * e);
                e = e + s * (curve - e);
            }
            *v = e;
        }
    }
}
