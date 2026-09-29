//! TIFF tests: round trips, hand-built files for each reader feature, and
//! malformed input.

use super::*;
use sf_core::{ErrorKind, Rng};

fn lim() -> Limits {
    Limits::default()
}

/// Builds a classic TIFF from raw strip data and (tag, type, values).
fn build(le: bool, strips: &[Vec<u8>], mut tags: Vec<(u16, u16, Vec<u32>)>) -> Vec<u8> {
    let p16 = |v: u16| if le { v.to_le_bytes() } else { v.to_be_bytes() };
    let p32 = |v: u32| if le { v.to_le_bytes() } else { v.to_be_bytes() };
    let mut out = if le { b"II".to_vec() } else { b"MM".to_vec() };
    out.extend(p16(42));
    out.extend(p32(0));
    let mut offs = Vec::new();
    for s in strips {
        offs.push(out.len() as u32);
        out.extend(s);
    }
    tags.push((273, 4, offs));
    tags.push((279, 4, strips.iter().map(|s| s.len() as u32).collect()));
    tags.sort_by_key(|t| t.0);
    let mut ext: Vec<Option<u32>> = Vec::new();
    for (_, t, v) in &tags {
        let size = if *t == 3 { 2 } else { 4 };
        if v.len() * size > 4 {
            ext.push(Some(out.len() as u32));
            for &x in v {
                if *t == 3 { out.extend(p16(x as u16)) } else { out.extend(p32(x)) }
            }
        } else {
            ext.push(None);
        }
    }
    let ifd = out.len() as u32;
    out.extend(p16(tags.len() as u16));
    for ((tag, t, v), e) in tags.iter().zip(ext) {
        out.extend(p16(*tag));
        out.extend(p16(*t));
        out.extend(p32(v.len() as u32));
        let start = out.len();
        match e {
            Some(off) => out.extend(p32(off)),
            None => {
                for &x in v {
                    if *t == 3 { out.extend(p16(x as u16)) } else { out.extend(p32(x)) }
                }
            }
        }
        out.resize(start + 4, 0);
    }
    out.extend(p32(0));
    let at = if le { ifd.to_le_bytes() } else { ifd.to_be_bytes() };
    out[4..8].copy_from_slice(&at);
    out
}

fn base_tags(
    w: u32,
    h: u32,
    spp: u32,
    bits: u32,
    photometric: u32,
    compression: u32,
    rows: u32,
) -> Vec<(u16, u16, Vec<u32>)> {
    vec![
        (256, 4, vec![w]),
        (257, 4, vec![h]),
        (258, 3, vec![bits; spp as usize]),
        (259, 3, vec![compression]),
        (262, 3, vec![photometric]),
        (277, 3, vec![spp]),
        (278, 4, vec![rows]),
    ]
}

#[test]
fn round_trip_all_formats_and_compressions() {
    let mut rng = Rng::seed_from_u64(0x7_1ff);
    for channels in 1..=4u8 {
        for format in [SampleFormat::U8, SampleFormat::U16, SampleFormat::F32] {
            for compression in [Compression::None, Compression::Deflate] {
                let (w, h) = (1 + rng.below(50) as u32, 1 + rng.below(40) as u32);
                let n = (w * h * u32::from(channels)) as usize;
                let samples = match format {
                    SampleFormat::U8 => Samples::U8((0..n).map(|i| (i % 251) as u8).collect()),
                    SampleFormat::U16 => Samples::U16((0..n).map(|i| (i * 131 % 65_536) as u16).collect()),
                    SampleFormat::F32 => Samples::F32((0..n).map(|i| i as f32 * 0.37 - 5.0).collect()),
                };
                let buf = ImageBuffer::new(w, h, channels, samples).unwrap();
                let icc = vec![3u8; 97];
                let data =
                    encode(&buf, &EncodeOptions { compression, icc_profile: Some(icc.clone()) }).unwrap();
                let back = decode(&data, &lim()).unwrap();
                assert_eq!(back.buffer, buf, "{channels} ch {format:?} {compression:?}");
                assert_eq!(back.meta.icc_profile, Some(icc));
            }
        }
    }
}

