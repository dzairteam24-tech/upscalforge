//! TIFF / BigTIFF reader and writer (a documented subset).
//!
//! Read: little- and big-endian, classic and BigTIFF, strips or tiles,
//! chunky or planar layout, compression none / LZW (MSB-first) / Deflate /
//! PackBits, horizontal differencing predictor, 8/16-bit unsigned or
//! 32-bit float samples, grey (either polarity) or RGB, with alpha as the
//! first extra sample, ICC profile and orientation.
//!
//! Write: little-endian strips, uncompressed or Deflate with horizontal
//! prediction, 8/16-bit or float, ICC profile; BigTIFF automatically when
//! offsets would exceed 4 GiB.
//!
//! Other variants (palette, CMYK, JPEG-in-TIFF, 1-bit, YCbCr) are rejected
//! with `Unsupported`.

mod lzw;

use sf_core::{Error, Limits, Result};

use crate::image::{FileFormat, Image, ImageBuffer, ImageMeta, SampleFormat, Samples};
use crate::zlib;

fn bad(what: impl std::fmt::Display) -> Error {
    Error::invalid_input(format!("tiff: {what}"))
}

fn unsupported(what: impl std::fmt::Display) -> Error {
    Error::unsupported(format!("tiff: {what}"))
}

struct Reader<'a> {
    d: &'a [u8],
    le: bool,
    big: bool,
}

impl Reader<'_> {
    fn bytes(&self, at: u64, n: u64) -> Result<&[u8]> {
        let start = usize::try_from(at).map_err(|_| bad("offset out of range"))?;
        let len = usize::try_from(n).map_err(|_| bad("length out of range"))?;
        self.d
            .get(start..start.checked_add(len).ok_or_else(|| bad("offset overflow"))?)
            .ok_or_else(|| bad("data outside the file"))
    }

    fn u16(&self, at: u64) -> Result<u16> {
        let b = self.bytes(at, 2)?;
        Ok(if self.le { u16::from_le_bytes([b[0], b[1]]) } else { u16::from_be_bytes([b[0], b[1]]) })
    }

    fn u32(&self, at: u64) -> Result<u32> {
        let b: [u8; 4] = self.bytes(at, 4)?.try_into().expect("4 bytes");
        Ok(if self.le { u32::from_le_bytes(b) } else { u32::from_be_bytes(b) })
    }

    fn u64(&self, at: u64) -> Result<u64> {
        let b: [u8; 8] = self.bytes(at, 8)?.try_into().expect("8 bytes");
        Ok(if self.le { u64::from_le_bytes(b) } else { u64::from_be_bytes(b) })
    }
}

/// One IFD entry: tag, type, count and the position of its value bytes.
struct Entry {
    tag: u16,
    kind: u16,
    count: u64,
    at: u64,
}

fn type_size(kind: u16) -> Option<u64> {
    Some(match kind {
        1 | 2 | 6 | 7 => 1,
        3 | 8 => 2,
        4 | 9 | 11 | 13 => 4,
        5 | 10 | 12 | 16 | 17 | 18 => 8,
        _ => return None,
    })
}

impl Entry {
    fn values(&self, r: &Reader<'_>, max: u64) -> Result<Vec<u64>> {
        if self.count > max {
            return Err(Error::limit_exceeded(format!("tiff: tag {} has {} values", self.tag, self.count)));
        }
        let size = type_size(self.kind).ok_or_else(|| bad(format!("unknown field type {}", self.kind)))?;
        (0..self.count)
            .map(|i| {
                let p = self.at + i * size;
                Ok(match self.kind {
                    1 | 7 => u64::from(r.bytes(p, 1)?[0]),
                    3 => u64::from(r.u16(p)?),
                    4 | 13 => u64::from(r.u32(p)?),
                    16 | 18 => r.u64(p)?,
                    _ => return Err(bad(format!("tag {} has non-integer type {}", self.tag, self.kind))),
                })
            })
            .collect()
    }
}

