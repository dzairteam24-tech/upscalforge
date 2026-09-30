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
//!
//! Streaming: [`PngSource`] decodes a non-interlaced file band by band and
//! [`PngSink`] encodes band by band; its output is byte-for-byte that of
//! [`encode`].

use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use sf_core::{Error, Limits, Result};

use crate::checksum::{Crc32, crc32};
use crate::image::{FileFormat, Image, ImageBuffer, ImageMeta, SampleFormat, Samples};
use crate::stream::{RowSink, RowSource, SourceInfo, check_band};
use crate::zlib;

/// The 8-byte PNG signature.
pub const SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];

fn bad(what: impl std::fmt::Display) -> Error {
    Error::invalid_input(format!("png: {what}"))
}

#[derive(Clone, Copy)]
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

    /// Channels and sample format after expansion (the same rules as
    /// [`expand`]: a transparency chunk too short for its colour type is
    /// ignored).
    fn output(&self, trns: Option<&[u8]>) -> (u8, SampleFormat) {
        let t = trns.map_or(0, <[u8]>::len);
        let channels = match self.color {
            0 => 1 + u8::from(t >= 2),
            2 => 3 + u8::from(t >= 6),
            3 => 3 + u8::from(t > 0),
            4 => 2,
            _ => 4,
        };
        (channels, if self.depth == 16 { SampleFormat::U16 } else { SampleFormat::U8 })
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

/// Appends the `width` pixels of an unfiltered row as plain sample values
/// (palette images: indices).
fn unpack_row(h: &Header, row: &[u8], width: usize, out: &mut Vec<u16>) {
    let n = width * h.samples_per_pixel();
    match h.depth {
        16 => out.extend((0..n).map(|i| u16::from_be_bytes([row[i * 2], row[i * 2 + 1]]))),
        8 => out.extend(row[..n].iter().map(|&b| u16::from(b))),
        d => out.extend((0..n).map(|i| {
            let bit = i * d as usize;
            let shift = 8 - d as usize - bit % 8;
            u16::from((row[bit / 8] >> shift) & ((1u8 << d) - 1))
        })),
    }
}

/// Everything read from the chunks that precede the image data.
#[derive(Default)]
struct HeadState {
    header: Option<Header>,
    palette: Vec<[u8; 3]>,
    trns: Option<Vec<u8>>,
    meta: ImageMeta,
}

/// Interprets one chunk other than IDAT and IEND.
fn handle_chunk(st: &mut HeadState, kind: &[u8; 4], body: &[u8], limits: &Limits) -> Result<()> {
    if st.header.is_none() && kind != b"IHDR" {
        return Err(bad("first chunk is not IHDR"));
    }
    match kind {
        b"IHDR" => {
            if st.header.is_some() || body.len() != 13 {
                return Err(bad("invalid IHDR"));
            }
            let width = u32::from_be_bytes(body[0..4].try_into().expect("4 bytes"));
            let height = u32::from_be_bytes(body[4..8].try_into().expect("4 bytes"));
            let (depth, color) = (body[8], body[9]);
            let valid =
                matches!((color, depth), (0, 1 | 2 | 4 | 8 | 16) | (3, 1 | 2 | 4 | 8) | (2 | 4 | 6, 8 | 16));
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
            st.header = Some(h);
        }
        b"PLTE" => {
            if !body.len().is_multiple_of(3) || body.is_empty() || body.len() > 768 {
                return Err(bad("invalid palette"));
            }
            st.palette = body.chunks(3).map(|c| [c[0], c[1], c[2]]).collect();
        }
        b"tRNS" => st.trns = Some(body.to_vec()),
        b"iCCP" => {
            let name_end = body.iter().position(|&b| b == 0).ok_or_else(|| bad("invalid iCCP"))?;
            if body.get(name_end + 1) != Some(&0) {
                return Err(bad("unknown iCCP compression"));
            }
            let profile = zlib::zlib_decompress(&body[name_end + 2..], limits.max_icc_bytes as usize)?;
            st.meta.icc_profile = Some(profile);
        }
        b"sRGB" => st.meta.declares_srgb = true,
        b"gAMA" if body.len() == 4 => {
            let g = u32::from_be_bytes(body.try_into().expect("4 bytes"));
            if g > 0 {
                st.meta.gamma = Some(f64::from(g) / 100_000.0);
            }
        }
        b"eXIf" => st.meta.orientation = crate::exif::orientation(body),
        other => {
            if other[0].is_ascii_uppercase() {
                return Err(Error::unsupported(format!(
                    "png: unknown critical chunk {}",
                    String::from_utf8_lossy(other)
                )));
            }
        }
    }
    Ok(())
}

/// Decodes a PNG file.
pub fn decode(data: &[u8], limits: &Limits) -> Result<Image> {
    if data.get(..8) != Some(&SIGNATURE[..]) {
        return Err(bad("missing signature"));
    }
    let mut pos = 8;
    let mut st = HeadState::default();
    let mut idat: Vec<u8> = Vec::new();
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
        match &kind {
            b"IDAT" if st.header.is_some() => {
                if idat.len() + len > limits.max_decoded_bytes as usize * 2 + (1 << 20) {
                    return Err(Error::limit_exceeded("png: compressed data exceeds the limit"));
                }
                idat.extend_from_slice(body);
            }
            b"IEND" if st.header.is_some() => {
                seen_iend = true;
                break;
            }
            _ => handle_chunk(&mut st, &kind, body, limits)?,
        }
    }
    let h = st.header.ok_or_else(|| bad("no IHDR"))?;
    if !seen_iend {
        return Err(bad("missing IEND"));
    }
    if h.color == 3 && st.palette.is_empty() {
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
    let mut values = Vec::new();
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
            values.clear();
            unpack_row(&h, &row, pw, &mut values);
            for (px, v) in values.chunks(spp).enumerate() {
                let (x, y) = (x0 + px * dx, y0 + py * dy);
                plain[(y * w + x) * spp..(y * w + x + 1) * spp].copy_from_slice(v);
            }
            prev = row;
        }
    }

    let buffer = expand(&h, h.height, plain, &st.palette, st.trns.as_deref())?;
    Ok(Image { buffer, meta: st.meta, format: FileFormat::Png })
}

