//! Estimator accuracy on synthetic images with known parameters.

use sf_core::{Limits, Rng};
use sf_image::{FileFormat, Image, ImageBuffer, ImageMeta, Samples, jpeg};

use crate::{analyze, metrics};

fn gaussian(rng: &mut Rng) -> f64 {
    // Box–Muller transform.
    let (u1, u2) = (rng.next_f64().max(1e-12), rng.next_f64());
    (-2.0 * u1.ln()).sqrt() * (2.0 * std::f64::consts::PI * u2).cos()
}

/// Smooth two-dimensional gradient in the 40–215 range.
fn smooth(w: usize, h: usize) -> Vec<f64> {
    (0..w * h)
        .map(|i| 40.0 + 175.0 * ((i % w) as f64 / w as f64 * 0.6 + (i / w) as f64 / h as f64 * 0.4))
        .collect()
}

fn grey_image(v: &[f64], w: usize, h: usize) -> Image {
    let s = v.iter().map(|&x| x.round().clamp(0.0, 255.0) as u8).collect();
    Image {
        buffer: ImageBuffer::new(w as u32, h as u32, 1, Samples::U8(s)).unwrap(),
        meta: ImageMeta::default(),
        format: FileFormat::Png,
    }
}

#[test]
fn noise_estimate_tracks_known_sigma() {
    let (w, h) = (320, 240);
    let mut rng = Rng::seed_from_u64(1);
    for sigma in [0.0, 2.0, 5.0, 10.0] {
        let v: Vec<f64> = smooth(w, h).iter().map(|&x| x + sigma * gaussian(&mut rng)).collect();
        let est = analyze(&grey_image(&v, w, h)).noise_sigma.value;
        if sigma == 0.0 {
            assert!(est < 0.8, "clean image: {est}");
        } else {
            assert!((est - sigma).abs() <= 0.25 * sigma + 0.3, "sigma {sigma}: estimated {est}");
        }
    }
}

#[test]
fn signal_dependent_noise_is_visible_per_level() {
    // Noise grows with intensity (like shot noise).
    let (w, h) = (400, 200);
    let mut rng = Rng::seed_from_u64(2);
    let base: Vec<f64> = (0..w * h).map(|i| 20.0 + 215.0 * (i % w) as f64 / w as f64).collect();
    let v: Vec<f64> = base.iter().map(|&x| x + (0.5 + x / 40.0) * gaussian(&mut rng)).collect();
    let levels = analyze(&grey_image(&v, w, h)).noise_by_level;
    assert!(levels.len() >= 3, "{levels:?}");
    assert!(levels.windows(2).all(|p| p[1].1 > p[0].1), "noise must increase with level: {levels:?}");
}

#[test]
fn jpeg_blocking_and_quality_are_detected() {
    let (w, h) = (256, 256);
    let mut rng = Rng::seed_from_u64(3);
    let v: Vec<f64> = smooth(w, h)
        .iter()
        .enumerate()
        .map(|(i, &x)| x + 25.0 * (((i % w) as f64 / 5.0).sin()) + 3.0 * gaussian(&mut rng))
        .collect();
    let clean = grey_image(&v, w, h);
    let clean_report = analyze(&clean);
    assert!(clean_report.blockiness.value < 1.15, "clean: {}", clean_report.blockiness.value);
    assert!(clean_report.jpeg_quality.is_none());

    let data =
        jpeg::encode(&clean.buffer, &jpeg::EncodeOptions { quality: 15, ..jpeg::EncodeOptions::default() })
            .unwrap();
    let decoded = jpeg::decode(&data, &Limits::default()).unwrap();
    let r = analyze(&decoded);
    assert!(r.blockiness.value > 1.3, "q15: {}", r.blockiness.value);
    let q = r.jpeg_quality.expect("quality from tables").value;
    assert!((q - 15.0).abs() <= 1.0, "{q}");
}

