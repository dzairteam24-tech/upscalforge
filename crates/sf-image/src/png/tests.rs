//! PNG tests. Hand-built files use unfiltered (filter 0) rows, so each
//! decoding stage is checked against an independently constructed file.

use super::*;
use sf_core::{ErrorKind, Rng};

/// Builds a PNG from already-filtered scanline data.
fn build(
    width: u32,
    height: u32,
    depth: u8,
    color: u8,
    interlace: u8,
    extra: &[(&[u8; 4], Vec<u8>)],
    raw: &[u8],
) -> Vec<u8> {
    let mut out = SIGNATURE.to_vec();
    let mut ihdr = Vec::new();
    ihdr.extend(width.to_be_bytes());
    ihdr.extend(height.to_be_bytes());
    ihdr.extend([depth, color, 0, 0, interlace]);
    write_chunk(&mut out, b"IHDR", &ihdr);
    for (k, body) in extra {
        write_chunk(&mut out, k, body);
    }
    write_chunk(&mut out, b"IDAT", &zlib::zlib_compress(raw, zlib::Level::Fast));
    write_chunk(&mut out, b"IEND", &[]);
    out
}

/// Files of every kind the decoder handles, for the band-source tests.
pub(crate) fn sample_files() -> Vec<Vec<u8>> {
    let plte = vec![10, 20, 30, 40, 50, 60, 70, 80, 90];
    let palette_rows: Vec<u8> = (0..6).flat_map(|y| [0u8, (y % 3) as u8, 1, 2, 0]).collect();
    let grey2: Vec<u8> = (0..4).flat_map(|_| [0u8, 0b0001_1011, 0b0100_0000]).collect();
    let grey1: Vec<u8> = (0..3).flat_map(|_| [0u8, 0b1010_1010, 0b1000_0000]).collect();
    let keyed: Vec<u8> = (0..5).flat_map(|y| [0u8, 1, 2, 3, 9, 9, y]).collect();
    let short_key: Vec<u8> = (0..2).flat_map(|_| [0u8, 7, 8, 9]).collect();
    let adam7: Vec<u8> = {
        let mut raw = Vec::new();
        for &(x0, y0, dx, dy) in &ADAM7 {
            let xs: Vec<usize> = (x0..5).step_by(dx).collect();
            if xs.is_empty() {
                continue;
            }
            for y in (y0..5).step_by(dy) {
                raw.push(0);
                raw.extend(xs.iter().map(|&x| (y * 5 + x) as u8));
            }
        }
        raw
    };
    vec![
        build(4, 6, 8, 3, 0, &[(b"PLTE", plte.clone()), (b"tRNS", vec![0, 128])], &palette_rows),
        build(4, 6, 8, 3, 0, &[(b"PLTE", plte)], &palette_rows),
        build(5, 4, 2, 0, 0, &[], &grey2),
        build(9, 3, 1, 0, 0, &[], &grey1),
        build(2, 5, 8, 2, 0, &[(b"tRNS", vec![0, 1, 0, 2, 0, 3])], &keyed),
        // A colour key too short for RGB is ignored by both decoders.
        build(1, 2, 8, 2, 0, &[(b"tRNS", vec![0, 1])], &short_key),
        build(5, 5, 8, 0, 1, &[], &adam7),
    ]
}

fn u8s(img: &Image) -> &[u8] {
    match img.buffer.samples() {
        Samples::U8(v) => v,
        _ => panic!("expected 8-bit samples"),
    }
}

fn lim() -> Limits {
    Limits::default()
}

#[test]
fn low_bit_depth_grey_is_unpacked_and_scaled() {
    // 5 pixels at 2 bits: values 0,1,2,3,1 → 0,85,170,255,85.
    // Packed MSB first: 00 01 10 11 | 01 000000.
    let raw = [0u8, 0b0001_1011, 0b0100_0000];
    let img = decode(&build(5, 1, 2, 0, 0, &[], &raw), &lim()).unwrap();
    assert_eq!(u8s(&img), &[0, 85, 170, 255, 85]);
    // 1-bit, width 9 spans two bytes.
    let raw = [0u8, 0b1010_1010, 0b1000_0000];
    let img = decode(&build(9, 1, 1, 0, 0, &[], &raw), &lim()).unwrap();
    assert_eq!(u8s(&img), &[255, 0, 255, 0, 255, 0, 255, 0, 255]);
}

