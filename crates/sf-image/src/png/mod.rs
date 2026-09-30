//! PNG decoder and encoder (ISO/IEC 15948).
//!
//! Decoding supports every standard colour type and bit depth, palettes
//! with transparency, and Adam7 interlacing. All chunk CRCs are verified,
//! and the decompressed size must match the header exactly. Output is 8-bit
//! for depths ≤ 8 and 16-bit for depth 16.
//!
//! Encoding writes 8- or 16-bit grey, grey+alpha, RGB or RGBA, with an
//! optional ICC profile. It uses per-row adaptive filtering and our own
//! DEFLATE.

use sf_core::{Error, Limits, Result};

use crate::checksum::{Crc32, crc32};
use crate::image::{FileFormat, Image, ImageBuffer, ImageMeta, SampleFormat, Samples};
use crate::zlib;

/// The 8-byte PNG signature.
pub const SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];

fn bad(what: impl std::fmt::Display) -> Error {
    Error::invalid_input(format!("png: {what}"))
}

struct Header {
    width: u32,
    height: u32,
    depth: u8,
    color: u8,
    interlaced: bool,
}

impl Header {
    fn samples_per_pixel(&self) -> usize {
        match self.color {
            0 | 3 => 1,
            4 => 2,
            2 => 3,
            _ => 4,
        }
    }

    fn row_bytes(&self, width: usize) -> usize {
        (width * self.samples_per_pixel() * self.depth as usize).div_ceil(8)
    }

    /// Bytes per complete pixel for filtering (at least 1).
    fn filter_bpp(&self) -> usize {
        (self.samples_per_pixel() * self.depth as usize).div_ceil(8).max(1)
    }
}

/// Adam7 pass origins and steps: (x0, y0, dx, dy).
const ADAM7: [(usize, usize, usize, usize); 7] =
    [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)];

fn passes(h: &Header) -> Vec<(usize, usize, usize, usize, usize, usize)> {
    let (w, ht) = (h.width as usize, h.height as usize);
    if !h.interlaced {
        return vec![(0, 0, 1, 1, w, ht)];
    }
    ADAM7
        .iter()
        .map(|&(x0, y0, dx, dy)| {
            let pw = if w > x0 { (w - x0).div_ceil(dx) } else { 0 };
            let ph = if ht > y0 { (ht - y0).div_ceil(dy) } else { 0 };
            (x0, y0, dx, dy, pw, ph)
        })
        .collect()
}

fn paeth(a: u8, b: u8, c: u8) -> u8 {
    let p = i16::from(a) + i16::from(b) - i16::from(c);
    let (pa, pb, pc) = ((p - i16::from(a)).abs(), (p - i16::from(b)).abs(), (p - i16::from(c)).abs());
    if pa <= pb && pa <= pc {
        a
    } else if pb <= pc {
        b
    } else {
        c
    }
}

fn unfilter(kind: u8, row: &mut [u8], prev: &[u8], bpp: usize) -> Result<()> {
    match kind {
        0 => {}
        1 => {
            for i in bpp..row.len() {
                row[i] = row[i].wrapping_add(row[i - bpp]);
            }
        }
        2 => {
            for (r, &p) in row.iter_mut().zip(prev) {
                *r = r.wrapping_add(p);
            }
        }
        3 => {
            for i in 0..row.len() {
                let left = if i >= bpp { u16::from(row[i - bpp]) } else { 0 };
                row[i] = row[i].wrapping_add(((left + u16::from(prev[i])) / 2) as u8);
            }
        }
        4 => {
            for i in 0..row.len() {
                let (a, c) = if i >= bpp { (row[i - bpp], prev[i - bpp]) } else { (0, 0) };
                row[i] = row[i].wrapping_add(paeth(a, prev[i], c));
            }
        }
        k => return Err(bad(format!("invalid filter type {k}"))),
    }
    Ok(())
}