fn unpredict(row: &mut [u8], spp: usize, bytes: usize, le: bool) {
    match bytes {
        1 => {
            for i in spp..row.len() {
                row[i] = row[i].wrapping_add(row[i - spp]);
            }
        }
        2 => {
            let n = row.len() / 2;
            let get = |r: &[u8], i: usize| {
                if le {
                    u16::from_le_bytes([r[2 * i], r[2 * i + 1]])
                } else {
                    u16::from_be_bytes([r[2 * i], r[2 * i + 1]])
                }
            };
            for i in spp..n {
                let v = get(row, i).wrapping_add(get(row, i - spp));
                let b = if le { v.to_le_bytes() } else { v.to_be_bytes() };
                row[2 * i] = b[0];
                row[2 * i + 1] = b[1];
            }
        }
        _ => {}
    }
}

fn packbits(src: &[u8], expected: usize) -> Result<Vec<u8>> {
    let mut out = Vec::with_capacity(expected);
    let mut i = 0;
    while i < src.len() && out.len() < expected {
        let n = src[i] as i8;
        i += 1;
        if n >= 0 {
            let len = n as usize + 1;
            out.extend_from_slice(src.get(i..i + len).ok_or_else(|| bad("truncated PackBits literal"))?);
            i += len;
        } else if n != -128 {
            let b = *src.get(i).ok_or_else(|| bad("truncated PackBits run"))?;
            out.extend(std::iter::repeat_n(b, (1 - isize::from(n)) as usize));
            i += 1;
        }
    }
    Ok(out)
}