#[test]
fn palette_with_transparency() {
    let plte = vec![10, 20, 30, 40, 50, 60, 70, 80, 90];
    let trns = vec![0, 128]; // entry 2 has no alpha → opaque
    let raw = [0u8, 0, 1, 2, 1];
    let img =
        decode(&build(4, 1, 8, 3, 0, &[(b"PLTE", plte.clone()), (b"tRNS", trns)], &raw), &lim()).unwrap();
    assert_eq!(img.buffer.channels(), 4);
    assert_eq!(u8s(&img), &[10, 20, 30, 0, 40, 50, 60, 128, 70, 80, 90, 255, 40, 50, 60, 128]);
    // Out-of-range index is an error.
    let raw = [0u8, 3];
    let e = decode(&build(1, 1, 8, 3, 0, &[(b"PLTE", plte)], &raw), &lim()).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::InvalidInput);
}

#[test]
fn rgb_colour_key_becomes_alpha_and_16_bit_is_kept() {
    let key = vec![0, 1, 0, 2, 0, 3];
    let raw = [0u8, 1, 2, 3, 9, 9, 9];
    let img = decode(&build(2, 1, 8, 2, 0, &[(b"tRNS", key)], &raw), &lim()).unwrap();
    assert_eq!(u8s(&img), &[1, 2, 3, 0, 9, 9, 9, 255]);

    let raw = [0u8, 0x12, 0x34, 0xFF, 0xFE];
    let img = decode(&build(1, 1, 16, 4, 0, &[], &raw), &lim()).unwrap();
    assert_eq!(img.buffer.samples(), &Samples::U16(vec![0x1234, 0xFFFE]));
}

#[test]
fn every_filter_type_decodes() {
    // Two RGB rows; row 1 is encoded with each filter in turn, computed by
    // hand from the definitions.
    let row0: [u8; 6] = [10, 20, 30, 200, 100, 50];
    let row1: [u8; 6] = [15, 25, 35, 205, 90, 60];
    let bpp = 3;
    for kind in 0..5u8 {
        let mut enc = row1;
        for i in 0..6 {
            let a = if i >= bpp { row1[i - bpp] } else { 0 };
            let b = row0[i];
            let c = if i >= bpp { row0[i - bpp] } else { 0 };
            let pred = match kind {
                0 => 0,
                1 => a,
                2 => b,
                3 => ((u16::from(a) + u16::from(b)) / 2) as u8,
                _ => paeth(a, b, c),
            };
            enc[i] = row1[i].wrapping_sub(pred);
        }
        let mut raw = vec![0u8];
        raw.extend(row0);
        raw.push(kind);
        raw.extend(enc);
        let img = decode(&build(2, 2, 8, 2, 0, &[], &raw), &lim()).unwrap();
        assert_eq!(&u8s(&img)[6..], &row1, "filter {kind}");
    }
}

#[test]
fn adam7_interlacing() {
    // 5×5 grey image with value = y*5+x; build the seven passes by hand.
    let (w, h) = (5usize, 5usize);
    let mut raw = Vec::new();
    for &(x0, y0, dx, dy) in &ADAM7 {
        let xs: Vec<usize> = (x0..w).step_by(dx).collect();
        let ys: Vec<usize> = (y0..h).step_by(dy).collect();
        if xs.is_empty() {
            continue;
        }
        for &y in &ys {
            raw.push(0);
            raw.extend(xs.iter().map(|&x| (y * w + x) as u8));
        }
    }
    let img = decode(&build(5, 5, 8, 0, 1, &[], &raw), &lim()).unwrap();
    assert_eq!(u8s(&img), (0..25u8).collect::<Vec<_>>().as_slice());
}

#[test]
fn round_trip_all_layouts() {
    let mut rng = Rng::seed_from_u64(0x9_2e);
    for channels in 1..=4u8 {
        for sixteen in [false, true] {
            let (w, h) = (1 + rng.below(40) as u32, 1 + rng.below(30) as u32);
            let n = (w * h * u32::from(channels)) as usize;
            // Smooth data plus noise exercises all filters.
            let samples = if sixteen {
                Samples::U16((0..n).map(|i| ((i * 97) % 65_536) as u16 ^ (rng.below(8) as u16)).collect())
            } else {
                Samples::U8((0..n).map(|i| ((i / 3) as u8).wrapping_add(rng.below(4) as u8)).collect())
            };
            let buf = ImageBuffer::new(w, h, channels, samples).unwrap();
            let icc = vec![7u8; 300];
            let opts = EncodeOptions { icc_profile: Some(icc.clone()), ..EncodeOptions::default() };
            let png = encode(&buf, &opts).unwrap();
            let back = decode(&png, &lim()).unwrap();
            assert_eq!(back.buffer, buf);
            assert_eq!(back.meta.icc_profile, Some(icc));
        }
    }
}

