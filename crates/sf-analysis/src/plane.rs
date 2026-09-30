//! Luma planes and the classical estimators.

use sf_image::{ImageBuffer, Samples, color::srgb_to_linear};

/// A single-channel image with values in 0–255.
#[derive(Debug, Clone, PartialEq)]
pub struct Plane {
    /// Width.
    pub width: usize,
    /// Height.
    pub height: usize,
    /// Row-major samples.
    pub data: Vec<f32>,
}

/// Images above this many pixels are analysed on a patch mosaic.
const MAX_FULL_PIXELS: usize = 16 << 20;
const PATCH: usize = 256;

impl Plane {
    /// Encoded luma (Rec. 601 weights) of the whole image.
    pub fn luma_full(buffer: &ImageBuffer) -> Plane {
        let (w, h, c) = (buffer.width() as usize, buffer.height() as usize, buffer.channels() as usize);
        let f = buffer.to_f32();
        let colour = c >= 3;
        let data = f
            .chunks(c)
            .map(|p| 255.0 * if colour { 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2] } else { p[0] })
            .collect();
        Plane { width: w, height: h, data }
    }

    /// Luma for analysis: the whole image when small enough, otherwise a
    /// set of native-resolution patches on a regular grid (never a
    /// downscaled copy, which would hide noise and blocking).
    pub fn luma(buffer: &ImageBuffer) -> Vec<Plane> {
        let (w, h) = (buffer.width() as usize, buffer.height() as usize);
        if w * h <= MAX_FULL_PIXELS || w < PATCH || h < PATCH {
            return vec![Plane::luma_full(buffer)];
        }
        let per_side = ((MAX_FULL_PIXELS / (PATCH * PATCH)) as f64).sqrt() as usize;
        let c = buffer.channels() as usize;
        let value = |x: usize, y: usize| -> f32 {
            let i = (y * w + x) * c;
            let s = |k: usize| match buffer.samples() {
                Samples::U8(v) => f32::from(v[i + k]) / 255.0,
                Samples::U16(v) => f32::from(v[i + k]) / 65_535.0,
                Samples::F32(v) => v[i + k],
            };
            255.0 * if c >= 3 { 0.299 * s(0) + 0.587 * s(1) + 0.114 * s(2) } else { s(0) }
        };
        let mut out = Vec::new();
        for gy in 0..per_side {
            for gx in 0..per_side {
                // Patch origins aligned to 8 so JPEG block phase is kept.
                let x0 = ((w - PATCH) * gx / (per_side - 1).max(1)) / 8 * 8;
                let y0 = ((h - PATCH) * gy / (per_side - 1).max(1)) / 8 * 8;
                let data = (0..PATCH * PATCH).map(|i| value(x0 + i % PATCH, y0 + i / PATCH)).collect();
                out.push(Plane { width: PATCH, height: PATCH, data });
            }
        }
        out
    }

    fn at(&self, x: usize, y: usize) -> f32 {
        self.data[y * self.width + x]
    }
}

struct Block {
    gradient: f32,
    sigma: f32,
    mean: f32,
    std: f32,
}

fn blocks(planes: &[Plane]) -> Vec<Block> {
    let mut out = Vec::new();
    for p in planes {
        let (w, h) = (p.width, p.height);
        if w < 10 || h < 10 {
            continue;
        }
        let step = (((w / 8) * (h / 8)) / 200_000).max(1);
        let mut n = 0usize;
        for by in (0..h - 9).step_by(8) {
            for bx in (0..w - 9).step_by(8) {
                n += 1;
                if !n.is_multiple_of(step) {
                    continue;
                }
                let (mut l, mut sum, mut sq) = (0f32, 0f32, 0f32);
                let (mut lo, mut hi) = (f32::MAX, f32::MIN);
                // Structure measure from 2×2 means: halves the noise's
                // influence on which blocks count as flat, which otherwise
                // biases the estimate low (blocks with luckily small noise
                // would be preferred).
                let mut means = [0f32; 16];
                for (k, m) in means.iter_mut().enumerate() {
                    let (sx, sy) = (bx + 1 + 2 * (k % 4), by + 1 + 2 * (k / 4));
                    *m = 0.25 * (p.at(sx, sy) + p.at(sx + 1, sy) + p.at(sx, sy + 1) + p.at(sx + 1, sy + 1));
                }
                let mut g = 0f32;
                for k in 0..16 {
                    if k % 4 < 3 {
                        g += (means[k + 1] - means[k]).abs();
                    }
                    if k < 12 {
                        g += (means[k + 4] - means[k]).abs();
                    }
                }
                for y in by + 1..by + 9 {
                    for x in bx + 1..bx + 9 {
                        let v = p.at(x, y);
                        lo = lo.min(v);
                        hi = hi.max(v);
                        sum += v;
                        sq += v * v;
                        // Separable second difference: zero on planar
                        // trends; for white noise its std is 6σ.
                        let lap = p.at(x - 1, y - 1) - 2.0 * p.at(x, y - 1) + p.at(x + 1, y - 1)
                            - 2.0 * (p.at(x - 1, y) - 2.0 * v + p.at(x + 1, y))
                            + p.at(x - 1, y + 1)
                            - 2.0 * p.at(x, y + 1)
                            + p.at(x + 1, y + 1);
                        l += lap.abs();
                    }
                }
                if lo < 3.0 || hi > 252.0 {
                    continue; // clipping hides noise
                }
                let mean = sum / 64.0;
                let std = (sq / 64.0 - mean * mean).max(0.0).sqrt();
                // E|X| = σ·√(2/π) for Gaussian X; the operator scales σ by 6.
                let sigma = (l / 64.0) * (std::f32::consts::PI / 2.0).sqrt() / 6.0;
                out.push(Block { gradient: g, sigma, mean, std });
            }
        }
    }
    out
}