/// Decodes the first image (IFD 0) of a TIFF file.
pub fn decode(data: &[u8], limits: &Limits) -> Result<Image> {
    let le = match data.get(0..2) {
        Some(b"II") => true,
        Some(b"MM") => false,
        _ => return Err(bad("missing byte-order mark")),
    };
    let mut r = Reader { d: data, le, big: false };
    let magic = r.u16(2)?;
    let first_ifd = match magic {
        42 => u64::from(r.u32(4)?),
        43 => {
            if r.u16(4)? != 8 || r.u16(6)? != 0 {
                return Err(bad("invalid BigTIFF header"));
            }
            r.big = true;
            r.u64(8)?
        }
        _ => return Err(bad("invalid magic number")),
    };
    let (count, entry_size, first) = if r.big {
        (r.u64(first_ifd)?, 20u64, first_ifd + 8)
    } else {
        (u64::from(r.u16(first_ifd)?), 12u64, first_ifd + 2)
    };
    if count > 4096 {
        return Err(bad("implausible number of IFD entries"));
    }
    let inline = if r.big { 8 } else { 4 };
    let mut entries = Vec::with_capacity(count as usize);
    for i in 0..count {
        let e = first + i * entry_size;
        let tag = r.u16(e)?;
        let kind = r.u16(e + 2)?;
        let (cnt, value_at) = if r.big { (r.u64(e + 4)?, e + 12) } else { (u64::from(r.u32(e + 4)?), e + 8) };
        let Some(size) = type_size(kind) else { continue };
        let total = size.checked_mul(cnt).ok_or_else(|| bad("field size overflow"))?;
        let at = if total <= inline {
            value_at
        } else if r.big {
            r.u64(value_at)?
        } else {
            u64::from(r.u32(value_at)?)
        };
        entries.push(Entry { tag, kind, count: cnt, at });
    }
    let find = |tag: u16| entries.iter().find(|e| e.tag == tag);
    let one = |tag: u16, default: Option<u64>| -> Result<u64> {
        match find(tag) {
            Some(e) => {
                e.values(&r, 1 << 20)?.first().copied().ok_or_else(|| bad(format!("tag {tag} is empty")))
            }
            None => default.ok_or_else(|| bad(format!("required tag {tag} missing"))),
        }
    };

    let width = u32::try_from(one(256, None)?).map_err(|_| bad("width out of range"))?;
    let height = u32::try_from(one(257, None)?).map_err(|_| bad("height out of range"))?;
    let spp = one(277, Some(1))? as usize;
    let bits: Vec<u64> = match find(258) {
        Some(e) => e.values(&r, 64)?,
        None => vec![1],
    };
    let depth = bits.first().copied().unwrap_or(1);
    if bits.iter().any(|&b| b != depth) {
        return Err(unsupported("mixed bits per sample"));
    }
    let format = one(339, Some(1))?;
    let sample = match (depth, format) {
        (8, 1) => SampleFormat::U8,
        (16, 1) => SampleFormat::U16,
        (32, 3) => SampleFormat::F32,
        _ => return Err(unsupported(format!("{depth}-bit samples with sample format {format}"))),
    };
    let photometric = one(262, None)?;
    let colors = match photometric {
        0 | 1 => 1usize,
        2 => 3,
        other => return Err(unsupported(format!("photometric interpretation {other}"))),
    };
    if spp < colors || spp > 16 {
        return Err(bad(format!("{spp} samples per pixel for {colors} colour channels")));
    }
    let extras: Vec<u64> = find(338).map(|e| e.values(&r, 16)).transpose()?.unwrap_or_default();
    let has_alpha = spp > colors;
    let premultiplied = has_alpha && extras.first() == Some(&1);
    let compression = one(259, Some(1))?;
    let predictor = one(317, Some(1))?;
    if predictor >= 3 || (predictor == 2 && sample == SampleFormat::F32) {
        return Err(unsupported(format!("predictor {predictor} for this sample format")));
    }
    let planar = one(284, Some(1))? == 2;
    let bytes = sample.bytes() as usize;
    let out_channels = colors + usize::from(has_alpha);
    limits.check_decoded_bytes(width, height, (spp * bytes) as u32)?;

    let tiled = find(322).is_some();
    let (tw, th, offsets, counts) = if tiled {
        (one(322, None)? as usize, one(323, None)? as usize, find(324), find(325))
    } else {
        (
            width as usize,
            one(278, Some(u64::from(height)))?.min(u64::from(height)) as usize,
            find(273),
            find(279),
        )
    };
    if tw == 0 || th == 0 {
        return Err(bad("zero tile or strip size"));
    }
    let (w, h) = (width as usize, height as usize);
    let across = w.div_ceil(tw);
    let down = h.div_ceil(th);
    let planes = if planar { spp } else { 1 };
    let chunk_spp = if planar { 1 } else { spp };
    let expected_chunks = across * down * planes;
    let offsets = offsets.ok_or_else(|| bad("missing data offsets"))?.values(&r, expected_chunks as u64)?;
    let counts = counts.ok_or_else(|| bad("missing byte counts"))?.values(&r, expected_chunks as u64)?;
    if offsets.len() != expected_chunks || counts.len() != expected_chunks {
        return Err(bad(format!("{} data chunks, {expected_chunks} expected", offsets.len())));
    }

    // Raw interleaved samples in file byte order, then converted.
    let row_bytes = w * spp * bytes;
    let mut raw = vec![0u8; row_bytes * h];
    for plane in 0..planes {
        for cy in 0..down {
            for cx in 0..across {
                let idx = plane * across * down + cy * across + cx;
                let chunk_rows = if tiled { th } else { th.min(h - cy * th) };
                let chunk_row_bytes = tw * chunk_spp * bytes;
                let expected = chunk_rows * chunk_row_bytes;
                let src = r.bytes(offsets[idx], counts[idx])?;
                let mut chunk = match compression {
                    1 => src.to_vec(),
                    5 => lzw::decode(src, expected)?,
                    8 | 32946 => zlib::zlib_decompress(src, expected)?,
                    32773 => packbits(src, expected)?,
                    other => return Err(unsupported(format!("compression {other}"))),
                };
                if chunk.len() < expected {
                    return Err(bad(format!(
                        "data chunk {idx} has {} bytes, {expected} expected",
                        chunk.len()
                    )));
                }
                if predictor == 2 {
                    for row in chunk[..expected].chunks_mut(chunk_row_bytes) {
                        unpredict(row, chunk_spp, bytes, le);
                    }
                }
                for y in 0..chunk_rows {
                    let iy = cy * th + y;
                    if iy >= h {
                        break;
                    }
                    for x in 0..tw {
                        let ix = cx * tw + x;
                        if ix >= w {
                            break;
                        }
                        for s in 0..chunk_spp {
                            let dst_s = if planar { plane } else { s };
                            let from = (y * tw + x) * chunk_spp * bytes + s * bytes;
                            let to = iy * row_bytes + (ix * spp + dst_s) * bytes;
                            raw[to..to + bytes].copy_from_slice(&chunk[from..from + bytes]);
                        }
                    }
                }
            }
        }
    }

    let keep = |i: usize| (i % spp) < out_channels;
    let invert = photometric == 0;
    let samples = match sample {
        SampleFormat::U8 => Samples::U8(
            raw.iter()
                .enumerate()
                .filter(|(i, _)| keep(*i))
                .map(|(i, &v)| if invert && i % spp == 0 { 255 - v } else { v })
                .collect(),
        ),
        SampleFormat::U16 => Samples::U16(
            raw.chunks(2)
                .enumerate()
                .filter(|(i, _)| keep(*i))
                .map(|(i, b)| {
                    let v =
                        if le { u16::from_le_bytes([b[0], b[1]]) } else { u16::from_be_bytes([b[0], b[1]]) };
                    if invert && i % spp == 0 { 65_535 - v } else { v }
                })
                .collect(),
        ),
        SampleFormat::F32 => Samples::F32(
            raw.chunks(4)
                .enumerate()
                .filter(|(i, _)| keep(*i))
                .map(|(i, b)| {
                    let a = [b[0], b[1], b[2], b[3]];
                    let v = if le { f32::from_le_bytes(a) } else { f32::from_be_bytes(a) };
                    if invert && i % spp == 0 { 1.0 - v } else { v }
                })
                .collect(),
        ),
    };
    let mut buffer = ImageBuffer::new(width, height, out_channels as u8, samples)?;
    if premultiplied {
        unpremultiply(&mut buffer);
    }
    let mut meta = ImageMeta::default();
    if let Some(e) = find(34675) {
        if e.count > u64::from(limits.max_icc_bytes) {
            return Err(Error::limit_exceeded("tiff: ICC profile exceeds the limit"));
        }
        meta.icc_profile = Some(r.bytes(e.at, e.count)?.to_vec());
    }
    meta.orientation = find(274)
        .and_then(|e| e.values(&r, 1).ok())
        .and_then(|v| v.first().copied())
        .filter(|v| (1..=8).contains(v))
        .map(|v| v as u8);
    Ok(Image { buffer, meta, format: FileFormat::Tiff })
}

