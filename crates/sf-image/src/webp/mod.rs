//! WebP decoder (RFC 9649): the RIFF container, lossless (VP8L) and lossy
//! (VP8, RFC 6386) bitstreams, and the `ALPH` alpha chunk.
//!
//! Output is 8-bit RGB, or RGBA when the image carries transparency.
//! Lossy images are converted from Y'CbCr with Rec. 601 coefficients, as
//! the container specification recommends; chroma is upsampled
//! bilinearly. Animated WebP is not supported (only the first frame
//! would be meaningful, and ScaleForge processes still images).
//!
//! Encoding WebP is INCOMPLETE.

mod lossless;
mod vp8;
mod vp8_tables;

use sf_core::{Error, Limits, Result};

use crate::image::{FileFormat, Image, ImageBuffer, ImageMeta, Samples};

fn bad(what: impl std::fmt::Display) -> Error {
    Error::invalid_input(format!("webp: {what}"))
}

/// True if `data` starts like a WebP file.
pub fn is_webp(data: &[u8]) -> bool {
    data.len() >= 12 && &data[0..4] == b"RIFF" && &data[8..12] == b"WEBP"
}

/// Splits the RIFF body into `(fourcc, payload)` chunks.
fn chunks(data: &[u8]) -> Result<Vec<([u8; 4], &[u8])>> {
    if !is_webp(data) {
        return Err(bad("missing RIFF/WEBP header"));
    }
    let riff_size = u32::from_le_bytes(data[4..8].try_into().expect("4 bytes")) as usize;
    // Data after the declared RIFF size is ignored, as the format allows.
    let end = riff_size.saturating_add(8).min(data.len());
    let mut out = Vec::new();
    let mut pos = 12;
    while pos + 8 <= end {
        let fourcc: [u8; 4] = data[pos..pos + 4].try_into().expect("4 bytes");
        let size = u32::from_le_bytes(data[pos + 4..pos + 8].try_into().expect("4 bytes")) as usize;
        let payload = data
            .get(pos + 8..(pos + 8).saturating_add(size))
            .filter(|_| pos + 8 + size <= end)
            .ok_or_else(|| bad(format!("chunk {} exceeds the file", String::from_utf8_lossy(&fourcc))))?;
        out.push((fourcc, payload));
        pos += 8 + size + (size & 1);
    }
    if out.is_empty() {
        return Err(bad("no chunks"));
    }
    Ok(out)
}

/// Decodes a WebP file.
pub fn decode(data: &[u8], limits: &Limits) -> Result<Image> {
    let list = chunks(data)?;
    let mut meta = ImageMeta::default();
    let (first, payload) = list[0];
    let (bitstream, alph, canvas) = match &first {
        b"VP8 " | b"VP8L" => ((first, payload), None, None),
        b"VP8X" => {
            if payload.len() < 10 {
                return Err(bad("VP8X chunk too short"));
            }
            if payload[0] & 0x02 != 0 {
                return Err(Error::unsupported("animated WebP (only still images are supported)"));
            }
            let u24 = |b: &[u8]| u32::from(b[0]) | u32::from(b[1]) << 8 | u32::from(b[2]) << 16;
            let canvas = (1 + u24(&payload[4..7]), 1 + u24(&payload[7..10]));
            let mut alph = None;
            let mut bitstream = None;
            for &(fourcc, body) in &list[1..] {
                match &fourcc {
                    b"ICCP" if meta.icc_profile.is_none() && bitstream.is_none() => {
                        if body.len() > limits.max_icc_bytes as usize {
                            return Err(Error::limit_exceeded("webp: ICC profile exceeds the limit"));
                        }
                        meta.icc_profile = Some(body.to_vec());
                    }
                    b"ANIM" | b"ANMF" => {
                        return Err(Error::unsupported("animated WebP (only still images are supported)"));
                    }
                    b"ALPH" if alph.is_none() && bitstream.is_none() => alph = Some(body),
                    b"VP8 " | b"VP8L" if bitstream.is_none() => bitstream = Some((fourcc, body)),
                    b"EXIF" if meta.orientation.is_none() => {
                        let tiff = body.strip_prefix(b"Exif\0\0").unwrap_or(body);
                        meta.orientation = crate::exif::orientation(tiff);
                    }
                    _ => {} // XMP and unknown chunks are ignored
                }
            }
            (bitstream.ok_or_else(|| bad("no image data"))?, alph, Some(canvas))
        }
        _ => return Err(bad(format!("unexpected first chunk {}", String::from_utf8_lossy(&first)))),
    };
    meta.declares_srgb = meta.icc_profile.is_none(); // the format's default

    let (kind, body) = bitstream;
    let (width, height) = if &kind == b"VP8L" {
        lossless::header(body)?
    } else {
        let (w, h, _) = vp8::header(body)?;
        (w, h)
    };
    if canvas.is_some_and(|c| c != (width, height)) {
        return Err(bad("canvas size differs from the image size"));
    }
    limits.check_decoded_bytes(width, height, 4)?;

    let buffer = if &kind == b"VP8L" {
        let argb = lossless::decode(body, width, height)?;
        let opaque = argb.iter().all(|&p| p >> 24 == 0xFF);
        let channels = if opaque { 3 } else { 4 };
        let mut out = Vec::with_capacity(argb.len() * channels);
        for p in argb {
            out.extend_from_slice(&[(p >> 16) as u8, (p >> 8) as u8, p as u8]);
            if !opaque {
                out.push((p >> 24) as u8);
            }
        }
        ImageBuffer::new(width, height, channels as u8, Samples::U8(out))?
    } else {
        let frame = vp8::decode(body)?;
        let alpha = alph.map(|a| decode_alpha(a, width as usize, height as usize)).transpose()?;
        yuv_to_rgb(&frame, alpha.as_deref())?
    };
    Ok(Image { buffer, meta, format: FileFormat::WebP })
}