/// Decodes a PNG file.
pub fn decode(data: &[u8], limits: &Limits) -> Result<Image> {
    if data.get(..8) != Some(&SIGNATURE[..]) {
        return Err(bad("missing signature"));
    }
    let mut pos = 8;
    let mut header: Option<Header> = None;
    let mut idat: Vec<u8> = Vec::new();
    let mut palette: Vec<[u8; 3]> = Vec::new();
    let mut trns: Option<Vec<u8>> = None;
    let mut meta = ImageMeta::default();
    let mut seen_iend = false;
    while pos < data.len() {
        let len = u32::from_be_bytes(
            data.get(pos..pos + 4).ok_or_else(|| bad("truncated chunk"))?.try_into().expect("4 bytes"),
        );
        if len > 0x7FFF_FFFF {
            return Err(bad("chunk length out of range"));
        }
        let len = len as usize;
        let kind: [u8; 4] =
            data.get(pos + 4..pos + 8).ok_or_else(|| bad("truncated chunk"))?.try_into().expect("4 bytes");
        let body = data.get(pos + 8..pos + 8 + len).ok_or_else(|| bad("truncated chunk data"))?;
        let crc_bytes = data.get(pos + 8 + len..pos + 12 + len).ok_or_else(|| bad("missing chunk CRC"))?;
        let mut crc = Crc32::default();
        crc.update(&kind);
        crc.update(body);
        if crc.finish() != u32::from_be_bytes(crc_bytes.try_into().expect("4 bytes")) {
            return Err(bad(format!("CRC mismatch in {} chunk", String::from_utf8_lossy(&kind))));
        }
        pos += 12 + len;
        if header.is_none() && &kind != b"IHDR" {
            return Err(bad("first chunk is not IHDR"));
        }
        match &kind {
            b"IHDR" => {
                if header.is_some() || len != 13 {
                    return Err(bad("invalid IHDR"));
                }
                let width = u32::from_be_bytes(body[0..4].try_into().expect("4 bytes"));
                let height = u32::from_be_bytes(body[4..8].try_into().expect("4 bytes"));
                let (depth, color) = (body[8], body[9]);
                let valid = matches!(
                    (color, depth),
                    (0, 1 | 2 | 4 | 8 | 16) | (3, 1 | 2 | 4 | 8) | (2 | 4 | 6, 8 | 16)
                );
                if !valid || body[10] != 0 || body[11] != 0 || body[12] > 1 {
                    return Err(bad(format!("unsupported header: colour type {color}, depth {depth}")));
                }
                let h = Header { width, height, depth, color, interlaced: body[12] == 1 };
                let out_channels = match color {
                    0 => 1,
                    4 => 2,
                    2 => 3,
                    _ => 4, // 6, and 3 (palette) is widened below as needed
                };
                limits.check_decoded_bytes(width, height, out_channels * if depth == 16 { 2 } else { 1 })?;
                header = Some(h);
            }
            b"PLTE" => {
                if !len.is_multiple_of(3) || len == 0 || len > 768 {
                    return Err(bad("invalid palette"));
                }
                palette = body.chunks(3).map(|c| [c[0], c[1], c[2]]).collect();
            }
            b"tRNS" => trns = Some(body.to_vec()),
            b"IDAT" => {
                if idat.len() + len > limits.max_decoded_bytes as usize * 2 + (1 << 20) {
                    return Err(Error::limit_exceeded("png: compressed data exceeds the limit"));
                }
                idat.extend_from_slice(body);
            }
            b"iCCP" => {
                let name_end = body.iter().position(|&b| b == 0).ok_or_else(|| bad("invalid iCCP"))?;
                if body.get(name_end + 1) != Some(&0) {
                    return Err(bad("unknown iCCP compression"));
                }
                let profile = zlib::zlib_decompress(&body[name_end + 2..], limits.max_icc_bytes as usize)?;
                meta.icc_profile = Some(profile);
            }
            b"sRGB" => meta.declares_srgb = true,
            b"gAMA" if len == 4 => {
                let g = u32::from_be_bytes(body.try_into().expect("4 bytes"));
                if g > 0 {
                    meta.gamma = Some(f64::from(g) / 100_000.0);
                }
            }
            b"eXIf" => meta.orientation = crate::exif::orientation(body),
            b"IEND" => {
                seen_iend = true;
                break;
            }
            other => {
                if other[0].is_ascii_uppercase() {
                    return Err(Error::unsupported(format!(
                        "png: unknown critical chunk {}",
                        String::from_utf8_lossy(other)
                    )));
                }
            }
        }
    }
    let h = header.ok_or_else(|| bad("no IHDR"))?;
    if !seen_iend {
        return Err(bad("missing IEND"));
    }
    if h.color == 3 && palette.is_empty() {
        return Err(bad("palette image without PLTE"));
    }

    let pass_list = passes(&h);
    let expected: usize =
        pass_list.iter().filter(|p| p.4 > 0 && p.5 > 0).map(|p| p.5 * (1 + h.row_bytes(p.4))).sum();
    let raw = zlib::zlib_decompress(&idat, expected)?;
    if raw.len() != expected {
        return Err(bad(format!("image data has {} bytes, {expected} expected", raw.len())));
    }

    let (w, ht) = (h.width as usize, h.height as usize);
    let spp = h.samples_per_pixel();
    // Samples per pixel in the decoded, still-unexpanded form (palette = index).
    let mut plain: Vec<u16> = vec![0; w * ht * spp];
    let bpp = h.filter_bpp();
    let mut at = 0;
    for &(x0, y0, dx, dy, pw, ph) in &pass_list {
        if pw == 0 || ph == 0 {
            continue;
        }
        let rb = h.row_bytes(pw);
        let mut prev = vec![0u8; rb];
        for py in 0..ph {
            let kind = raw[at];
            let mut row = raw[at + 1..at + 1 + rb].to_vec();
            at += 1 + rb;
            unfilter(kind, &mut row, &prev, bpp)?;
            for px in 0..pw {
                let (x, y) = (x0 + px * dx, y0 + py * dy);
                for s in 0..spp {
                    let idx = px * spp + s;
                    let v = match h.depth {
                        16 => u16::from_be_bytes([row[idx * 2], row[idx * 2 + 1]]),
                        8 => u16::from(row[idx]),
                        d => {
                            let bit = idx * d as usize;
                            let byte = row[bit / 8];
                            let shift = 8 - d as usize - bit % 8;
                            u16::from((byte >> shift) & ((1u8 << d) - 1))
                        }
                    };
                    plain[(y * w + x) * spp + s] = v;
                }
            }
            prev = row;
        }
    }

    let buffer = expand(&h, plain, &palette, trns.as_deref())?;
    Ok(Image { buffer, meta, format: FileFormat::Png })
}