/// Converts `rows` rows of raw samples to 8/16-bit grey/GA/RGB/RGBA,
/// applying the palette and transparency.
fn expand(
    h: &Header,
    rows: u32,
    plain: Vec<u16>,
    palette: &[[u8; 3]],
    trns: Option<&[u8]>,
) -> Result<ImageBuffer> {
    let w = h.width;
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
            ImageBuffer::new(w, rows, channels, Samples::U8(out))
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
            finish(w, rows, channels, out, h.depth == 16)
        }
        _ => {
            let channels = h.samples_per_pixel() as u8;
            finish(w, rows, channels, plain, h.depth == 16)
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

// ------------------------------------------------------------ streaming decoder

/// Reads the payload of consecutive IDAT chunks as one byte stream,
/// verifying each chunk's CRC. Ends at the first chunk that is not IDAT.
struct IdatReader<R: Read> {
    r: R,
    left: u32,
    crc: Crc32,
    done: bool,
}

fn io_bad(what: &str) -> std::io::Error {
    std::io::Error::new(std::io::ErrorKind::InvalidData, format!("png: {what}"))
}

impl<R: Read> Read for IdatReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        while self.left == 0 {
            if self.done {
                return Ok(0);
            }
            let mut c = [0u8; 4];
            self.r.read_exact(&mut c)?;
            if u32::from_be_bytes(c) != std::mem::take(&mut self.crc).finish() {
                return Err(io_bad("CRC mismatch in IDAT chunk"));
            }
            let mut head = [0u8; 8];
            self.r.read_exact(&mut head)?;
            if &head[4..8] != b"IDAT" {
                // Chunks after the image data are not needed for the pixels.
                self.done = true;
                return Ok(0);
            }
            self.left = u32::from_be_bytes(head[0..4].try_into().expect("4 bytes"));
            if self.left > 0x7FFF_FFFF {
                return Err(io_bad("chunk length out of range"));
            }
            self.crc.update(b"IDAT");
        }
        let n = (self.left as usize).min(buf.len());
        let got = self.r.read(&mut buf[..n])?;
        if got == 0 {
            return Err(io_bad("truncated IDAT chunk"));
        }
        self.crc.update(&buf[..got]);
        self.left -= got as u32;
        Ok(got)
    }
}

