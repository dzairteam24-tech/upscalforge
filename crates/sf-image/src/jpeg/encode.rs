//! Baseline JPEG encoder.
//!
//! Quantisation uses the example tables of ITU-T T.81 Annex K, scaled by a
//! quality factor. Huffman tables are **optimised per image**: a first
//! pass gathers symbol statistics, and the length-limited code builder
//! (shared with DEFLATE) produces the tables.

use sf_core::{Error, Result};

use super::dct::{ZIGZAG, fdct};
use crate::huffman::huffman_lengths;
use crate::image::{ImageBuffer, Samples};

/// Annex K example luminance quantisation table (natural order).
const LUMA_Q: [u16; 64] = [
    16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, 14, 17,
    22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92, 49, 64, 78,
    87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
];
/// Annex K example chrominance quantisation table (natural order).
const CHROMA_Q: [u16; 64] = [
    17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99, 47, 66,
    99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
];

/// Chroma subsampling.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Subsampling {
    /// Full-resolution chroma.
    S444,
    /// Chroma halved in both directions.
    S420,
}

/// JPEG encoder options.
#[derive(Debug, Clone)]
pub struct EncodeOptions {
    /// Quality 1–100.
    pub quality: u8,
    /// Chroma subsampling for colour images.
    pub subsampling: Subsampling,
    /// ICC profile to embed (APP2 segments).
    pub icc_profile: Option<Vec<u8>>,
}

impl Default for EncodeOptions {
    fn default() -> Self {
        EncodeOptions { quality: 92, subsampling: Subsampling::S444, icc_profile: None }
    }
}

fn scaled_table(base: &[u16; 64], quality: u8) -> [u16; 64] {
    let q = u32::from(quality.clamp(1, 100));
    let s = if q < 50 { 5000 / q } else { 200 - 2 * q };
    base.map(|b| ((u32::from(b) * s + 50) / 100).clamp(1, 255) as u16)
}

/// Estimates the quality setting (1–100) that would produce `table` from
/// the Annex K luminance table under the usual scaling rule. The table is in
/// zig-zag order, as stored in files. Returns the best fit and its mean
/// absolute error per entry; encoders using other base tables fit poorly
/// (large error), which the caller should treat as "unknown quality".
pub fn estimate_quality(table: &[u16]) -> Option<(u8, f64)> {
    if table.len() != 64 {
        return None;
    }
    (1..=100u8)
        .map(|q| {
            let t = scaled_table(&LUMA_Q, q);
            let err: f64 = ZIGZAG
                .iter()
                .enumerate()
                .map(|(k, &n)| (f64::from(t[n]) - f64::from(table[k])).abs())
                .sum::<f64>()
                / 64.0;
            (q, err)
        })
        .min_by(|a, b| a.1.total_cmp(&b.1))
}

/// Magnitude category (number of bits) of a coefficient value.
fn category(v: i32) -> u32 {
    32 - v.unsigned_abs().leading_zeros()
}

/// The bits written after a category code: v for positive values, v−1 in
/// the low bits for negative values.
fn magnitude_bits(v: i32, cat: u32) -> u32 {
    if v >= 0 { v as u32 } else { (v - 1) as u32 & ((1 << cat) - 1) }
}

/// Quantised coefficient blocks for one component, in zig-zag order.
struct Plane {
    blocks: Vec<[i32; 64]>,
    table: usize,
}

struct Writer {
    out: Vec<u8>,
    acc: u32,
    n: u32,
}

impl Writer {
    fn put(&mut self, value: u32, bits: u32) {
        for i in (0..bits).rev() {
            self.acc = (self.acc << 1) | ((value >> i) & 1);
            self.n += 1;
            if self.n == 8 {
                let b = self.acc as u8;
                self.out.push(b);
                if b == 0xFF {
                    self.out.push(0);
                }
                self.acc = 0;
                self.n = 0;
            }
        }
    }

    fn flush(&mut self) {
        if self.n > 0 {
            let pad = 8 - self.n;
            self.put((1 << pad) - 1, pad);
        }
    }
}

/// Symbol statistics → (DHT counts, symbols, code per symbol, length per symbol).
struct Table {
    counts: [u8; 16],
    symbols: Vec<u8>,
    code: [u32; 256],
    len: [u8; 256],
}