/// Converts raw samples to 8/16-bit grey/GA/RGB/RGBA, applying the palette
/// and transparency.
fn expand(h: &Header, plain: Vec<u16>, palette: &[[u8; 3]], trns: Option<&[u8]>) -> Result<ImageBuffer> {
    let (w, ht) = (h.width, h.height);
    let scale_low = |v: u16| -> u8 {
        match h.depth {
            1 => (v * 255) as u8,
            2 => (v * 85) as u8,
            4 => (v * 17) as u8,
            _ => v as u8,
        }
    };
    let key16 = |t: &[u8], i: usize| t.get(i * 2..i * 2 + 2).map(|b| u16::from_be_bytes([b[0], b[1]]));
    match h.color {
        3 => {
            let alpha: Vec<u8> = trns.map(|t| t.to_vec()).unwrap_or_default();
            let channels: u8 = if alpha.is_empty() { 3 } else { 4 };
            let mut out = Vec::with_capacity(plain.len() * channels as usize);
            for &i in &plain {
                let rgb = palette.get(i as usize).ok_or_else(|| bad("palette index out of range"))?;
                out.extend_from_slice(rgb);
                if channels == 4 {
                    out.push(alpha.get(i as usize).copied().unwrap_or(255));
                }
            }
            ImageBuffer::new(w, ht, channels, Samples::U8(out))
        }
        0 | 2 => {
            let spp = h.samples_per_pixel();
            let key: Option<Vec<u16>> = trns.and_then(|t| (0..spp).map(|i| key16(t, i)).collect());
            let channels = (spp + usize::from(key.is_some())) as u8;
            let full = if h.depth == 16 { 65_535 } else { 255 };
            let mut out: Vec<u16> = Vec::with_capacity(plain.len() / spp * channels as usize);
            for px in plain.chunks(spp) {
                for &v in px {
                    out.push(if h.depth == 16 { v } else { u16::from(scale_low(v)) });
                }
                if let Some(k) = &key {
                    out.push(if px == k.as_slice() { 0 } else { full });
                }
            }
            finish(w, ht, channels, out, h.depth == 16)
        }
        _ => {
            let channels = h.samples_per_pixel() as u8;
            finish(w, ht, channels, plain, h.depth == 16)
        }
    }
}

fn finish(w: u32, h: u32, channels: u8, v: Vec<u16>, sixteen: bool) -> Result<ImageBuffer> {
    if sixteen {
        ImageBuffer::new(w, h, channels, Samples::U16(v))
    } else {
        ImageBuffer::new(w, h, channels, Samples::U8(v.into_iter().map(|x| x as u8).collect()))
    }
}

// ------------------------------------------------------------------ encoder