#[test]
fn big_endian_whiteiszero_and_packbits() {
    // 4×1 grey, WhiteIsZero, PackBits: literal run of 2, then a repeat of 2.
    let packed = vec![1, 10, 20, (-1i8) as u8, 200];
    let f = build(false, &[packed], base_tags(4, 1, 1, 8, 0, 32773, 1));
    let img = decode(&f, &lim()).unwrap();
    assert_eq!(img.buffer.samples(), &Samples::U8(vec![245, 235, 55, 55]));
}

#[test]
fn lzw_with_predictor_and_multiple_strips() {
    let (w, h) = (300u32, 7u32);
    let pixels: Vec<u8> = (0..w * h * 3).map(|i| ((i / 3) % 97 + (i % 3) * 50) as u8).collect();
    let rows = 3u32;
    let mut strips = Vec::new();
    for y0 in (0..h).step_by(rows as usize) {
        let mut strip = Vec::new();
        for y in y0..(y0 + rows).min(h) {
            let mut row = pixels[(y * w * 3) as usize..((y + 1) * w * 3) as usize].to_vec();
            for i in (3..row.len()).rev() {
                row[i] = row[i].wrapping_sub(row[i - 3]);
            }
            strip.extend(row);
        }
        strips.push(lzw::test_encoder::encode(&strip));
    }
    let mut tags = base_tags(w, h, 3, 8, 2, 5, rows);
    tags.push((317, 3, vec![2]));
    let img = decode(&build(true, &strips, tags), &lim()).unwrap();
    assert_eq!(img.buffer.samples(), &Samples::U8(pixels));
}

#[test]
fn lzw_long_input_crosses_every_code_width() {
    // Enough varied data to grow codes to 12 bits and trigger a clear.
    let mut rng = Rng::seed_from_u64(3);
    let data: Vec<u8> = (0..60_000).map(|_| (rng.below(20) * 7) as u8).collect();
    assert_eq!(lzw::decode(&lzw::test_encoder::encode(&data), data.len()).unwrap(), data);
}

#[test]
fn tiles_planar_layout_and_premultiplied_alpha() {
    // 3×3 grey+alpha, planar, 2×2 tiles (4 tiles per plane, 2 planes).
    let grey = [10u8, 20, 30, 40, 50, 60, 70, 80, 90];
    let alpha = [255u8, 128, 0, 255, 255, 255, 255, 255, 64];
    let tile = |plane: &[u8], tx: usize, ty: usize| -> Vec<u8> {
        let mut t = vec![0u8; 4];
        for y in 0..2 {
            for x in 0..2 {
                let (ix, iy) = (tx * 2 + x, ty * 2 + y);
                if ix < 3 && iy < 3 {
                    t[y * 2 + x] = plane[iy * 3 + ix];
                }
            }
        }
        t
    };
    // Premultiply the grey by alpha as the file stores it.
    let pre: Vec<u8> =
        grey.iter().zip(&alpha).map(|(&g, &a)| ((u32::from(g) * u32::from(a) + 127) / 255) as u8).collect();
    let mut chunks = Vec::new();
    for plane in [&pre[..], &alpha[..]] {
        for ty in 0..2 {
            for tx in 0..2 {
                chunks.push(tile(plane, tx, ty));
            }
        }
    }
    // Reuse the strip helper, then rename strip tags to tile tags.
    let mut tags = base_tags(3, 3, 2, 8, 1, 1, 3);
    tags.retain(|t| t.0 != 278);
    tags.extend([(284, 3, vec![2]), (322, 4, vec![2]), (323, 4, vec![2]), (338, 3, vec![1])]);
    let mut f = build(true, &chunks, tags);
    // Tag ids 273/279 → 324/325 (tile offsets/byte counts); keep sorted order
    // valid for the reader, which looks tags up by id.
    let ifd = u32::from_le_bytes(f[4..8].try_into().unwrap()) as usize;
    let n = u16::from_le_bytes([f[ifd], f[ifd + 1]]) as usize;
    for i in 0..n {
        let e = ifd + 2 + i * 12;
        let tag = u16::from_le_bytes([f[e], f[e + 1]]);
        let new = match tag {
            273 => 324u16,
            279 => 325,
            t => t,
        };
        f[e..e + 2].copy_from_slice(&new.to_le_bytes());
    }
    let img = decode(&f, &lim()).unwrap();
    let Samples::U8(v) = img.buffer.samples() else { panic!() };
    for i in 0..9 {
        assert_eq!(v[2 * i + 1], alpha[i]);
        if alpha[i] > 0 {
            assert!(v[2 * i].abs_diff(grey[i]) <= 2, "pixel {i}: {} vs {}", v[2 * i], grey[i]);
        } else {
            assert_eq!(v[2 * i], 0);
        }
    }
}