type Inner = zlib::ZlibReader<IdatReader<std::io::BufReader<std::fs::File>>>;

/// A non-interlaced PNG file decoded band by band. Memory holds one band
/// and the DEFLATE window, whatever the image size.
pub struct PngSource {
    path: PathBuf,
    limits: Limits,
    header: Header,
    palette: Vec<[u8; 3]>,
    trns: Option<Vec<u8>>,
    info: SourceInfo,
    data: Inner,
    prev: Vec<u8>,
    next: u32,
}

/// Parses the chunks before the image data and positions a reader at it.
fn open_png(path: &Path, limits: &Limits) -> Result<(HeadState, Inner)> {
    let file = std::fs::File::open(path).map_err(|e| Error::from(e).context(path.display()))?;
    let mut r = std::io::BufReader::new(file);
    let mut sig = [0u8; 8];
    r.read_exact(&mut sig).map_err(|_| bad("missing signature"))?;
    if sig != SIGNATURE {
        return Err(bad("missing signature"));
    }
    let mut st = HeadState::default();
    loop {
        let mut head = [0u8; 8];
        r.read_exact(&mut head).map_err(|_| bad("truncated chunk"))?;
        let len = u32::from_be_bytes(head[0..4].try_into().expect("4 bytes"));
        if len > 0x7FFF_FFFF {
            return Err(bad("chunk length out of range"));
        }
        let kind: [u8; 4] = head[4..8].try_into().expect("4 bytes");
        if &kind == b"IDAT" {
            let h = st.header.ok_or_else(|| bad("first chunk is not IHDR"))?;
            if h.color == 3 && st.palette.is_empty() {
                return Err(bad("palette image without PLTE"));
            }
            let mut crc = Crc32::default();
            crc.update(b"IDAT");
            let idat = IdatReader { r, left: len, crc, done: false };
            let rows = h.height as u64 * (1 + h.row_bytes(h.width as usize)) as u64;
            return Ok((st, zlib::ZlibReader::new(idat, rows)?));
        }
        if &kind == b"IEND" {
            return Err(bad("no image data"));
        }
        // Chunks before the image data are small metadata; one larger than
        // the metadata limit is refused rather than buffered.
        if u64::from(len) > u64::from(limits.max_metadata_bytes.max(limits.max_icc_bytes)) + 4096 {
            return Err(Error::limit_exceeded(format!(
                "png: {} chunk of {len} bytes before the image data",
                String::from_utf8_lossy(&kind)
            )));
        }
        let mut body = vec![0u8; len as usize + 4];
        r.read_exact(&mut body).map_err(|_| bad("truncated chunk data"))?;
        let crc_bytes = body.split_off(len as usize);
        let mut crc = Crc32::default();
        crc.update(&kind);
        crc.update(&body);
        if crc.finish() != u32::from_be_bytes(crc_bytes[..].try_into().expect("4 bytes")) {
            return Err(bad(format!("CRC mismatch in {} chunk", String::from_utf8_lossy(&kind))));
        }
        handle_chunk(&mut st, &kind, &body, limits)?;
    }
}