fn median(v: &mut [f32]) -> Option<f32> {
    if v.is_empty() {
        return None;
    }
    v.sort_by(f32::total_cmp);
    Some(v[v.len() / 2])
}

/// Noise sigma from the flattest blocks, plus a per-intensity breakdown.
pub fn noise(planes: &[Plane]) -> (f64, Vec<(f64, f64)>) {
    let mut all = blocks(planes);
    let estimate = |bs: &mut Vec<&Block>| -> Option<f32> {
        if bs.len() < 8 {
            return None;
        }
        bs.sort_by(|a, b| a.gradient.total_cmp(&b.gradient));
        let keep = (bs.len() * 3 / 10).max(8);
        let mut s: Vec<f32> = bs[..keep].iter().map(|b| b.sigma).collect();
        median(&mut s)
    };
    let mut refs: Vec<&Block> = all.iter().collect();
    let sigma = estimate(&mut refs).unwrap_or(0.0);
    let mut levels = Vec::new();
    for band in 0..4 {
        let lo = band as f32 * 64.0;
        let mut bs: Vec<&Block> = all.iter().filter(|b| b.mean >= lo && b.mean < lo + 64.0).collect();
        if let Some(s) = estimate(&mut bs) {
            levels.push((f64::from(lo + 32.0), f64::from(s)));
        }
    }
    all.clear();
    (f64::from(sigma), levels)
}

/// Fraction of blocks whose standard deviation clearly exceeds the noise.
pub fn texture_density(planes: &[Plane], sigma: f64) -> f64 {
    let bs = blocks(planes);
    if bs.is_empty() {
        return 0.0;
    }
    let t = (3.0 * sigma + 2.0) as f32;
    bs.iter().filter(|b| b.std > t).count() as f64 / bs.len() as f64
}

/// Ratio of mean absolute differences across the strongest 8-pixel grid
/// phase to those elsewhere, averaged over both directions.
pub fn blockiness(planes: &[Plane]) -> f64 {
    let mut col = [0f64; 8];
    let mut row = [0f64; 8];
    let mut ncol = [0f64; 8];
    let mut nrow = [0f64; 8];
    for p in planes {
        for y in 0..p.height {
            for x in 0..p.width - 1 {
                col[x % 8] += f64::from((p.at(x + 1, y) - p.at(x, y)).abs());
                ncol[x % 8] += 1.0;
            }
        }
        for y in 0..p.height - 1 {
            for x in 0..p.width {
                row[y % 8] += f64::from((p.at(x, y + 1) - p.at(x, y)).abs());
                nrow[y % 8] += 1.0;
            }
        }
    }
    let ratio = |s: &[f64; 8], n: &[f64; 8], phase: usize| {
        let at = s[phase] / n[phase].max(1.0);
        let rest: f64 = (0..8).filter(|&i| i != phase).map(|i| s[i]).sum::<f64>()
            / (0..8).filter(|&i| i != phase).map(|i| n[i]).sum::<f64>().max(1.0);
        if rest < 1e-9 { 1.0 } else { at / rest }
    };
    (0..8).map(|ph| 0.5 * (ratio(&col, &ncol, ph) + ratio(&row, &nrow, ph))).fold(0.0, f64::max)
}