fn build_table(freq: &[u32; 256]) -> Table {
    // Add a reserved symbol (index 256) with the smallest frequency, and
    // give it the longest code: it then takes the all-ones code, which JPEG
    // forbids, and is simply not transmitted.
    let mut f: Vec<u32> = freq.to_vec();
    f.push(1);
    let mut lens = huffman_lengths(&f, 16);
    let max = *lens.iter().max().expect("non-empty");
    if lens[256] != max {
        let j = (0..256).rev().find(|&j| lens[j] == max).expect("a symbol has the maximum length");
        lens.swap(j, 256);
    }
    let mut counts = [0u8; 16];
    let mut order: Vec<usize> = (0..256).filter(|&s| lens[s] > 0).collect();
    order.sort_by_key(|&s| (lens[s], s));
    for &s in &order {
        counts[lens[s] as usize - 1] += 1;
    }
    let mut code = [0u32; 256];
    let mut len = [0u8; 256];
    let mut c = 0u32;
    let mut prev_len = 0u8;
    for &s in &order {
        c <<= lens[s] - prev_len;
        prev_len = lens[s];
        code[s] = c;
        len[s] = lens[s];
        c += 1;
    }
    Table { counts, symbols: order.iter().map(|&s| s as u8).collect(), code, len }
}

/// Visits every symbol of a component's blocks in coding order.
fn for_each_symbol(blocks: &[[i32; 64]], mut dc: impl FnMut(i32), mut ac: impl FnMut(u8, i32)) {
    let mut pred = 0;
    for b in blocks {
        dc(b[0] - pred);
        pred = b[0];
        let mut run = 0u8;
        for &v in &b[1..] {
            if v == 0 {
                run += 1;
                continue;
            }
            while run >= 16 {
                ac(0xF0, 0);
                run -= 16;
            }
            ac((run << 4) | category(v) as u8, v);
            run = 0;
        }
        if run > 0 {
            ac(0x00, 0);
        }
    }
}