impl PngSource {
    /// Opens a file. Interlaced images cannot be streamed (`Unsupported`);
    /// decode them whole instead.
    pub fn open(path: &Path, limits: &Limits) -> Result<PngSource> {
        let (st, data) = open_png(path, limits)?;
        let header = st.header.expect("checked when the image data was found");
        if header.interlaced {
            return Err(Error::unsupported("png: interlaced images cannot be decoded band by band"));
        }
        let (channels, sample) = header.output(st.trns.as_deref());
        let info = SourceInfo {
            width: header.width,
            height: header.height,
            channels,
            sample,
            meta: st.meta,
            format: FileFormat::Png,
        };
        Ok(PngSource {
            path: path.to_path_buf(),
            limits: limits.clone(),
            header,
            palette: st.palette,
            trns: st.trns,
            info,
            data,
            prev: vec![0; header.row_bytes(header.width as usize)],
            next: 0,
        })
    }
}

impl RowSource for PngSource {
    fn info(&self) -> &SourceInfo {
        &self.info
    }

    fn read_rows(&mut self, rows: u32) -> Result<ImageBuffer> {
        let h = self.header;
        if self.next >= h.height || rows == 0 {
            return Err(Error::invalid_input("no rows left in the source"));
        }
        let n = rows.min(h.height - self.next);
        let rb = h.row_bytes(h.width as usize);
        let want = n as usize * (1 + rb);
        let mut raw = Vec::with_capacity(want);
        if self.data.read_into(want, &mut raw)? < want {
            return Err(bad(format!("image data ends before row {}", self.next + n)));
        }
        let mut plain = Vec::with_capacity(n as usize * h.width as usize * h.samples_per_pixel());
        for filtered in raw.chunks(1 + rb) {
            let mut row = filtered[1..].to_vec();
            unfilter(filtered[0], &mut row, &self.prev, h.filter_bpp())?;
            unpack_row(&h, &row, h.width as usize, &mut plain);
            self.prev = row;
        }
        self.next += n;
        if self.next == h.height {
            // The stream must end exactly here (this also checks Adler-32).
            let mut extra = Vec::new();
            if self.data.read_into(1, &mut extra)? != 0 {
                return Err(bad("more image data than the header declares"));
            }
        }
        expand(&h, n, plain, &self.palette, self.trns.as_deref())
    }

    fn rewind(&mut self) -> Result<()> {
        let (_, data) = open_png(&self.path, &self.limits)?;
        self.data = data;
        self.prev.fill(0);
        self.next = 0;
        Ok(())
    }

