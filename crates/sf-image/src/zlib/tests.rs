//! DEFLATE/zlib tests.
//!
//! The known-answer streams were produced by Python's standard `zlib`
//! module (an independent reference implementation) from inputs that the
//! tests below rebuild. They were generated once with
//! `zlib.compress(data, level)`; only the compressed bytes are embedded.

use super::*;
use crate::huffman::huffman_lengths;
use sf_core::{ErrorKind, Rng};

fn hex(parts: &[&str]) -> Vec<u8> {
    let s: String = parts.concat();
    (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
}

fn reference_cases() -> Vec<(&'static str, Vec<u8>, Vec<u8>)> {
    let stored = b"ScaleForge stored block test ".repeat(3);
    let text = b"the quick brown fox jumps over the lazy dog; ".repeat(40);
    let mut best: Vec<u8> = (0..=255u8).collect::<Vec<_>>().repeat(3);
    best.extend(b"abcabcabcabcabcabc".repeat(50));
    let mut sparse = vec![0u8; 5000];
    sparse.extend([7, 7, 7]);
    sparse.extend(vec![0u8; 2000]);
    vec![
        (
            "stored (level 0)",
            stored,
            hex(&[
                "7801015700a8ff5363616c65466f7267652073746f72656420626c6f636b2074657374205363616c65466f7267652073",
                "746f72656420626c6f636b2074657374205363616c65466f7267652073746f72656420626c6f636b2074657374208e57",
                "2026",
            ]),
        ),
        (
            "fixed/dynamic (level 1)",
            text,
            hex(&[
                "78012bc94855282ccd4cce56482aca2fcf5348cbaf50c82acd2d2856c82f4b2d5228014ae72456552aa4e4a75b8379a3",
                "8a474363346d8ce694d17263b4601c46d50400887d8d3f",
            ]),
        ),
        (
            "dynamic (level 9)",
            best,
            hex(&[
                "78da6360646266616563e7e0e4e2e6e1e5e3171014121611151397909492969195935750545256515553d7d0d4d2d6d1",
                "d5d33730343236313533b7b0b4b2b6b1b5b37770747276717573f7f0f4f2f6f1f5f30f080c0a0e090d0b8f888c8a8e89",
                "8d8b4f484c4a4e494d4bcfc8cccacec9cdcb2f282c2a2e292d2bafa8acaaaea9adab6f686c6a6e696d6befe8eceaeee9",
                "edeb9f3071d2e42953a74d9f3173d6ec3973e7cd5fb070d1e2254b972d5fb172d5ea356bd7addfb071d3e62d5bb76ddf",
                "b173d7ee3d7bf7ed3f70f0d0e123478f1d3f71f2d4e93367cf9dbf70f1d2e52b57af5dbf71f3d6ed3b77efdd7ff0f0d1",
                "e3274f9f3d7ff1f2d5eb376fdfbdfff0f1d3e72f5fbf7dfff1f3d7ef3f7ffffd6718f5ff88f63fd079a368148da20144",
                "001942d727",
            ]),
        ),
        (
            "long runs (level 6)",
            sparse,
            hex(&["789cedce310d00000803b07df3ef181184f0b40a9a0000000000d7da7e170080bd01bf950016"]),
        ),
    ]
}

#[test]
fn decodes_reference_streams() {
    for (name, data, compressed) in reference_cases() {
        let got = zlib_decompress(&compressed, 1 << 20).unwrap_or_else(|e| panic!("{name}: {e}"));
        assert_eq!(got, data, "{name}");
    }
}

fn corpus() -> Vec<Vec<u8>> {
    let mut rng = Rng::seed_from_u64(0x2_1b);
    let random: Vec<u8> = (0..70_000).map(|_| rng.next_u64() as u8).collect();
    let skewed: Vec<u8> = (0..50_000).map(|_| (rng.below(6) * rng.below(6)) as u8).collect();
    let text = b"ScaleForge exact tiling keeps every core pixel identical. ".repeat(3_000);
    let gradient: Vec<u8> = (0..200_000u32).map(|i| ((i % 640) / 3) as u8).collect();
    vec![Vec::new(), vec![42], vec![0; 100_000], random, skewed, text, gradient]
}

#[test]
fn round_trip_all_levels() {
    for data in corpus() {
        for level in [Level::Fast, Level::Default, Level::Best] {
            let z = zlib_compress(&data, level);
            assert_eq!(
                zlib_decompress(&z, data.len().max(1)).unwrap(),
                data,
                "{level:?}, {} bytes",
                data.len()
            );
        }
    }
}

#[test]
fn compresses_redundant_data_and_bounds_incompressible_growth() {
    let c = corpus();
    let text = &c[5];
    assert!(zlib_compress(text, Level::Default).len() < text.len() / 50);
    let random = &c[3];
    let z = zlib_compress(random, Level::Default);
    assert!(z.len() <= random.len() + random.len() / 1000 + 64, "stored fallback keeps growth small");
}

/// Inputs longer than one segment: mixed content so that stored blocks
/// (random runs) land at arbitrary bit offsets inside segments, plus
/// lengths exactly at segment boundaries.
fn multi_segment_corpus() -> Vec<Vec<u8>> {
    let mut rng = Rng::seed_from_u64(0x5e6);
    let mut mixed = b"segment boundary test ".repeat(5_000);
    mixed.extend((0..300_000).map(|_| rng.next_u64() as u8));
    mixed.extend(vec![7u8; 150_000]);
    mixed.extend((0..400_000u32).map(|i| ((i % 900) / 4) as u8));
    mixed.extend((0..90_000).map(|_| rng.next_u64() as u8));
    let at = |n: usize| (0..n as u32).map(|i| (i % 251) as u8 ^ (i / 7_000) as u8).collect::<Vec<u8>>();
    vec![mixed, at(SEGMENT), at(SEGMENT + 1), at(2 * SEGMENT - 1), at(3 * SEGMENT)]
}

#[test]
fn multi_segment_streams_round_trip() {
    for data in multi_segment_corpus() {
        for level in [Level::Fast, Level::Default] {
            let z = zlib_compress(&data, level);
            assert_eq!(zlib_decompress(&z, data.len()).unwrap(), data, "{level:?}, {} bytes", data.len());
        }
    }
}

#[test]
fn output_does_not_depend_on_the_thread_count() {
    for data in multi_segment_corpus() {
        let one = deflate_with(&data, Level::Default, 1);
        assert_eq!(deflate_with(&data, Level::Default, 3), one);
        assert_eq!(deflate_with(&data, Level::Default, 64), one);
    }
}

#[test]
fn matches_reach_back_across_segment_boundaries() {
    // A 20 000-byte random pattern repeated over 1 MB. Only matches that
    // reach into the previous segment avoid re-sending the pattern as
    // literals at the start of every segment (4 segments ≈ 80 KB).
    let mut rng = Rng::seed_from_u64(0xb0);
    let pattern: Vec<u8> = (0..20_000).map(|_| rng.next_u64() as u8).collect();
    let data: Vec<u8> = pattern.iter().copied().cycle().take(1 << 20).collect();
    let z = zlib_compress(&data, Level::Default);
    assert!(z.len() < 30_000, "{} bytes", z.len());
    assert_eq!(zlib_decompress(&z, data.len()).unwrap(), data);
}

#[test]
fn rejects_corruption() {
    let data = b"corruption detection test ".repeat(20);
    let good = zlib_compress(&data, Level::Default);
    let kind = |bytes: &[u8]| zlib_decompress(bytes, 1 << 20).unwrap_err().kind();
    assert_eq!(kind(&good[..good.len() - 1]), ErrorKind::InvalidInput, "truncated trailer");
    assert_eq!(kind(&good[..good.len() / 2]), ErrorKind::InvalidInput, "truncated body");
    let mut bad = good.clone();
    let n = bad.len();
    bad[n - 1] ^= 1;
    assert_eq!(kind(&bad), ErrorKind::InvalidInput, "adler mismatch");
    let mut bad = good.clone();
    bad[1] ^= 1;
    assert_eq!(kind(&bad), ErrorKind::InvalidInput, "header check");
    // Stored block whose NLEN is not the complement of LEN.
    assert_eq!(kind(&[0x78, 0x01, 0x01, 0x05, 0x00, 0x00, 0x00, 0, 0, 0, 0]), ErrorKind::InvalidInput);
    // Reserved block type 3.
    assert_eq!(kind(&[0x78, 0x01, 0x07, 0, 0, 0, 0, 0]), ErrorKind::InvalidInput);
    // Preset dictionary flag.
    assert_eq!(
        zlib_decompress(&[0x78, 0xBB, 0, 0, 0, 0, 0, 0], 16).unwrap_err().kind(),
        ErrorKind::Unsupported
    );
}

#[test]
fn output_limit_stops_decompression_bombs() {
    let zeros = vec![0u8; 1 << 20];
    let z = zlib_compress(&zeros, Level::Best);
    assert!(z.len() < 5_000);
    let e = zlib_decompress(&z, 64 * 1024).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::LimitExceeded);
}