#[test]
fn bigtiff_is_read() {
    // Build a BigTIFF by hand: 2×1 grey, uncompressed, inline values.
    let mut f = b"II".to_vec();
    f.extend(43u16.to_le_bytes());
    f.extend(8u16.to_le_bytes());
    f.extend(0u16.to_le_bytes());
    f.extend(32u64.to_le_bytes()); // IFD at 32
    f.extend([0u8; 8]); // padding to 24
    f.extend([7u8, 9]); // pixel data at 24
    f.resize(32, 0);
    let entries: [(u16, u16, u64); 7] =
        [(256, 3, 2), (257, 3, 1), (258, 3, 8), (262, 3, 1), (273, 16, 24), (277, 3, 1), (279, 16, 2)];
    f.extend((entries.len() as u64).to_le_bytes());
    for (tag, t, v) in entries {
        f.extend(tag.to_le_bytes());
        f.extend(t.to_le_bytes());
        f.extend(1u64.to_le_bytes());
        f.extend(v.to_le_bytes());
    }
    f.extend(0u64.to_le_bytes());
    let img = decode(&f, &lim()).unwrap();
    assert_eq!(img.buffer.samples(), &Samples::U8(vec![7, 9]));
}

#[test]
fn unsupported_and_malformed() {
    let kind = |d: &[u8]| decode(d, &lim()).unwrap_err().kind();
    // Palette photometric.
    assert_eq!(kind(&build(true, &[vec![0]], base_tags(1, 1, 1, 8, 3, 1, 1))), ErrorKind::Unsupported);
    // JPEG compression.
    assert_eq!(kind(&build(true, &[vec![0]], base_tags(1, 1, 1, 8, 1, 7, 1))), ErrorKind::Unsupported);
    // Strip too short for the declared size.
    assert_eq!(kind(&build(true, &[vec![0, 1]], base_tags(2, 2, 1, 8, 1, 1, 2))), ErrorKind::InvalidInput);
    // Offset outside the file.
    let mut f = build(true, &[vec![5]], base_tags(1, 1, 1, 8, 1, 1, 1));
    let n = f.len();
    f.truncate(n - 30);
    assert!(decode(&f, &lim()).is_err());
    // Declared size over the limit is refused before reading pixels.
    let tiny = Limits { max_decoded_bytes: 10, ..Limits::default() };
    assert_eq!(
        decode(&build(true, &[vec![0]], base_tags(100, 100, 1, 8, 1, 1, 100)), &tiny).unwrap_err().kind(),
        ErrorKind::LimitExceeded
    );
}

#[test]
fn mutated_files_never_panic() {
    let mut rng = Rng::seed_from_u64(0x7_1fe);
    let buf = ImageBuffer::new(13, 11, 3, Samples::U16((0..429).map(|i| i as u16 * 97).collect())).unwrap();
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

#[test]
fn bigtiff_writer_path_round_trips() {
    // BigTIFF is chosen automatically only above 4 GiB; force it here.
    let buf = ImageBuffer::new(5, 3, 3, Samples::U16((0..45).map(|i| i * 1000).collect())).unwrap();
    let opts = EncodeOptions { compression: Compression::Deflate, icc_profile: Some(vec![1, 2, 3]) };
    let strips = vec![zlib::zlib_compress(
        &{
            let mut raw = Vec::new();
            for y in 0..3 {
                let mut row: Vec<u8> =
                    (0..15).flat_map(|i| (((y * 15 + i) * 1000) as u16).to_le_bytes()).collect();
                predict_row(&mut row, 3, 2);
                raw.extend(row);
            }
            raw
        },
        zlib::Level::Default,
    )];
    let f = write_file(&buf, &opts, &strips, 3, true, true).unwrap();
    assert_eq!(&f[2..4], &[43, 0]);
    let back = decode(&f, &lim()).unwrap();
    assert_eq!(back.buffer, buf);
    assert_eq!(back.meta.icc_profile, Some(vec![1, 2, 3]));
}