fn write_chunk(out: &mut Vec<u8>, kind: &[u8; 4], body: &[u8]) {
    out.extend_from_slice(&(body.len() as u32).to_be_bytes());
    let start = out.len();
    out.extend_from_slice(kind);
    out.extend_from_slice(body);
    let crc = crc32(&out[start..]);
    out.extend_from_slice(&crc.to_be_bytes());
}

/// Options for [`encode`].
#[derive(Debug, Clone)]
pub struct EncodeOptions {
    /// DEFLATE effort.
    pub level: zlib::Level,
    /// ICC profile to embed.
    pub icc_profile: Option<Vec<u8>>,
    /// Write an `sRGB` chunk (ignored when an ICC profile is given).
    pub srgb: bool,
}

impl Default for EncodeOptions {
    fn default() -> Self {
        EncodeOptions { level: zlib::Level::Default, icc_profile: None, srgb: false }
    }
}

/// Encodes an 8- or 16-bit image as PNG.
pub fn encode(image: &ImageBuffer, options: &EncodeOptions) -> Result<Vec<u8>> {
    let (depth, bytes_per_sample) = match image.format() {
        SampleFormat::U8 => (8u8, 1usize),
        SampleFormat::U16 => (16, 2),
        SampleFormat::F32 => return Err(Error::unsupported("png: floating-point samples cannot be stored")),
    };
    let color = match image.channels() {
        1 => 0u8,
        2 => 4,
        3 => 2,
        _ => 6,
    };
    let (w, h) = (image.width() as usize, image.height() as usize);
    let bpp = image.channels() as usize * bytes_per_sample;
    let row_bytes = w * bpp;

    let mut out = SIGNATURE.to_vec();
    let mut ihdr = Vec::with_capacity(13);
    ihdr.extend_from_slice(&image.width().to_be_bytes());
    ihdr.extend_from_slice(&image.height().to_be_bytes());
    ihdr.extend_from_slice(&[depth, color, 0, 0, 0]);
    write_chunk(&mut out, b"IHDR", &ihdr);
    if let Some(icc) = &options.icc_profile {
        let mut body = b"ICC profile\0\0".to_vec();
        body.extend(zlib::zlib_compress(icc, zlib::Level::Best));
        write_chunk(&mut out, b"iCCP", &body);
    } else if options.srgb {
        write_chunk(&mut out, b"sRGB", &[0]); // perceptual rendering intent
    }

    // Serialise rows big-endian, then filter each row adaptively.
    let row = |y: usize| -> Vec<u8> {
        match image.samples() {
            Samples::U8(v) => v[y * row_bytes..(y + 1) * row_bytes].to_vec(),
            Samples::U16(v) => v[y * w * image.channels() as usize..(y + 1) * w * image.channels() as usize]
                .iter()
                .flat_map(|s| s.to_be_bytes())
                .collect(),
            Samples::F32(_) => unreachable!("rejected above"),
        }
    };
    let mut filtered = Vec::with_capacity(h * (row_bytes + 1));
    let mut prev = vec![0u8; row_bytes];
    let mut candidate = vec![0u8; row_bytes];
    for y in 0..h {
        let cur = row(y);
        let mut best: (u64, u8) = (u64::MAX, 0);
        let mut best_row = Vec::new();
        for kind in 0..5u8 {
            for i in 0..row_bytes {
                let (a, b) = (if i >= bpp { cur[i - bpp] } else { 0 }, prev[i]);
                let c = if i >= bpp { prev[i - bpp] } else { 0 };
                let pred = match kind {
                    0 => 0,
                    1 => a,
                    2 => b,
                    3 => ((u16::from(a) + u16::from(b)) / 2) as u8,
                    _ => paeth(a, b, c),
                };
                candidate[i] = cur[i].wrapping_sub(pred);
            }
            // Heuristic: minimise the sum of absolute signed residuals.
            let cost: u64 = candidate.iter().map(|&v| u64::from((v as i8).unsigned_abs())).sum();
            if cost < best.0 {
                best = (cost, kind);
                best_row.clone_from(&candidate);
            }
        }
        filtered.push(best.1);
        filtered.extend_from_slice(&best_row);
        prev = cur;
    }
    let compressed = zlib::zlib_compress(&filtered, options.level);
    for chunk in compressed.chunks(1 << 20) {
        write_chunk(&mut out, b"IDAT", chunk);
    }
    write_chunk(&mut out, b"IEND", &[]);
    Ok(out)
}

#[cfg(test)]
mod tests;