/// Converts associated (premultiplied) alpha to straight alpha. Pixels with
/// zero alpha keep zero colour.
fn unpremultiply(buffer: &mut ImageBuffer) {
    let c = buffer.channels() as usize;
    match buffer.samples_mut() {
        Samples::U8(v) => {
            for px in v.chunks_mut(c) {
                let a = u32::from(px[c - 1]);
                if a > 0 {
                    for s in &mut px[..c - 1] {
                        *s = ((u32::from(*s) * 255 + a / 2) / a).min(255) as u8;
                    }
                }
            }
        }
        Samples::U16(v) => {
            for px in v.chunks_mut(c) {
                let a = u64::from(px[c - 1]);
                if a > 0 {
                    for s in &mut px[..c - 1] {
                        *s = ((u64::from(*s) * 65_535 + a / 2) / a).min(65_535) as u16;
                    }
                }
            }
        }
        Samples::F32(v) => {
            for px in v.chunks_mut(c) {
                let a = px[c - 1];
                if a > 0.0 {
                    for s in &mut px[..c - 1] {
                        *s /= a;
                    }
                }
            }
        }
    }
}

/// TIFF compression for writing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Compression {
    /// Uncompressed.
    None,
    /// Deflate (zlib) with horizontal prediction for integer samples.
    Deflate,
}

/// Options for [`encode`].
#[derive(Debug, Clone)]
pub struct EncodeOptions {
    /// Compression.
    pub compression: Compression,
    /// ICC profile to embed.
    pub icc_profile: Option<Vec<u8>>,
}