#[test]
fn large_images_round_trip_across_filter_bands_and_deflate_segments() {
    // Tall enough for many filter bands; more than one DEFLATE segment of
    // filtered data. A wrong "previous row" at a band start, or a broken
    // segment join, would change the decoded pixels.
    let mut rng = Rng::seed_from_u64(0x7a11);
    for (w, h, sixteen) in [(700u32, 500u32, false), (300, 211, true)] {
        let n = (w * h * 3) as usize;
        let samples = if sixteen {
            Samples::U16((0..n).map(|i| ((i * 31) % 65_536) as u16 ^ (rng.below(64) as u16)).collect())
        } else {
            Samples::U8((0..n).map(|i| ((i / 5) as u8).wrapping_add(rng.below(6) as u8)).collect())
        };
        let buf = ImageBuffer::new(w, h, 3, samples).unwrap();
        let png = encode(&buf, &EncodeOptions::default()).unwrap();
        assert_eq!(decode(&png, &lim()).unwrap().buffer, buf, "{w}x{h}");
    }
}

#[test]
fn metadata_chunks() {
    let mut exif = b"MM\0\x2a\0\0\0\x08\0\x01\x01\x12\0\x03\0\0\0\x01\0\x06\0\0\0\0\0\0".to_vec();
    exif.truncate(26);
    let raw = [0u8, 5];
    let img = decode(
        &build(
            1,
            1,
            8,
            0,
            0,
            &[(b"sRGB", vec![0]), (b"gAMA", 45_455u32.to_be_bytes().to_vec()), (b"eXIf", exif)],
            &raw,
        ),
        &lim(),
    )
    .unwrap();
    assert!(img.meta.declares_srgb);
    assert!((img.meta.gamma.unwrap() - 0.454_55).abs() < 1e-9);
    assert_eq!(img.meta.orientation, Some(6));
}

#[test]
fn rejects_malformed_files() {
    let good = build(2, 2, 8, 0, 0, &[], &[0, 1, 2, 0, 3, 4]);
    let kind = |d: &[u8]| decode(d, &lim()).unwrap_err().kind();
    assert!(decode(&good, &lim()).is_ok());
    assert_eq!(kind(&good[..good.len() - 5]), ErrorKind::InvalidInput, "truncated");
    let mut bad_crc = good.clone();
    bad_crc[20] ^= 1;
    assert_eq!(kind(&bad_crc), ErrorKind::InvalidInput);
    assert_eq!(kind(b"GIF89a"), ErrorKind::InvalidInput);
    // Too little image data for the declared size.
    assert_eq!(kind(&build(3, 3, 8, 0, 0, &[], &[0, 1, 2, 3])), ErrorKind::InvalidInput);
    // Invalid colour type / depth pair.
    assert_eq!(kind(&build(1, 1, 16, 3, 0, &[], &[0, 0, 0])), ErrorKind::InvalidInput);
    // Unknown critical chunk.
    assert_eq!(kind(&build(1, 1, 8, 0, 0, &[(b"ABCD", vec![])], &[0, 0])), ErrorKind::Unsupported);
    // Invalid filter type.
    assert_eq!(kind(&build(1, 1, 8, 0, 0, &[], &[9, 0])), ErrorKind::InvalidInput);
}

#[test]
fn declared_size_is_checked_before_decoding() {
    let tiny_limits = Limits { max_decoded_bytes: 1_000, ..Limits::default() };
    // Header claims 100×100 RGBA; nothing is allocated for it.
    let png = build(100, 100, 8, 6, 0, &[], &[0]);
    assert_eq!(decode(&png, &tiny_limits).unwrap_err().kind(), ErrorKind::LimitExceeded);
}

#[test]
fn mutated_files_never_panic() {
    let mut rng = Rng::seed_from_u64(0x0bad_f11e);
    let buf = ImageBuffer::new(9, 7, 3, Samples::U8((0..189).map(|i| (i * 13) as u8).collect())).unwrap();
    let base = encode(&buf, &EncodeOptions::default()).unwrap();
    for _ in 0..5_000 {
        let mut d = base.clone();
        for _ in 0..=rng.below(3) {
            let at = rng.below(d.len() as u64) as usize;
            d[at] = rng.next_u64() as u8;
        }
        let _ = decode(&d, &lim());
    }
}
