//! WebP decoder tests.
//!
//! The `.webp` files in `testdata/` were produced once by libwebp (through
//! Pillow), an independent reference implementation, from synthetic
//! images. Each has a `.png` next to it holding libwebp's own decode of
//! that file: for lossless files this equals the source image exactly.

use super::*;
use sf_core::{ErrorKind, Rng};

macro_rules! fixture {
    ($name:literal) => {
        (
            &include_bytes!(concat!("testdata/", $name, ".webp"))[..],
            &include_bytes!(concat!("testdata/", $name, ".png"))[..],
        )
    };
}

fn lim() -> Limits {
    Limits::default()
}

fn expected(png: &[u8]) -> ImageBuffer {
    crate::png::decode(png, &lim()).unwrap().buffer
}

fn u8s(b: &ImageBuffer) -> &[u8] {
    match b.samples() {
        Samples::U8(v) => v,
        _ => panic!("expected 8-bit samples"),
    }
}

#[test]
fn lossless_files_decode_exactly() {
    for (name, (webp, png)) in [
        ("rgb", fixture!("lossless_rgb")),
        ("fast", fixture!("lossless_fast")),
        ("alpha", fixture!("lossless_alpha")),
        ("palette2", fixture!("lossless_palette2")),
        ("palette3", fixture!("lossless_palette3")),
        ("palette12", fixture!("lossless_palette12")),
        ("palette200", fixture!("lossless_palette200")),
    ] {
        let img = decode(webp, &lim()).unwrap_or_else(|e| panic!("{name}: {e}"));
        assert_eq!(img.format, FileFormat::WebP);
        assert_eq!(img.buffer, expected(png), "{name}");
    }
}

/// Compares colour channels with a tolerance (Y'CbCr → RGB conversion is
/// not specified bit-exactly) and alpha exactly.
fn assert_close(name: &str, got: &ImageBuffer, want: &ImageBuffer) {
    assert_eq!(
        (got.width(), got.height(), got.channels()),
        (want.width(), want.height(), want.channels()),
        "{name}"
    );
    let c = got.channels() as usize;
    let (g, w) = (u8s(got), u8s(want));
    let (mut max, mut sum, mut n) = (0i32, 0i64, 0i64);
    for (i, (&a, &b)) in g.iter().zip(w).enumerate() {
        let d = (i32::from(a) - i32::from(b)).abs();
        if c == 4 && i % 4 == 3 {
            assert_eq!(a, b, "{name}: alpha differs at sample {i}");
        } else {
            max = max.max(d);
            sum += i64::from(d);
            n += 1;
        }
    }
    let mean = sum as f64 / n as f64;
    assert!(max <= 3 && mean < 0.75, "{name}: max {max}, mean {mean:.3}");
}

#[test]
fn lossy_files_match_the_reference_decoder() {
    for (name, (webp, png)) in [
        ("q80", fixture!("lossy_q80")),
        ("q10", fixture!("lossy_q10")),
        ("q98", fixture!("lossy_q98")),
        ("alpha", fixture!("lossy_alpha")),
    ] {
        let img = decode(webp, &lim()).unwrap_or_else(|e| panic!("{name}: {e}"));
        assert_close(name, &img.buffer, &expected(png));
    }
}

#[test]
fn detection_and_dispatch() {
    let (webp, _) = fixture!("lossy_q80");
    assert_eq!(crate::detect(webp), Some(FileFormat::WebP));
    assert_eq!(crate::decode_any(webp, &lim()).unwrap().format, FileFormat::WebP);
    assert!(!is_webp(b"RIFF\0\0\0\0WAVE"));
}

#[test]
fn truncated_files_fail_cleanly() {
    for (webp, _) in [fixture!("lossless_rgb"), fixture!("lossy_q80"), fixture!("lossy_alpha")] {
        for len in (0..webp.len()).step_by(7) {
            assert!(decode(&webp[..len], &lim()).is_err(), "prefix of {len} bytes decoded");
        }
    }
}

#[test]
fn mutated_files_never_panic() {
    let mut rng = Rng::seed_from_u64(0x3eb9);
    for (webp, _) in [
        fixture!("lossless_rgb"),
        fixture!("lossless_palette12"),
        fixture!("lossy_q80"),
        fixture!("lossy_alpha"),
    ] {
        for _ in 0..300 {
            let mut m = webp.to_vec();
            for _ in 0..1 + rng.below(4) {
                let i = rng.below(m.len() as u64) as usize;
                m[i] ^= 1 << rng.below(8);
            }
            let _ = decode(&m, &lim()); // must return, never panic
        }
    }
}