/// Decodes an `ALPH` chunk into `width × height` alpha values.
fn decode_alpha(chunk: &[u8], width: usize, height: usize) -> Result<Vec<u8>> {
    let (&head, body) = chunk.split_first().ok_or_else(|| bad("empty ALPH chunk"))?;
    let (compression, filter) = (head & 3, (head >> 2) & 3);
    let mut a = match compression {
        0 => body.get(..width * height).ok_or_else(|| bad("ALPH chunk too short"))?.to_vec(),
        1 => {
            let mut br = lossless::BitReader::new(body);
            let argb = lossless::decode_stream(&mut br, width, height)?;
            argb.into_iter().map(|p| (p >> 8) as u8).collect() // green carries alpha
        }
        c => return Err(bad(format!("unknown alpha compression {c}"))),
    };
    // Undo the prediction filter (RFC 9649 §2.7.1.2), in scan order.
    if filter != 0 {
        for y in 0..height {
            for x in 0..width {
                let i = y * width + x;
                let pred = match (x, y) {
                    (0, 0) => 0,
                    (_, 0) => a[i - 1],
                    (0, _) => a[i - width],
                    _ => match filter {
                        1 => a[i - 1],
                        2 => a[i - width],
                        _ => (i32::from(a[i - 1]) + i32::from(a[i - width]) - i32::from(a[i - width - 1]))
                            .clamp(0, 255) as u8,
                    },
                };
                a[i] = a[i].wrapping_add(pred);
            }
        }
    }
    Ok(a)
}

/// Converts the decoded 4:2:0 frame to 8-bit RGB(A). Each chroma sample
/// sits between two luma samples in each direction; a luma pixel takes
/// 9/16 of its nearest chroma sample, 3/16 of each of the two next
/// nearest and 1/16 of the diagonal one (clamped at the edges).
fn yuv_to_rgb(f: &vp8::Frame, alpha: Option<&[u8]>) -> Result<ImageBuffer> {
    let (w, h) = (f.width, f.height);
    let (cw, ch) = (w.div_ceil(2), h.div_ceil(2));
    let channels = if alpha.is_some() { 4 } else { 3 };
    let mut out = Vec::with_capacity(w * h * channels);
    // Neighbouring chroma index in the direction of the luma position.
    let far = |i: usize, odd: bool, n: usize| if odd { (i + 1).min(n - 1) } else { i.saturating_sub(1) };
    for y in 0..h {
        let (cy, fy) = (y / 2, far(y / 2, y % 2 == 1, ch));
        for x in 0..w {
            let (cx, fx) = (x / 2, far(x / 2, x % 2 == 1, cw));
            let sample = |p: &[u8]| {
                let at = |yy: usize, xx: usize| f32::from(p[yy * f.uv_stride + xx]);
                (9.0 * at(cy, cx) + 3.0 * at(cy, fx) + 3.0 * at(fy, cx) + at(fy, fx)) / 16.0 - 128.0
            };
            let (u, v) = (sample(&f.u), sample(&f.v));
            let luma = 1.164_383 * (f32::from(f.y[y * f.y_stride + x]) - 16.0);
            let to8 = |c: f32| c.round().clamp(0.0, 255.0) as u8;
            out.extend_from_slice(&[
                to8(luma + 1.596_027 * v),
                to8(luma - 0.391_762 * u - 0.812_968 * v),
                to8(luma + 2.017_232 * u),
            ]);
            if let Some(a) = alpha {
                out.push(a[y * w + x]);
            }
        }
    }
    ImageBuffer::new(w as u32, h as u32, channels as u8, Samples::U8(out))
}

#[cfg(test)]
mod tests;
