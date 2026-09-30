//! Classical-engine tests: each operation must measurably improve a
//! synthetic degradation, or be a no-op when disabled.

use sf_core::Rng;
use sf_image::resample::{Filter, resize};

use crate::*;

fn psnr(a: &[f32], b: &[f32]) -> f64 {
    let mse: f64 = a.iter().zip(b).map(|(x, y)| f64::from(x - y).powi(2)).sum::<f64>() / a.len() as f64;
    10.0 * (1.0 / mse.max(1e-12)).log10()
}

fn gaussian(rng: &mut Rng) -> f32 {
    let (u1, u2) = (rng.next_f64().max(1e-12), rng.next_f64());
    ((-2.0 * u1.ln()).sqrt() * (2.0 * std::f64::consts::PI * u2).cos()) as f32
}

/// A smooth colour scene with a few hard edges.
fn scene(w: usize, h: usize) -> Vec<f32> {
    let mut v = Vec::with_capacity(w * h * 3);
    for y in 0..h {
        for x in 0..w {
            let edge = if x > w / 2 { 0.25 } else { 0.0 };
            let (fx, fy) = (x as f32 / w as f32, y as f32 / h as f32);
            v.extend([0.2 + 0.5 * fx + edge, 0.3 + 0.4 * fy, 0.6 - 0.3 * fx + edge * 0.5]);
        }
    }
    v
}

#[test]
fn denoise_improves_psnr_and_is_a_no_op_when_disabled() {
    let (w, h) = (96, 80);
    let clean = scene(w, h);
    let mut rng = Rng::seed_from_u64(4);
    let sigma = 0.04;
    let noisy: Vec<f32> = clean.iter().map(|&v| v + sigma * gaussian(&mut rng)).collect();
    let mut out = noisy.clone();
    denoise(&mut out, w, h, 3, sigma, 1.0);
    let (before, after) = (psnr(&noisy, &clean), psnr(&out, &clean));
    assert!(after > before + 5.0, "{before:.1} dB -> {after:.1} dB");

    let mut same = noisy.clone();
    denoise(&mut same, w, h, 3, sigma, 0.0);
    assert_eq!(same, noisy);
    // A clean image is left essentially unchanged at a small sigma.
    let mut c = clean.clone();
    denoise(&mut c, w, h, 3, 0.002, 1.0);
    assert!(psnr(&c, &clean) > 45.0);
}

#[test]
fn denoise_greyscale() {
    let (w, h) = (64, 64);
    let clean: Vec<f32> = (0..w * h).map(|i| 0.3 + 0.4 * (i % w) as f32 / w as f32).collect();
    let mut rng = Rng::seed_from_u64(5);
    let noisy: Vec<f32> = clean.iter().map(|&v| v + 0.03 * gaussian(&mut rng)).collect();
    let mut out = noisy.clone();
    denoise(&mut out, w, h, 1, 0.03, 1.0);
    assert!(psnr(&out, &clean) > psnr(&noisy, &clean) + 5.0);
}

#[test]
fn deblock_reduces_block_steps_without_touching_real_edges() {
    let (w, h) = (64, 16);
    // Flat blocks with small steps at every 8th column, plus one real edge.
    let mut v: Vec<f32> = (0..w * h).map(|i| 0.4 + 0.01 * ((i % w) / 8) as f32).collect();
    for y in 0..h {
        for x in 40..w {
            v[y * w + x] += 0.3; // a strong genuine edge at x = 40
        }
    }
    let before = v.clone();
    deblock(&mut v, w, h, 1, 0.03, 0);
    let step = |d: &[f32], x: usize| (d[x] - d[x - 1]).abs();
    assert!(step(&v, 16) < step(&before, 16) * 0.6, "block step reduced");
    assert!((step(&v, 40) - step(&before, 40)).abs() < 1e-6, "real edge untouched");
    let mut same = before.clone();
    deblock(&mut same, w, h, 1, 0.0, 0);
    assert_eq!(same, before);
}

#[test]
fn upscale_beats_nearest_and_does_not_ring() {
    let (w, h) = (80, 60);
    let hr = scene(w, h);
    let lr = resize(&hr, w, h, 3, w / 2, h / 2, Filter::Area);
    let up = upscale(&lr, w / 2, h / 2, 3, 2);
    assert_eq!(up.len(), hr.len());
    let nn = resize(&lr, w / 2, h / 2, 3, w, h, Filter::Nearest);
    assert!(psnr(&up, &hr) > psnr(&nn, &hr), "{:.1} vs {:.1}", psnr(&up, &hr), psnr(&nn, &hr));

    // A hard step: output stays within the input range (no halos).
    let step: Vec<f32> = (0..32).map(|x| if x < 16 { 0.1 } else { 0.9 }).collect();
    let row = upscale(&step, 32, 1, 1, 4);
    assert!(row.iter().all(|&v| (0.1 - 1.0 / 255.0..=0.9 + 1.0 / 255.0).contains(&v)), "{row:?}");
}

#[test]
fn sharpen_narrows_edges_within_the_overshoot_limit() {
    let w = 64;
    let blurred: Vec<f32> = (0..w).map(|x| 0.2 + 0.6 / (1.0 + (-(x as f32 - 32.0) / 2.0).exp())).collect();
    let rows = 8;
    let mut img: Vec<f32> = blurred.iter().cycle().take(w * rows).copied().collect();
    let orig = img.clone();
    sharpen(&mut img, w, rows, 1, 0.8, 1.5, 0.02);
    let slope = |d: &[f32]| (d[33] - d[31]).abs();
    // The halo limiter caps the gain; a clear, bounded steepening is expected.
    assert!(slope(&img[w * 4..w * 5]) > slope(&orig[w * 4..w * 5]) * 1.1, "edge got steeper");
    let (lo, hi) = (0.2 - 0.02 - 1e-4, 0.8 + 0.02 + 1e-4);
    assert!(img.iter().all(|&v| v >= lo && v <= hi), "halo limited");
    let mut same = orig.clone();
    sharpen(&mut same, w, rows, 1, 0.0, 1.5, 0.02);
    assert_eq!(same, orig);
}

#[test]
fn tone_identity_white_balance_and_monotone_contrast() {
    let mut px = vec![0.2f32, 0.5, 0.8, 0.0, 1.0, 0.33];
    let orig = px.clone();
    tone(&mut px, 3, Tone::default());
    for (a, b) in px.iter().zip(&orig) {
        assert!((a - b).abs() < 1e-5);
    }
    // A cast of R ×1.3 and B ×0.8 in linear light is undone by the inverse gains.
    let lin = |v: f32| sf_image::color::srgb_to_linear(v);
    let enc = |v: f32| sf_image::color::linear_to_srgb(v);
    let mut cast = vec![enc(lin(0.5) * 1.3), 0.5, enc(lin(0.5) * 0.8)];
    tone(&mut cast, 3, Tone { white_balance: (1.0 / 1.3, 1.0 / 0.8), ..Tone::default() });
    assert!(cast.iter().all(|&v| (v - 0.5).abs() < 1e-3), "{cast:?}");
    // Contrast curve is monotone and fixes 0, 0.5 and 1.
    let mut ramp: Vec<f32> = (0..=20).map(|i| i as f32 / 20.0).collect();
    tone(&mut ramp, 1, Tone { contrast: 0.7, ..Tone::default() });
    assert!(ramp.windows(2).all(|p| p[1] >= p[0]));
    assert!(ramp[0].abs() < 1e-6 && (ramp[10] - 0.5).abs() < 1e-5 && (ramp[20] - 1.0).abs() < 1e-5);
}