/// Median 10–90 % rise distance of strong, isolated horizontal and
/// vertical edges.
pub fn edge_width(planes: &[Plane]) -> Option<f64> {
    let mut widths: Vec<f32> = Vec::new();
    for p in planes {
        let lines: Vec<Vec<f32>> = (0..p.height)
            .step_by(2)
            .map(|y| p.data[y * p.width..(y + 1) * p.width].to_vec())
            .chain((0..p.width).step_by(2).map(|x| (0..p.height).map(|y| p.at(x, y)).collect()))
            .collect();
        for line in lines {
            measure_line(&line, &mut widths);
        }
    }
    if widths.len() < 20 {
        return None;
    }
    median(&mut widths).map(f64::from)
}

fn measure_line(v: &[f32], out: &mut Vec<f32>) {
    let n = v.len();
    if n < 8 {
        return;
    }
    let d: Vec<f32> = v.windows(2).map(|w| w[1] - w[0]).collect();
    let mut x = 1;
    while x + 1 < d.len() {
        let s = d[x].signum();
        let is_peak = d[x].abs() >= 12.0 && d[x].abs() >= d[x - 1].abs() && d[x].abs() >= d[x + 1].abs();
        if !is_peak {
            x += 1;
            continue;
        }
        let (mut a, mut b) = (x, x);
        while a > 0 && d[a - 1] * s > 0.5 {
            a -= 1;
        }
        while b + 1 < d.len() && d[b + 1] * s > 0.5 {
            b += 1;
        }
        let (lo, hi) = (v[a], v[b + 1]);
        let total = hi - lo;
        if total.abs() >= 30.0 && b - a < 40 {
            let cross = |frac: f32| -> f32 {
                let target = lo + frac * total;
                for i in a..=b {
                    let (p, q) = (v[i], v[i + 1]);
                    if (p - target) * s <= 0.0 && (q - target) * s >= 0.0 && q != p {
                        return i as f32 + (target - p) / (q - p);
                    }
                }
                a as f32
            };
            out.push(cross(0.9) - cross(0.1));
        }
        x = b + 1;
    }
}

/// Luma percentiles and clipping.
pub fn exposure(planes: &[Plane]) -> crate::Exposure {
    let mut hist = [0u64; 256];
    let mut total = 0u64;
    for p in planes {
        for &v in &p.data {
            hist[v.round().clamp(0.0, 255.0) as usize] += 1;
            total += 1;
        }
    }
    let pct = |q: f64| -> f64 {
        let target = (q * total as f64).ceil() as u64;
        let mut acc = 0;
        for (i, &c) in hist.iter().enumerate() {
            acc += c;
            if acc >= target.max(1) {
                return i as f64;
            }
        }
        255.0
    };
    let t = total.max(1) as f64;
    crate::Exposure {
        p1: pct(0.01),
        p50: pct(0.5),
        p99: pct(0.99),
        clipped_dark: (hist[0] + hist[1]) as f64 / t,
        clipped_bright: (hist[254] + hist[255]) as f64 / t,
    }
}

/// Standard deviation of luma, as a fraction of full scale.
pub fn rms_contrast(planes: &[Plane]) -> f64 {
    let (mut n, mut s, mut sq) = (0f64, 0f64, 0f64);
    for p in planes {
        for &v in &p.data {
            let v = f64::from(v) / 255.0;
            n += 1.0;
            s += v;
            sq += v * v;
        }
    }
    if n == 0.0 {
        return 0.0;
    }
    let m = s / n;
    (sq / n - m * m).max(0.0).sqrt()
}

/// Grey-world balance of mid-tone pixels in linear light.
pub fn color_balance(buffer: &ImageBuffer) -> Option<(f64, f64)> {
    let c = buffer.channels() as usize;
    if c < 3 {
        return None;
    }
    let f = buffer.to_f32();
    let pixels = f.len() / c;
    let step = (pixels / 4_000_000).max(1);
    let mut sum = [0f64; 3];
    let mut n = 0;
    for px in f.chunks(c).step_by(step) {
        let y = 0.299 * px[0] + 0.587 * px[1] + 0.114 * px[2];
        if !(0.08..=0.92).contains(&y) {
            continue;
        }
        for k in 0..3 {
            sum[k] += f64::from(srgb_to_linear(px[k]));
        }
        n += 1;
    }
    if n < 100 || sum[1] < 1e-9 {
        return None;
    }
    Some((sum[0] / sum[1], sum[2] / sum[1]))
}