/// Encodes an 8-bit grey or RGB image as baseline JPEG. Images with alpha
/// must be flattened by the caller (JPEG cannot store alpha).
pub fn encode(image: &ImageBuffer, options: &EncodeOptions) -> Result<Vec<u8>> {
    let samples = match image.samples() {
        Samples::U8(v) => v,
        _ => return Err(Error::unsupported("jpeg: only 8-bit samples can be encoded")),
    };
    let nc = match image.channels() {
        1 => 1usize,
        3 => 3,
        _ => return Err(Error::unsupported("jpeg: alpha channels cannot be stored; flatten first")),
    };
    let (w, h) = (image.width() as usize, image.height() as usize);
    if w > 65_535 || h > 65_535 {
        return Err(Error::limit_exceeded(format!("jpeg: {w}x{h} exceeds the 65535-pixel format limit")));
    }
    let sub = nc == 3 && options.subsampling == Subsampling::S420;
    let tables = [scaled_table(&LUMA_Q, options.quality), scaled_table(&CHROMA_Q, options.quality)];

    // Colour conversion to Y, Cb, Cr planes (JFIF full range).
    let mut planes: Vec<Vec<f32>> = vec![vec![0.0; w * h]; nc];
    for i in 0..w * h {
        if nc == 1 {
            planes[0][i] = f32::from(samples[i]);
        } else {
            let (r, g, b) =
                (f32::from(samples[3 * i]), f32::from(samples[3 * i + 1]), f32::from(samples[3 * i + 2]));
            planes[0][i] = 0.299 * r + 0.587 * g + 0.114 * b;
            planes[1][i] = -0.168_736 * r - 0.331_264 * g + 0.5 * b + 128.0;
            planes[2][i] = 0.5 * r - 0.418_688 * g - 0.081_312 * b + 128.0;
        }
    }
    let (mcu_w, mcu_h) = if sub { (16, 16) } else { (8, 8) };
    let (mcux, mcuy) = (w.div_ceil(mcu_w), h.div_ceil(mcu_h));

    // Transform and quantise, emitting blocks in interleaved MCU order.
    let mut coded: Vec<Plane> =
        (0..nc).map(|c| Plane { blocks: Vec::new(), table: usize::from(c > 0) }).collect();
    let fetch = |plane: &[f32], x: usize, y: usize| plane[y.min(h - 1) * w + x.min(w - 1)];
    let mut block = [0f32; 64];
    let mut freq = [0f32; 64];
    for my in 0..mcuy {
        for mx in 0..mcux {
            for (c, plane) in planes.iter().enumerate() {
                let (bh, bv, step) = if sub && c == 0 {
                    (2, 2, 1)
                } else if sub {
                    (1, 1, 2)
                } else {
                    (1, 1, 1)
                };
                for by in 0..bv {
                    for bx in 0..bh {
                        for y in 0..8 {
                            for x in 0..8 {
                                let px = (mx * mcu_w) + (bx * 8 + x) * step;
                                let py = (my * mcu_h) + (by * 8 + y) * step;
                                block[y * 8 + x] = if step == 1 {
                                    fetch(plane, px, py)
                                } else {
                                    // 2×2 box average for subsampled chroma.
                                    (fetch(plane, px, py)
                                        + fetch(plane, px + 1, py)
                                        + fetch(plane, px, py + 1)
                                        + fetch(plane, px + 1, py + 1))
                                        / 4.0
                                } - 128.0;
                            }
                        }
                        fdct(&block, &mut freq);
                        let q = &tables[coded[c].table];
                        let mut zz = [0i32; 64];
                        for k in 0..64 {
                            zz[k] = (freq[ZIGZAG[k]] / f32::from(q[ZIGZAG[k]])).round() as i32;
                        }
                        coded[c].blocks.push(zz);
                    }
                }
            }
        }
    }

    // Gather statistics per table class (luma / chroma).
    let mut dc_freq = [[0u32; 256]; 2];
    let mut ac_freq = [[0u32; 256]; 2];
    for p in &coded {
        let t = p.table;
        for_each_symbol(
            &p.blocks,
            |d| dc_freq[t][category(d) as usize] += 1,
            |s, _| ac_freq[t][s as usize] += 1,
        );
    }
    let ntab = if nc == 3 { 2 } else { 1 };
    let dc_tab: Vec<Table> = (0..ntab).map(|t| build_table(&dc_freq[t])).collect();
    let ac_tab: Vec<Table> = (0..ntab).map(|t| build_table(&ac_freq[t])).collect();

    // Headers.
    let mut out = vec![0xFF, 0xD8];
    let segment = |out: &mut Vec<u8>, marker: u8, body: &[u8]| {
        out.extend([0xFF, marker]);
        out.extend(((body.len() + 2) as u16).to_be_bytes());
        out.extend_from_slice(body);
    };
    segment(&mut out, 0xE0, b"JFIF\0\x01\x02\0\0\x01\0\x01\0\0");
    if let Some(icc) = &options.icc_profile {
        let chunks: Vec<&[u8]> = icc.chunks(65_519).collect();
        if chunks.len() > 255 {
            return Err(Error::limit_exceeded("jpeg: ICC profile too large to embed"));
        }
        for (i, chunk) in chunks.iter().enumerate() {
            let mut body = b"ICC_PROFILE\0".to_vec();
            body.extend([(i + 1) as u8, chunks.len() as u8]);
            body.extend_from_slice(chunk);
            segment(&mut out, 0xE2, &body);
        }
    }
    for (id, t) in tables.iter().enumerate().take(ntab) {
        let mut body = vec![id as u8];
        body.extend(ZIGZAG.iter().map(|&i| t[i] as u8));
        segment(&mut out, 0xDB, &body);
    }
    let mut sof = vec![8];
    sof.extend((h as u16).to_be_bytes());
    sof.extend((w as u16).to_be_bytes());
    sof.push(nc as u8);
    for c in 0..nc {
        let sampling = if sub && c == 0 { 0x22 } else { 0x11 };
        sof.extend([c as u8 + 1, sampling, u8::from(c > 0)]);
    }
    segment(&mut out, 0xC0, &sof);
    for (class, tabs) in [(0u8, &dc_tab), (1u8, &ac_tab)] {
        for (id, t) in tabs.iter().enumerate() {
            let mut body = vec![(class << 4) | id as u8];
            body.extend(t.counts);
            body.extend(&t.symbols);
            segment(&mut out, 0xC4, &body);
        }
    }
    let mut sos = vec![nc as u8];
    for c in 0..nc {
        let t = u8::from(c > 0);
        sos.extend([c as u8 + 1, (t << 4) | t]);
    }
    sos.extend([0, 63, 0]);
    segment(&mut out, 0xDA, &sos);

    // Entropy-coded data, interleaved per MCU.
    let mut wr = Writer { out, acc: 0, n: 0 };
    let per_mcu: Vec<usize> = (0..nc).map(|c| if sub && c == 0 { 4 } else { 1 }).collect();
    let mut preds = vec![0i32; nc];
    for m in 0..mcux * mcuy {
        for c in 0..nc {
            let t = coded[c].table;
            for k in 0..per_mcu[c] {
                let b = &coded[c].blocks[m * per_mcu[c] + k];
                let diff = b[0] - preds[c];
                preds[c] = b[0];
                let cat = category(diff);
                wr.put(dc_tab[t].code[cat as usize], u32::from(dc_tab[t].len[cat as usize]));
                wr.put(magnitude_bits(diff, cat), cat);
                let mut run = 0u8;
                for &v in &b[1..] {
                    if v == 0 {
                        run += 1;
                        continue;
                    }
                    while run >= 16 {
                        wr.put(ac_tab[t].code[0xF0], u32::from(ac_tab[t].len[0xF0]));
                        run -= 16;
                    }
                    let cat = category(v);
                    let sym = ((run << 4) | cat as u8) as usize;
                    wr.put(ac_tab[t].code[sym], u32::from(ac_tab[t].len[sym]));
                    wr.put(magnitude_bits(v, cat), cat);
                    run = 0;
                }
                if run > 0 {
                    wr.put(ac_tab[t].code[0], u32::from(ac_tab[t].len[0]));
                }
            }
        }
    }
    wr.flush();
    let mut out = wr.out;
    out.extend([0xFF, 0xD9]);
    Ok(out)
}