/// Wraps chunks in a RIFF/WEBP container.
fn container(chunks: &[(&[u8; 4], Vec<u8>)]) -> Vec<u8> {
    let mut body = b"WEBP".to_vec();
    for (fourcc, payload) in chunks {
        body.extend_from_slice(*fourcc);
        body.extend((payload.len() as u32).to_le_bytes());
        body.extend(payload);
        if payload.len() % 2 == 1 {
            body.push(0);
        }
    }
    let mut out = b"RIFF".to_vec();
    out.extend((body.len() as u32).to_le_bytes());
    out.extend(body);
    out
}

/// The single `VP8 `/`VP8L` chunk of a simple-format fixture.
fn bitstream(webp: &[u8]) -> ([u8; 4], Vec<u8>) {
    let c = chunks(webp).unwrap();
    (c[0].0, c[0].1.to_vec())
}

fn vp8x(flags: u8, w: u32, h: u32) -> Vec<u8> {
    let mut p = vec![flags, 0, 0, 0];
    p.extend(&(w - 1).to_le_bytes()[..3]);
    p.extend(&(h - 1).to_le_bytes()[..3]);
    p
}

#[test]
fn extended_format_with_icc_and_exif() {
    let (webp, png) = fixture!("lossless_rgb");
    let (kind, data) = bitstream(webp);
    let icc = vec![9u8; 57];
    let exif = crate::exif::tests_support::orientation_block(6);
    let file = container(&[
        (b"VP8X", vp8x(0x20 | 0x08, 61, 43)),
        (b"ICCP", icc.clone()),
        (&kind, data),
        (b"EXIF", exif),
        (b"XYZW", vec![1, 2, 3]),
    ]);
    let img = decode(&file, &lim()).unwrap();
    assert_eq!(img.buffer, expected(png));
    assert_eq!(img.meta.icc_profile, Some(icc));
    assert!(!img.meta.declares_srgb);
    assert_eq!(img.meta.orientation, Some(6));
}

#[test]
fn rejects_animation_size_mismatch_and_oversized_images() {
    let (webp, _) = fixture!("lossy_q80");
    let (kind, data) = bitstream(webp);
    let animated = container(&[(b"VP8X", vp8x(0x02, 83, 59)), (b"ANIM", vec![0; 6])]);
    assert_eq!(decode(&animated, &lim()).unwrap_err().kind(), ErrorKind::Unsupported);
    let mismatch = container(&[(b"VP8X", vp8x(0, 84, 59)), (&kind, data)]);
    assert_eq!(decode(&mismatch, &lim()).unwrap_err().kind(), ErrorKind::InvalidInput);
    let small = Limits { max_image_dimension: 64, ..Limits::default() };
    assert_eq!(decode(webp, &small).unwrap_err().kind(), ErrorKind::LimitExceeded);
}

#[test]
fn raw_alpha_with_every_filter() {
    // An ALPH chunk with uncompressed, filtered data next to a lossy frame.
    let (webp, png) = fixture!("lossy_q80");
    let (kind, data) = bitstream(webp);
    let (w, h) = (83usize, 59usize);
    let alpha: Vec<u8> = (0..w * h).map(|i| ((i % w) * 3 + (i / w) * 2) as u8).collect();
    for filter in 0..4u8 {
        // Apply the forward filter so decoding must invert it.
        let mut coded = alpha.clone();
        for y in 0..h {
            for x in 0..w {
                let i = y * w + x;
                let pred = match (x, y) {
                    (0, 0) => 0,
                    (_, 0) => alpha[i - 1],
                    (0, _) => alpha[i - w],
                    _ => match filter {
                        0 => 0,
                        1 => alpha[i - 1],
                        2 => alpha[i - w],
                        _ => {
                            (i32::from(alpha[i - 1]) + i32::from(alpha[i - w]) - i32::from(alpha[i - w - 1]))
                                .clamp(0, 255) as u8
                        }
                    },
                };
                coded[i] = if filter == 0 { alpha[i] } else { alpha[i].wrapping_sub(pred) };
            }
        }
        let mut chunk = vec![filter << 2];
        chunk.extend(coded);
        let file = container(&[(b"VP8X", vp8x(0x10, 83, 59)), (b"ALPH", chunk), (&kind, data.clone())]);
        let img = decode(&file, &lim()).unwrap();
        let rgb = expected(png);
        let got = u8s(&img.buffer);
        assert_eq!(img.buffer.channels(), 4);
        let a: Vec<u8> = got.chunks(4).map(|p| p[3]).collect();
        assert_eq!(a, alpha, "filter {filter}");
        let colour: Vec<u8> = got.chunks(4).flat_map(|p| p[..3].to_vec()).collect();
        let colour = ImageBuffer::new(83, 59, 3, Samples::U8(colour)).unwrap();
        assert_close("raw alpha", &colour, &rgb);
    }
}
