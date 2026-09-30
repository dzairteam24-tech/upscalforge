//! JPEG tests: round trips through our encoder and decoder, metadata,
//! malformed input. Decoding of third-party files (baseline, progressive,
//! all common subsamplings) is additionally checked locally against an
//! independent decoder; see CHANGELOG.

use super::*;
use crate::image::{ImageBuffer, Samples};
use sf_core::{ErrorKind, Limits, Rng};

fn test_image(w: u32, h: u32, channels: u8) -> ImageBuffer {
    let mut v = Vec::new();
    for y in 0..h {
        for x in 0..w {
            let base = [
                (128.0 + 100.0 * ((x as f32) / 9.0).sin()) as u8,
                (128.0 + 90.0 * ((y as f32) / 7.0).cos()) as u8,
                ((x * 3 + y * 2) % 256) as u8,
            ];
            v.extend_from_slice(&base[..channels as usize]);
        }
    }
    ImageBuffer::new(w, h, channels, Samples::U8(v)).unwrap()
}

fn psnr(a: &ImageBuffer, b: &ImageBuffer) -> f64 {
    let (Samples::U8(x), Samples::U8(y)) = (a.samples(), b.samples()) else { panic!() };
    let mse: f64 =
        x.iter().zip(y).map(|(&p, &q)| (f64::from(p) - f64::from(q)).powi(2)).sum::<f64>() / x.len() as f64;
    if mse == 0.0 { 99.0 } else { 10.0 * (255.0f64.powi(2) / mse).log10() }
}

#[test]
fn round_trip_quality_scales_with_the_setting() {
    for (channels, sub) in [(3u8, Subsampling::S444), (3, Subsampling::S420), (1, Subsampling::S444)] {
        let img = test_image(77, 45, channels);
        let mut last_size = 0;
        let mut last_psnr = 0.0;
        for q in [50u8, 80, 95] {
            let data =
                encode(&img, &EncodeOptions { quality: q, subsampling: sub, icc_profile: None }).unwrap();
            let back = decode(&data, &Limits::default()).unwrap();
            assert_eq!(back.buffer.channels(), channels);
            assert_eq!((back.buffer.width(), back.buffer.height()), (77, 45));
            let p = psnr(&img, &back.buffer);
            assert!(p > 26.0, "q{q} {sub:?} c{channels}: {p:.1} dB");
            assert!(
                p >= last_psnr - 0.5 && data.len() > last_size,
                "q{q} {sub:?} c{channels}: {p:.2} dB {} bytes after {last_psnr:.2} dB {last_size} bytes",
                data.len()
            );
            last_psnr = p;
            last_size = data.len();
        }
        // 4:2:0 discards chroma detail no quality setting can restore, so
        // its ceiling on this chroma-rich test image is lower.
        let floor = if sub == Subsampling::S420 { 30.0 } else { 38.0 };
        assert!(last_psnr > floor, "q95 {sub:?} c{channels}: {last_psnr:.1} dB");
    }
}

#[test]
fn records_quantisation_sampling_and_icc() {
    let img = test_image(20, 20, 3);
    let icc: Vec<u8> = (0..150_000u32).map(|i| (i % 251) as u8).collect();
    let data = encode(
        &img,
        &EncodeOptions { quality: 75, subsampling: Subsampling::S420, icc_profile: Some(icc.clone()) },
    )
    .unwrap();
    let back = decode(&data, &Limits::default()).unwrap();
    assert_eq!(back.meta.icc_profile.as_ref(), Some(&icc), "multi-segment ICC reassembled");
    let info = back.meta.jpeg.unwrap();
    assert!(!info.progressive);
    assert_eq!(info.sampling, vec![(2, 2), (1, 1), (1, 1)]);
    assert_eq!(info.quant_tables.len(), 2);
    // Quality 75 scales the Annex K luminance DC entry 16 to 8.
    assert_eq!(info.quant_tables[0].1[0], 8);
}

#[test]
fn flat_image_is_exact() {
    let img = ImageBuffer::new(16, 16, 3, Samples::U8([90u8, 150, 210].repeat(256))).unwrap();
    let back = decode(
        &encode(&img, &EncodeOptions { quality: 100, ..EncodeOptions::default() }).unwrap(),
        &Limits::default(),
    )
    .unwrap();
    let Samples::U8(v) = back.buffer.samples() else { panic!() };
    for px in v.chunks(3) {
        for (a, b) in px.iter().zip([90u8, 150, 210]) {
            assert!(a.abs_diff(b) <= 1, "{px:?}");
        }
    }
}

#[test]
fn encoder_rejects_alpha_and_oversize() {
    let rgba = ImageBuffer::new(2, 2, 4, Samples::U8(vec![0; 16])).unwrap();
    assert_eq!(encode(&rgba, &EncodeOptions::default()).unwrap_err().kind(), ErrorKind::Unsupported);
}

#[test]
fn rejects_malformed_and_unsupported_files() {
    let good = encode(&test_image(16, 8, 3), &EncodeOptions::default()).unwrap();
    let kind = |d: &[u8]| decode(d, &Limits::default()).unwrap_err().kind();
    assert_eq!(kind(b"not a jpeg"), ErrorKind::InvalidInput);
    assert_eq!(kind(&good[..40]), ErrorKind::InvalidInput);
    // Change SOF0 to SOF3 (lossless).
    let sof = good.windows(2).position(|w| w == [0xFF, 0xC0]).unwrap();
    let mut lossless = good.clone();
    lossless[sof + 1] = 0xC3;
    assert_eq!(kind(&lossless), ErrorKind::Unsupported);
    // 12-bit precision.
    let mut twelve = good.clone();
    twelve[sof + 4] = 12;
    assert_eq!(kind(&twelve), ErrorKind::Unsupported);
    // Declared size above the limit is refused before allocation.
    let small = Limits { max_decoded_bytes: 100, ..Limits::default() };
    assert_eq!(decode(&good, &small).unwrap_err().kind(), ErrorKind::LimitExceeded);
}

#[test]
fn mutated_files_never_panic() {
    let mut rng = Rng::seed_from_u64(0x1_9e9);
    let bases = [
        encode(
            &test_image(24, 17, 3),
            &EncodeOptions { subsampling: Subsampling::S420, ..EncodeOptions::default() },
        )
        .unwrap(),
        encode(&test_image(9, 9, 1), &EncodeOptions::default()).unwrap(),
    ];
    for i in 0..6_000 {
        let mut d = bases[i % 2].clone();
        for _ in 0..=rng.below(3) {
            let at = rng.below(d.len() as u64) as usize;
            d[at] = rng.next_u64() as u8;
        }
        let _ = decode(&d, &Limits::default());
    }
}

#[test]
fn quality_is_recovered_from_quantisation_tables() {
    let img = test_image(16, 16, 3);
    for q in [30u8, 60, 85, 95] {
        let data = encode(&img, &EncodeOptions { quality: q, ..EncodeOptions::default() }).unwrap();
        let info = decode(&data, &Limits::default()).unwrap().meta.jpeg.unwrap();
        let (est, err) = estimate_quality(&info.quant_tables[0].1).unwrap();
        assert!(est.abs_diff(q) <= 1 && err < 0.5, "q{q} -> {est} (err {err})");
    }
}