impl Default for EncodeOptions {
    fn default() -> Self {
        EncodeOptions { compression: Compression::Deflate, icc_profile: None }
    }
}

/// Encodes an image as a little-endian TIFF (BigTIFF when needed).
pub fn encode(image: &ImageBuffer, options: &EncodeOptions) -> Result<Vec<u8>> {
    let (w, h, c) = (image.width() as usize, image.height() as usize, image.channels() as usize);
    let bytes = image.format().bytes() as usize;
    let row_bytes = w * c * bytes;
    let rows_per_strip = (65_536 / row_bytes.max(1)).clamp(1, h);
    let predict = options.compression == Compression::Deflate && image.format() != SampleFormat::F32;
    let mut strips: Vec<Vec<u8>> = Vec::new();
    for y0 in (0..h).step_by(rows_per_strip) {
        let rows = rows_per_strip.min(h - y0);
        let mut strip = Vec::with_capacity(rows * row_bytes);
        for y in y0..y0 + rows {
            let start = y * w * c;
            let mut row: Vec<u8> = match image.samples() {
                Samples::U8(v) => v[start..start + w * c].to_vec(),
                Samples::U16(v) => v[start..start + w * c].iter().flat_map(|s| s.to_le_bytes()).collect(),
                Samples::F32(v) => v[start..start + w * c].iter().flat_map(|s| s.to_le_bytes()).collect(),
            };
            if predict {
                predict_row(&mut row, c, bytes);
            }
            strip.extend(row);
        }
        strips.push(match options.compression {
            Compression::None => strip,
            Compression::Deflate => zlib::zlib_compress(&strip, zlib::Level::Default),
        });
    }
    let data_len: u64 = strips.iter().map(|s| s.len() as u64).sum::<u64>()
        + options.icc_profile.as_ref().map_or(0, |p| p.len() as u64);
    let big = data_len + (1 << 20) > u64::from(u32::MAX);
    write_file(image, options, &strips, rows_per_strip, predict, big)
}

fn predict_row(row: &mut [u8], c: usize, bytes: usize) {
    if bytes == 1 {
        for i in (c..row.len()).rev() {
            row[i] = row[i].wrapping_sub(row[i - c]);
        }
    } else {
        let n = row.len() / 2;
        for i in (c..n).rev() {
            let cur = u16::from_le_bytes([row[2 * i], row[2 * i + 1]]);
            let prev = u16::from_le_bytes([row[2 * (i - c)], row[2 * (i - c) + 1]]);
            row[2 * i..2 * i + 2].copy_from_slice(&cur.wrapping_sub(prev).to_le_bytes());
        }
    }
}