fn blurred_steps(w: usize, h: usize, sigma: f64) -> Vec<f64> {
    // Vertical step edges every 32 px, blurred horizontally with a Gaussian.
    let raw: Vec<f64> = (0..w).map(|x| if (x / 32) % 2 == 0 { 50.0 } else { 200.0 }).collect();
    let r = (4.0 * sigma).ceil() as isize;
    let k: Vec<f64> = (-r..=r).map(|i| (-(i * i) as f64 / (2.0 * sigma * sigma)).exp()).collect();
    let s: f64 = k.iter().sum();
    let row: Vec<f64> = (0..w as isize)
        .map(|x| {
            (-r..=r)
                .map(|i| k[(i + r) as usize] * raw[(x + i).clamp(0, w as isize - 1) as usize])
                .sum::<f64>()
                / s
        })
        .collect();
    (0..w * h).map(|i| row[i % w]).collect()
}

#[test]
fn edge_width_grows_with_blur() {
    let (w, h) = (512, 64);
    let mut last = 0.0;
    for sigma in [0.8, 1.6, 3.2] {
        let est =
            analyze(&grey_image(&blurred_steps(w, h, sigma), w, h)).edge_width.expect("edges found").value;
        // Continuous Gaussian blur: 10–90 % rise = 2.563σ.
        let expected = 2.563 * sigma;
        assert!((est - expected).abs() < 0.35 * expected + 0.5, "σ {sigma}: {est} vs {expected}");
        assert!(est > last);
        last = est;
    }
}

#[test]
fn exposure_colour_and_texture() {
    let (w, h) = (128, 128);
    let dark: Vec<f64> = (0..w * h).map(|i| 5.0 + 40.0 * (i % w) as f64 / w as f64).collect();
    let r = analyze(&grey_image(&dark, w, h));
    assert!(r.exposure.p99 < 50.0 && r.exposure.p1 >= 5.0, "{:?}", r.exposure);
    assert!(r.color_balance.is_none());
    assert!(r.texture_density < 0.05);

    // Warm-tinted colour image: red raised.
    let mut rgb = Vec::new();
    for i in 0..w * h {
        let g = 60 + (i % 100) as u8;
        rgb.extend([g.saturating_add(40), g, g.saturating_sub(10)]);
    }
    let img = Image {
        buffer: ImageBuffer::new(w as u32, h as u32, 3, Samples::U8(rgb)).unwrap(),
        meta: ImageMeta::default(),
        format: FileFormat::Png,
    };
    let (rg, bg) = analyze(&img).color_balance.unwrap();
    assert!(rg > 1.3 && bg < 0.95, "{rg} {bg}");

    // A checkerboard of 4-pixel squares is all texture.
    let checker: Vec<f64> =
        (0..w * h).map(|i| if ((i % w) / 4 + (i / w) / 4) % 2 == 0 { 60.0 } else { 190.0 }).collect();
    assert!(analyze(&grey_image(&checker, w, h)).texture_density > 0.9);
}

#[test]
fn unavailable_quantities_are_declared() {
    let r = analyze(&grey_image(&smooth(64, 64), 64, 64));
    assert!(r.unavailable.iter().any(|(q, _)| *q == "face_presence"));
}

#[test]
fn metrics_behave() {
    let (w, h) = (96, 64);
    let mut rng = Rng::seed_from_u64(9);
    let a = grey_image(&smooth(w, h), w, h).buffer;
    let noisy =
        grey_image(&smooth(w, h).iter().map(|&x| x + 8.0 * gaussian(&mut rng)).collect::<Vec<_>>(), w, h)
            .buffer;
    assert_eq!(metrics::psnr(&a, &a), Some(f64::INFINITY));
    assert!((metrics::ssim(&a, &a).unwrap() - 1.0).abs() < 1e-9);
    let p = metrics::psnr(&a, &noisy).unwrap();
    assert!((p - 20.0 * (255.0f64 / 8.0).log10()).abs() < 1.0, "PSNR {p}");
    let s = metrics::ssim(&a, &noisy).unwrap();
    assert!(s < 0.9 && s > 0.0, "{s}");
    let other = grey_image(&smooth(10, 10), 10, 10).buffer;
    assert_eq!(metrics::psnr(&a, &other), None);
}
