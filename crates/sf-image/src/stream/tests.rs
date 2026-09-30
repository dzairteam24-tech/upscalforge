//! Band I/O tests: every source must deliver exactly the rows of a whole
//! decode, and every sink exactly the bytes of a whole encode.

use std::io::Cursor;

use super::*;
use crate::image::Samples;
use crate::png::{self, PngSink, PngSource};
use crate::tiff::{self, TiffSink};
use sf_core::Rng;

fn tmp(tag: &str) -> std::path::PathBuf {
    let p = std::env::temp_dir().join(format!("sf-stream-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&p);
    std::fs::create_dir_all(&p).unwrap();
    p
}

fn image(w: u32, h: u32, c: u8, sixteen: bool, seed: u64) -> ImageBuffer {
    let mut rng = Rng::seed_from_u64(seed);
    let n = (w * h * u32::from(c)) as usize;
    let samples = if sixteen {
        Samples::U16((0..n).map(|i| ((i * 37) % 65_536) as u16 ^ rng.below(512) as u16).collect())
    } else {
        Samples::U8((0..n).map(|i| ((i / 3) as u8).wrapping_add(rng.below(9) as u8)).collect())
    };
    ImageBuffer::new(w, h, c, samples).unwrap()
}

/// Reads a source to the end in bands of varying height.
fn drain(src: &mut dyn RowSource, rng: &mut Rng) -> ImageBuffer {
    let info = src.info().clone();
    let mut bands = Vec::new();
    let mut done = 0;
    while done < info.height {
        let b = src.read_rows(1 + rng.below(40) as u32).unwrap();
        done += b.height();
        bands.push(b);
    }
    assert!(src.read_rows(1).is_err(), "no rows are left at the end");
    let mut all = bands[0].clone();
    for b in &bands[1..] {
        all = crate::tiff::tests_support::append(&all, b);
    }
    all
}

#[test]
fn png_source_matches_whole_decode_for_every_layout() {
    let d = tmp("png-src");
    let mut rng = Rng::seed_from_u64(5);
    for (i, (w, h, c, sixteen)) in
        [(1, 1, 1, false), (37, 90, 3, false), (64, 33, 4, true), (19, 70, 2, false), (200, 150, 3, true)]
            .into_iter()
            .enumerate()
    {
        let img = image(w, h, c, sixteen, i as u64);
        let path = d.join(format!("{i}.png"));
        let icc = vec![3u8; 100];
        std::fs::write(
            &path,
            png::encode(&img, &png::EncodeOptions { icc_profile: Some(icc.clone()), ..Default::default() })
                .unwrap(),
        )
        .unwrap();
        let mut src = PngSource::open(&path, &Limits::default()).unwrap();
        assert_eq!((src.info().width, src.info().height, src.info().channels), (w, h, c));
        assert_eq!(src.info().meta.icc_profile.as_ref(), Some(&icc));
        let first = drain(&mut src, &mut rng);
        assert_eq!(first, img, "case {i}");
        src.rewind().unwrap();
        assert_eq!(drain(&mut src, &mut rng), img, "case {i} after rewind");
        assert!(src.resident_bytes() < 1 << 20);
    }
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn png_source_handles_palette_low_depth_and_transparency_like_the_decoder() {
    // Files from the PNG decoder tests: palette with tRNS, 1/2/4-bit grey,
    // colour key; decoded both ways.
    let d = tmp("png-kinds");
    let mut rng = Rng::seed_from_u64(9);
    for (i, bytes) in crate::png::tests_support::sample_files().into_iter().enumerate() {
        let path = d.join(format!("{i}.png"));
        std::fs::write(&path, &bytes).unwrap();
        let whole = png::decode(&bytes, &Limits::default()).unwrap();
        match PngSource::open(&path, &Limits::default()) {
            Ok(mut src) => assert_eq!(drain(&mut src, &mut rng), whole.buffer, "file {i}"),
            Err(e) => assert_eq!(
                e.kind(),
                sf_core::ErrorKind::Unsupported,
                "file {i}: only interlacing may be refused"
            ),
        }
    }
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn png_source_rejects_corrupt_and_truncated_data() {
    let d = tmp("png-bad");
    let img = image(80, 60, 3, false, 3);
    let good = png::encode(&img, &Default::default()).unwrap();
    let path = d.join("x.png");
    for (what, bytes) in [
        ("truncated", good[..good.len() - 40].to_vec()),
        ("flipped", {
            let mut b = good.clone();
            let i = b.len() / 2;
            b[i] ^= 0x10;
            b
        }),
    ] {
        std::fs::write(&path, &bytes).unwrap();
        let res = PngSource::open(&path, &Limits::default()).and_then(|mut s| {
            let mut done = 0;
            while done < 60 {
                done += s.read_rows(16)?.height();
            }
            Ok(())
        });
        assert!(res.is_err(), "{what} data accepted");
    }
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn png_sink_output_is_byte_identical_to_whole_encode() {
    let mut rng = Rng::seed_from_u64(11);
    for (w, h, c, sixteen) in
        [(1, 1, 1, false), (31, 77, 3, false), (300, 220, 4, true), (1024, 300, 3, false)]
    {
        let img = image(w, h, c, sixteen, u64::from(w));
        let opts = png::EncodeOptions { icc_profile: Some(vec![1u8; 40]), ..Default::default() };
        let expected = png::encode(&img, &opts).unwrap();
        let mut sink = PngSink::new(Cursor::new(Vec::new()), w, h, c, img.format(), &opts).unwrap();
        let mut y = 0;
        while y < h {
            let n = (1 + rng.below(50) as u32).min(h - y);
            sink.write_band(&img.rows(y, n).unwrap()).unwrap();
            y += n;
        }
        let got = sink.finish_file().unwrap().into_inner();
        assert!(got == expected, "{w}x{h}x{c}");
    }
}

#[test]
fn tiff_sink_output_is_byte_identical_to_whole_encode() {
    let mut rng = Rng::seed_from_u64(13);
    for (w, h, c, sixteen, compression) in [
        (1, 1, 1, false, tiff::Compression::Deflate),
        (45, 200, 3, false, tiff::Compression::Deflate),
        (500, 90, 4, true, tiff::Compression::Deflate),
        (120, 130, 2, false, tiff::Compression::None),
    ] {
        let img = image(w, h, c, sixteen, u64::from(h));
        let opts = tiff::EncodeOptions { compression, icc_profile: Some(vec![7u8; 33]) };
        let expected = tiff::encode(&img, &opts).unwrap();
        let mut sink = TiffSink::new(Cursor::new(Vec::new()), w, h, c, img.format(), &opts).unwrap();
        let mut y = 0;
        while y < h {
            let n = (1 + rng.below(70) as u32).min(h - y);
            sink.write_band(&img.rows(y, n).unwrap()).unwrap();
            y += n;
        }
        let got = sink.finish_file().unwrap().into_inner();
        assert!(got == expected, "{w}x{h}x{c}");
        assert_eq!(tiff::decode(&got, &Limits::default()).unwrap().buffer, img);
    }
}

#[test]
fn sinks_refuse_wrong_bands_and_missing_rows() {
    let img = image(10, 10, 3, false, 1);
    let mut sink =
        PngSink::new(Cursor::new(Vec::new()), 10, 10, 3, img.format(), &Default::default()).unwrap();
    assert!(sink.write_band(&image(11, 2, 3, false, 2)).is_err(), "wrong width");
    sink.write_band(&img.rows(0, 5).unwrap()).unwrap();
    assert!(sink.finish_file().is_err(), "rows missing");
    let mut t = TiffSink::new(Cursor::new(Vec::new()), 10, 10, 3, img.format(), &Default::default()).unwrap();
    t.write_band(&img).unwrap();
    assert!(t.write_band(&img.rows(0, 1).unwrap()).is_err(), "too many rows");
}

#[test]
fn memory_source_applies_orientation_and_serves_bands() {
    let img = image(5, 3, 1, false, 4);
    let meta = ImageMeta { orientation: Some(6), ..ImageMeta::default() };
    let mut src = MemorySource::new(Image { buffer: img.clone(), meta, format: FileFormat::Png });
    assert_eq!((src.info().width, src.info().height), (3, 5));
    assert_eq!(src.info().meta.orientation, None);
    let mut rng = Rng::seed_from_u64(2);
    assert_eq!(drain(&mut src, &mut rng), img.oriented(6));
    assert_eq!(img.oriented(6).oriented(8), img, "6 then 8 is the identity");
}