fn write_file(
    image: &ImageBuffer,
    options: &EncodeOptions,
    strips: &[Vec<u8>],
    rows_per_strip: usize,
    predict: bool,
    big: bool,
) -> Result<Vec<u8>> {
    let c = image.channels() as u64;
    let bits = u64::from(image.format().bytes()) * 8;
    let mut out: Vec<u8> = if big { vec![b'I', b'I', 43, 0, 8, 0, 0, 0] } else { vec![b'I', b'I', 42, 0] };
    let header_len = if big { 16 } else { 8 };
    out.resize(header_len, 0);
    // Pixel data and out-of-line values first, then the IFD.
    let mut offsets = Vec::with_capacity(strips.len());
    for s in strips {
        offsets.push(out.len() as u64);
        out.extend_from_slice(s);
        if out.len() % 2 == 1 {
            out.push(0);
        }
    }
    // Entry: (tag, type, values). Types: 3 SHORT, 4 LONG, 16 LONG8, 7 UNDEFINED.
    let long = if big { 16u16 } else { 4u16 };
    let mut entries: Vec<(u16, u16, Vec<u64>)> = vec![
        (256, long, vec![u64::from(image.width())]),
        (257, long, vec![u64::from(image.height())]),
        (258, 3, vec![bits; c as usize]),
        (259, 3, vec![if options.compression == Compression::Deflate { 8 } else { 1 }]),
        (262, 3, vec![if c >= 3 { 2 } else { 1 }]),
        (273, long, offsets),
        (277, 3, vec![c]),
        (278, long, vec![rows_per_strip as u64]),
        (279, long, strips.iter().map(|s| s.len() as u64).collect()),
        (284, 3, vec![1]),
    ];
    if predict {
        entries.push((317, 3, vec![2]));
    }
    if image.has_alpha() {
        entries.push((338, 3, vec![2])); // unassociated alpha
    }
    entries.push((339, 3, vec![if image.format() == SampleFormat::F32 { 3 } else { 1 }; c as usize]));
    let mut icc_at = None;
    if let Some(icc) = &options.icc_profile {
        icc_at = Some(out.len() as u64);
        out.extend_from_slice(icc);
        if out.len() % 2 == 1 {
            out.push(0);
        }
    }
    entries.sort_by_key(|e| e.0);
    let inline = if big { 8 } else { 4 };
    let size_of = |t: u16| type_size(t).expect("known type");
    // Out-of-line arrays.
    let mut value_pos: Vec<Option<u64>> = Vec::new();
    for (_, t, vals) in &entries {
        let total = size_of(*t) * vals.len() as u64;
        if total > inline {
            value_pos.push(Some(out.len() as u64));
            for &v in vals {
                push_value(&mut out, *t, v);
            }
        } else {
            value_pos.push(None);
        }
    }
    let mut n_entries = entries.len() as u64;
    if icc_at.is_some() {
        n_entries += 1;
    }
    if out.len() % 2 == 1 {
        out.push(0);
    }
    let ifd = out.len() as u64;
    if !big && ifd > u64::from(u32::MAX) {
        return Err(Error::internal("tiff: classic offsets overflow; BigTIFF should have been chosen"));
    }
    if big {
        out.extend(n_entries.to_le_bytes());
    } else {
        out.extend((n_entries as u16).to_le_bytes());
    }
    let write_entry =
        |out: &mut Vec<u8>, tag: u16, t: u16, count: u64, inline_bytes: &[u8], pos: Option<u64>| {
            out.extend(tag.to_le_bytes());
            out.extend(t.to_le_bytes());
            if big {
                out.extend(count.to_le_bytes());
            } else {
                out.extend((count as u32).to_le_bytes());
            }
            let start = out.len();
            match pos {
                Some(p) if big => out.extend(p.to_le_bytes()),
                Some(p) => out.extend((p as u32).to_le_bytes()),
                None => out.extend_from_slice(inline_bytes),
            }
            out.resize(start + inline as usize, 0);
        };
    for ((tag, t, vals), pos) in entries.iter().zip(&value_pos) {
        let mut inline_bytes = Vec::new();
        if pos.is_none() {
            for &v in vals {
                push_value(&mut inline_bytes, *t, v);
            }
        }
        write_entry(&mut out, *tag, *t, vals.len() as u64, &inline_bytes, *pos);
    }
    // The ICC tag (34675) has the highest number, so it goes last.
    if let (Some(at), Some(icc)) = (icc_at, &options.icc_profile) {
        let pos = (icc.len() as u64 > inline).then_some(at);
        write_entry(&mut out, 34675, 7, icc.len() as u64, icc, pos);
    }
    if big {
        out.extend(0u64.to_le_bytes());
    } else {
        out.extend(0u32.to_le_bytes());
    }
    // Patch the first-IFD offset.
    if big {
        out[8..16].copy_from_slice(&ifd.to_le_bytes());
    } else {
        out[4..8].copy_from_slice(&(ifd as u32).to_le_bytes());
    }
    Ok(out)
}

fn push_value(out: &mut Vec<u8>, t: u16, v: u64) {
    match t {
        3 => out.extend((v as u16).to_le_bytes()),
        4 => out.extend((v as u32).to_le_bytes()),
        16 => out.extend(v.to_le_bytes()),
        _ => out.push(v as u8),
    }
}

#[cfg(test)]
mod tests;