    fn resident_bytes(&self) -> u64 {
        // The previous row plus the decoder's history window and input chunk.
        (self.prev.len() + (4 << 15) + (1 << 16) + (8 << 10)) as u64
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

/// How an image is laid out in the file.
#[derive(Clone, Copy)]
struct Layout {
    width: u32,
    height: u32,
    channels: u8,
    format: SampleFormat,
}

impl Layout {
    fn new(width: u32, height: u32, channels: u8, format: SampleFormat) -> Result<Layout> {
        if format == SampleFormat::F32 {
            return Err(Error::unsupported("png: floating-point samples cannot be stored"));
        }
        if !(1..=4).contains(&channels) || width == 0 || height == 0 {
            return Err(Error::invalid_input("png: invalid image layout"));
        }
        Ok(Layout { width, height, channels, format })
    }

    fn bytes_per_sample(&self) -> usize {
        self.format.bytes() as usize
    }

    fn bpp(&self) -> usize {
        self.channels as usize * self.bytes_per_sample()
    }

    fn row_bytes(&self) -> usize {
        self.width as usize * self.bpp()
    }

    fn row_samples(&self) -> usize {
        self.width as usize * self.channels as usize
    }

    /// Signature, IHDR and the colour chunk.
    fn head(&self, options: &EncodeOptions) -> Vec<u8> {
        let depth = if self.format == SampleFormat::U16 { 16u8 } else { 8 };
        let color = match self.channels {
            1 => 0u8,
            2 => 4,
            3 => 2,
            _ => 6,
        };
        let mut out = SIGNATURE.to_vec();
        let mut ihdr = Vec::with_capacity(13);
        ihdr.extend_from_slice(&self.width.to_be_bytes());
        ihdr.extend_from_slice(&self.height.to_be_bytes());
        ihdr.extend_from_slice(&[depth, color, 0, 0, 0]);
        write_chunk(&mut out, b"IHDR", &ihdr);
        if let Some(icc) = &options.icc_profile {
            let mut body = b"ICC profile\0\0".to_vec();
            body.extend(zlib::zlib_compress(icc, zlib::Level::Best));
            write_chunk(&mut out, b"iCCP", &body);
        } else if options.srgb {
            write_chunk(&mut out, b"sRGB", &[0]); // perceptual rendering intent
        }
        out
    }
}

/// Row `y` of `samples`, serialised as stored (16-bit big-endian).
fn raw_row(samples: &Samples, y: usize, row_samples: usize) -> Vec<u8> {
    let r = y * row_samples..(y + 1) * row_samples;
    match samples {
        Samples::U8(v) => v[r].to_vec(),
        Samples::U16(v) => v[r].iter().flat_map(|s| s.to_be_bytes()).collect(),
        Samples::F32(_) => unreachable!("rejected by Layout"),
    }
}

/// Chooses a filter for one row and appends the filter byte and the
/// filtered row to `out`.
fn filter_row(
    cur: &[u8],
    prev: &[u8],
    bpp: usize,
    candidate: &mut [u8],
    best_row: &mut Vec<u8>,
    out: &mut Vec<u8>,
) {
    let mut best: (u64, u8) = (u64::MAX, 0);
    for kind in 0..5u8 {
        for i in 0..cur.len() {
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
            best_row.clear();
            best_row.extend_from_slice(candidate);
        }
    }
    out.push(best.1);
    out.extend_from_slice(best_row);
}

/// Filters rows `0..n`, given by `row(i)`. `above` is the unfiltered row
/// before row 0 (zeros at the top of the image). Bands of rows run in
/// parallel; each starts from the unfiltered row before it, so the result
/// equals sequential filtering.
fn filter_rows(
    n: usize,
    row_bytes: usize,
    bpp: usize,
    above: &[u8],
    row: impl Fn(usize) -> Vec<u8> + Sync,
) -> Vec<u8> {
    let band = |rows: std::ops::Range<usize>| -> Vec<u8> {
        let mut out = Vec::with_capacity(rows.len() * (row_bytes + 1));
        let mut prev = if rows.start == 0 { above.to_vec() } else { row(rows.start - 1) };
        let (mut candidate, mut best) = (vec![0u8; row_bytes], Vec::with_capacity(row_bytes));
        for y in rows {
            let cur = row(y);
            filter_row(&cur, &prev, bpp, &mut candidate, &mut best, &mut out);
            prev = cur;
        }
        out
    };
    let cores = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
    let per = n.div_ceil(cores.min(n / 16).max(1)).max(1);
    std::thread::scope(|sc| {
        let bands: Vec<_> =
            (0..n).step_by(per).map(|y0| sc.spawn(move || band(y0..(y0 + per).min(n)))).collect();
        bands.into_iter().flat_map(|b| b.join().expect("PNG filter worker panicked")).collect()
    })
}

/// Size of the IDAT chunks written.
const IDAT_CHUNK: usize = 1 << 20;

/// Encodes an 8- or 16-bit image as PNG.
pub fn encode(image: &ImageBuffer, options: &EncodeOptions) -> Result<Vec<u8>> {
    let l = Layout::new(image.width(), image.height(), image.channels(), image.format())?;
    let mut out = l.head(options);
    let (rs, rb) = (l.row_samples(), l.row_bytes());
    let filtered =
        filter_rows(l.height as usize, rb, l.bpp(), &vec![0u8; rb], |y| raw_row(image.samples(), y, rs));
    let compressed = zlib::zlib_compress(&filtered, options.level);
    for chunk in compressed.chunks(IDAT_CHUNK) {
        write_chunk(&mut out, b"IDAT", chunk);
    }
    write_chunk(&mut out, b"IEND", &[]);
    Ok(out)
}

/// Writes a PNG band by band. The file is byte-for-byte what [`encode`]
/// produces for the whole image; memory holds one band, the DEFLATE
/// window and less than one IDAT chunk of output.
pub struct PngSink<W: Write> {
    w: W,
    layout: Layout,
    zlib: zlib::ZlibWriter,
    above: Vec<u8>,
    pending: Vec<u8>,
    rows_done: u32,
}

impl<W: Write> PngSink<W> {
    /// Starts a file of the given layout and writes its header.
    pub fn new(
        mut w: W,
        width: u32,
        height: u32,
        channels: u8,
        format: SampleFormat,
        options: &EncodeOptions,
    ) -> Result<Self> {
        let layout = Layout::new(width, height, channels, format)?;
        w.write_all(&layout.head(options))?;
        Ok(PngSink {
            w,
            layout,
            zlib: zlib::ZlibWriter::new(options.level),
            above: vec![0; layout.row_bytes()],
            pending: Vec::new(),
            rows_done: 0,
        })
    }

    fn flush_chunks(&mut self, all: bool) -> Result<()> {
        let mut done = 0;
        while self.pending.len() - done >= IDAT_CHUNK || (all && done < self.pending.len()) {
            let n = IDAT_CHUNK.min(self.pending.len() - done);
            let mut chunk = Vec::with_capacity(n + 12);
            write_chunk(&mut chunk, b"IDAT", &self.pending[done..done + n]);
            self.w.write_all(&chunk)?;
            done += n;
        }
        self.pending.drain(..done);
        Ok(())
    }

    /// Appends a band of rows.
    pub fn write_band(&mut self, band: &ImageBuffer) -> Result<()> {
        let l = self.layout;
        let n = check_band(band, (l.width, l.height, l.channels, l.format), self.rows_done)? as usize;
        let rs = l.row_samples();
        let filtered =
            filter_rows(n, l.row_bytes(), l.bpp(), &self.above, |i| raw_row(band.samples(), i, rs));
        self.above = raw_row(band.samples(), n - 1, rs);
        self.zlib.write(&filtered);
        self.pending.extend(self.zlib.take_output());
        self.rows_done += n as u32;
        self.flush_chunks(false)
    }

    /// Completes the file and returns the writer.
    pub fn finish_file(mut self) -> Result<W> {
        if self.rows_done != self.layout.height {
            return Err(Error::invalid_input(format!(
                "png: {} of {} rows written",
                self.rows_done, self.layout.height
            )));
        }
        let zlib = std::mem::replace(&mut self.zlib, zlib::ZlibWriter::new(zlib::Level::Fast));
        self.pending.extend(zlib.finish());
        self.flush_chunks(true)?;
        let mut end = Vec::new();
        write_chunk(&mut end, b"IEND", &[]);
        self.w.write_all(&end)?;
        self.w.flush()?;
        Ok(self.w)
    }
}

impl<W: Write> RowSink for PngSink<W> {
    fn write_rows(&mut self, rows: &ImageBuffer) -> Result<()> {
        self.write_band(rows)
    }

    fn finish(self: Box<Self>) -> Result<()> {
        self.finish_file().map(|_| ())
    }
}

#[cfg(test)]
mod tests;

/// Test helpers shared with the stream tests.
#[cfg(test)]
pub(crate) mod tests_support {
    pub(crate) use super::tests::sample_files;
}