#[test]
fn huffman_lengths_are_complete_and_limited() {
    let mut rng = Rng::seed_from_u64(77);
    for _ in 0..300 {
        let max: u8 = if rng.below(2) == 0 { 7 } else { 15 };
        // Code-length alphabets (limit 7) have 19 symbols; others up to 286.
        let n = 2 + rng.below(if max == 7 { 18 } else { 285 }) as usize;
        // Fibonacci-like frequencies force deep trees that must be limited.
        let freqs: Vec<u32> = (0..n)
            .map(|i| {
                if rng.below(4) == 0 {
                    0
                } else if i < 30 {
                    1u32 << (i % 25)
                } else {
                    rng.below(1000) as u32
                }
            })
            .collect();
        let l = huffman_lengths(&freqs, max);
        let kraft: u64 = l.iter().filter(|&&x| x > 0).map(|&x| 1u64 << (max - x)).sum();
        assert_eq!(kraft, 1u64 << max, "{freqs:?} -> {l:?}");
        assert!(l.iter().all(|&x| x <= max));
        assert!(freqs.iter().zip(&l).all(|(&f, &x)| f == 0 || x > 0));
    }
}

#[test]
fn mutated_streams_never_panic() {
    let mut rng = Rng::seed_from_u64(0xf00d);
    let seeds: Vec<Vec<u8>> =
        corpus().iter().take(6).map(|d| zlib_compress(&d[..d.len().min(3000)], Level::Default)).collect();
    for i in 0..20_000 {
        let mut s = seeds[i % seeds.len()].clone();
        if s.is_empty() {
            continue;
        }
        for _ in 0..=rng.below(3) {
            let at = rng.below(s.len() as u64) as usize;
            s[at] ^= 1 << rng.below(8);
        }
        let _ = zlib_decompress(&s, 1 << 20);
    }
}
