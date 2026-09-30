//! VP8 key-frame decoder for lossy WebP, written from RFC 6386.
//!
//! Only what a still WebP image needs: key frames, intra prediction,
//! residue decoding, both loop filters. The output is the decoded Y'CbCr
//! 4:2:0 frame; colour conversion happens in the container module.
//!
//! Deviations from the RFC's prose, where the RFC contradicts itself:
//! - `segment_feature_mode`: 1 means absolute values, 0 deltas (annex
//!   §19.2 and the reference decoder; §9.3 states the opposite);
//! - the token pseudocode in §13.3 swaps plane types 0/1 and never clears
//!   its "previous coefficient was zero" flag; the prose is followed.

use sf_core::{Error, Result};

use super::vp8_tables::{AC_Q, COEFF_UPDATE_PROB, DC_Q, DEFAULT_COEFF_PROB, KF_BMODE_PROB};

fn bad(what: impl std::fmt::Display) -> Error {
    Error::invalid_input(format!("webp lossy: {what}"))
}

// ------------------------------------------------------------ bool decoder

/// The boolean entropy decoder of RFC 6386 §7.
struct BoolDecoder<'a> {
    data: &'a [u8],
    pos: usize,
    /// Pending input bits; the current 8-bit window is `value >> bits`.
    value: u64,
    bits: i32,
    range: u32,
    /// Set once the decoder needed bytes beyond the end of its partition.
    overrun: bool,
}

impl<'a> BoolDecoder<'a> {
    /// Input is loaded on first use, so a partition that is never read
    /// (for example an empty one) is never reported as truncated.
    fn new(data: &'a [u8]) -> Self {
        BoolDecoder { data, pos: 0, value: 0, bits: -8, range: 255, overrun: false }
    }

    fn refill(&mut self) {
        while self.bits < 0 {
            let byte = match self.data.get(self.pos) {
                Some(&b) => {
                    self.pos += 1;
                    b
                }
                None => {
                    self.overrun = true;
                    0
                }
            };
            self.value = (self.value << 8) | u64::from(byte);
            self.bits += 8;
        }
    }

    /// Reads a bool whose probability of being 0 is `prob / 256`.
    fn read(&mut self, prob: u8) -> bool {
        if self.bits < 0 {
            self.refill();
        }
        let split = 1 + (((self.range - 1) * u32::from(prob)) >> 8);
        let window = (self.value >> self.bits) as u32;
        let bit = window >= split;
        if bit {
            self.range -= split;
            self.value -= u64::from(split) << self.bits;
        } else {
            self.range = split;
        }
        // Renormalise so that 128 <= range <= 255.
        let shift = self.range.leading_zeros() as i32 - 24;
        self.range <<= shift;
        self.bits -= shift;
        bit
    }

    fn flag(&mut self) -> bool {
        self.read(128)
    }

    /// Unsigned `n`-bit literal, most significant bit first.
    fn literal(&mut self, n: u32) -> u32 {
        (0..n).fold(0, |v, _| (v << 1) | u32::from(self.flag()))
    }

    /// Magnitude of `n` bits followed by a sign flag (1 = negative).
    fn signed(&mut self, n: u32) -> i32 {
        let m = self.literal(n) as i32;
        if self.flag() { -m } else { m }
    }

    /// Optional signed value: a presence flag, then [`Self::signed`].
    fn maybe_signed(&mut self, n: u32) -> i32 {
        if self.flag() { self.signed(n) } else { 0 }
    }

    /// Reads a tree-coded value (RFC 6386 §8.1 tree layout: positive
    /// entries index the next node pair, others are negated leaves).
    fn tree(&mut self, tree: &[i8], probs: &[u8]) -> u8 {
        let mut i = 0usize;
        loop {
            let next = tree[i + usize::from(self.read(probs[i >> 1]))];
            if next <= 0 {
                return (-next) as u8;
            }
            i = next as usize;
        }
    }
}

// ------------------------------------------------------------ modes

// 16x16 luma and chroma modes.
const DC_PRED: u8 = 0;
const V_PRED: u8 = 1;
const H_PRED: u8 = 2;
const TM_PRED: u8 = 3;
const B_PRED: u8 = 4;

// Subblock modes, in the order that indexes `KF_BMODE_PROB`.
const B_DC: u8 = 0;
const B_TM: u8 = 1;
const B_VE: u8 = 2;
const B_HE: u8 = 3;
const B_LD: u8 = 4;
const B_RD: u8 = 5;
const B_VR: u8 = 6;
const B_VL: u8 = 7;
const B_HD: u8 = 8;
const B_HU: u8 = 9;

const KF_YMODE_TREE: [i8; 8] =
    [-(B_PRED as i8), 2, 4, 6, -(DC_PRED as i8), -(V_PRED as i8), -(H_PRED as i8), -(TM_PRED as i8)];
const KF_YMODE_PROB: [u8; 4] = [145, 156, 163, 128];
const UV_MODE_TREE: [i8; 6] = [-(DC_PRED as i8), 2, -(V_PRED as i8), 4, -(H_PRED as i8), -(TM_PRED as i8)];
const KF_UV_MODE_PROB: [u8; 3] = [142, 114, 183];
const BMODE_TREE: [i8; 18] = [
    -(B_DC as i8),
    2,
    -(B_TM as i8),
    4,
    -(B_VE as i8),
    6,
    8,
    12,
    -(B_HE as i8),
    10,
    -(B_RD as i8),
    -(B_VR as i8),
    -(B_LD as i8),
    14,
    -(B_VL as i8),
    16,
    -(B_HD as i8),
    -(B_HU as i8),
];
const SEGMENT_TREE: [i8; 6] = [2, 4, 0, -1, -2, -3];

// ------------------------------------------------------------ residue

/// Coefficient band of each scan position.
const BANDS: [usize; 17] = [0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0];
/// Scan position → raster index within the 4x4 block.
const ZIGZAG: [usize; 16] = [0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15];
/// Extra-bit probabilities of token categories 1–6 and their base values.
const CATEGORIES: [(u32, &[u8]); 6] = [
    (5, &[159]),
    (7, &[165, 145]),
    (11, &[173, 148, 140]),
    (19, &[176, 155, 140, 135]),
    (35, &[180, 157, 141, 134, 130]),
    (67, &[254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129]),
];

// Plane types indexing the coefficient probabilities (RFC 6386 §13.3).
const PLANE_Y_AFTER_Y2: usize = 0;
const PLANE_Y2: usize = 1;
const PLANE_CHROMA: usize = 2;
const PLANE_Y_WITH_DC: usize = 3;

type CoeffProbs = [[[[u8; 11]; 3]; 8]; 4];

/// Reads one block's tokens into `out` (raster order, dequantised).
/// Returns true unless the first token was end-of-block; that is the
/// "has coefficients" context the neighbouring blocks see.
fn read_block(
    d: &mut BoolDecoder<'_>,
    probs: &[[[u8; 11]; 3]; 8],
    first: usize,
    mut ctx: usize,
    (dc, ac): (i32, i32),
    out: &mut [i32; 16],
) -> bool {
    let mut i = first;
    let mut after_zero = false;
    while i < 16 {
        let p = &probs[BANDS[i]][ctx];
        // End-of-block cannot follow a zero, so that branch is not coded.
        if !after_zero && !d.read(p[0]) {
            break;
        }
        if !d.read(p[1]) {
            ctx = 0;
            after_zero = true;
            i += 1;
            continue;
        }
        let v: u32 = if !d.read(p[2]) {
            1
        } else if !d.read(p[3]) {
            if !d.read(p[4]) { 2 } else { 3 + u32::from(d.read(p[5])) }
        } else {
            let cat = if !d.read(p[6]) {
                usize::from(d.read(p[7]))
            } else if !d.read(p[8]) {
                2 + usize::from(d.read(p[9]))
            } else {
                4 + usize::from(d.read(p[10]))
            };
            let (base, extra) = CATEGORIES[cat];
            base + extra.iter().fold(0, |v, &q| (v << 1) | u32::from(d.read(q)))
        };
        let signed = if d.flag() { -(v as i32) } else { v as i32 };
        out[ZIGZAG[i]] = signed * if i == 0 { dc } else { ac };
        ctx = if v == 1 { 1 } else { 2 };
        after_zero = false;
        i += 1;
    }
    i > first
}

/// Inverse Walsh–Hadamard transform of the Y2 block (RFC 6386 §14.3).
fn inverse_wht(input: &[i32; 16]) -> [i32; 16] {
    let mut t = [0i32; 16];
    for c in 0..4 {
        let (i0, i1, i2, i3) = (input[c], input[4 + c], input[8 + c], input[12 + c]);
        let (a, b) = (i0 + i3, i1 + i2);
        let (cc, dd) = (i1 - i2, i0 - i3);
        t[c] = a + b;
        t[4 + c] = cc + dd;
        t[8 + c] = a - b;
        t[12 + c] = dd - cc;
    }
    let mut out = [0i32; 16];
    for r in 0..4 {
        let row = &t[r * 4..r * 4 + 4];
        let (a, b) = (row[0] + row[3], row[1] + row[2]);
        let (cc, dd) = (row[1] - row[2], row[0] - row[3]);
        out[r * 4] = (a + b + 3) >> 3;
        out[r * 4 + 1] = (cc + dd + 3) >> 3;
        out[r * 4 + 2] = (a - b + 3) >> 3;
        out[r * 4 + 3] = (dd - cc + 3) >> 3;
    }
    out
}

/// Inverse DCT (RFC 6386 §14.4) added to the prediction at `buf[at..]`.
fn add_inverse_dct(coeffs: &[i32; 16], buf: &mut [u8], at: usize, stride: usize) {
    // x·√2·cos(π/8) and x·√2·sin(π/8) in 16-bit fixed point.
    let mul_c = |x: i32| x + ((x * 20091) >> 16);
    let mul_s = |x: i32| (x * 35468) >> 16;
    let mut t = [0i32; 16];
    for c in 0..4 {
        let (i0, i1, i2, i3) = (coeffs[c], coeffs[4 + c], coeffs[8 + c], coeffs[12 + c]);
        let (a, b) = (i0 + i2, i0 - i2);
        let cc = mul_s(i1) - mul_c(i3);
        let dd = mul_c(i1) + mul_s(i3);
        t[c] = a + dd;
        t[12 + c] = a - dd;
        t[4 + c] = b + cc;
        t[8 + c] = b - cc;
    }
    for r in 0..4 {
        let row = &t[r * 4..r * 4 + 4];
        let (a, b) = (row[0] + row[2], row[0] - row[2]);
        let cc = mul_s(row[1]) - mul_c(row[3]);
        let dd = mul_c(row[1]) + mul_s(row[3]);
        let res = [(a + dd + 4) >> 3, (b + cc + 4) >> 3, (b - cc + 4) >> 3, (a - dd + 4) >> 3];
        for (k, v) in res.iter().enumerate() {
            let p = &mut buf[at + r * stride + k];
            *p = (i32::from(*p) + v).clamp(0, 255) as u8;
        }
    }
}

// ------------------------------------------------------------ prediction

fn avg2(a: u8, b: u8) -> u8 {
    ((u16::from(a) + u16::from(b) + 1) >> 1) as u8
}

fn avg3(a: u8, b: u8, c: u8) -> u8 {
    ((u16::from(a) + 2 * u16::from(b) + u16::from(c) + 2) >> 2) as u8
}

/// Predicts a `size`×`size` block with a whole-block mode. The block's
/// top-left pixel is at `ws[at]`; the row above and the column to the
/// left are already filled in (with 127/129 outside the frame).
fn predict_block(ws: &mut [u8], at: usize, stride: usize, size: usize, mode: u8, above: bool, left: bool) {
    let top: Vec<u8> = ws[at - stride..at - stride + size].to_vec();
    let lft: Vec<u8> = (0..size).map(|r| ws[at + r * stride - 1]).collect();
    let corner = ws[at - stride - 1];
    let shift = size.trailing_zeros();
    for r in 0..size {
        for c in 0..size {
            ws[at + r * stride + c] = match mode {
                V_PRED => top[c],
                H_PRED => lft[r],
                TM_PRED => (i32::from(lft[r]) + i32::from(top[c]) - i32::from(corner)).clamp(0, 255) as u8,
                _ => {
                    let sum = |v: &[u8]| v.iter().map(|&x| u32::from(x)).sum::<u32>();
                    match (above, left) {
                        (true, true) => ((sum(&top) + sum(&lft) + (1 << shift)) >> (shift + 1)) as u8,
                        (true, false) => ((sum(&top) + (1 << (shift - 1))) >> shift) as u8,
                        (false, true) => ((sum(&lft) + (1 << (shift - 1))) >> shift) as u8,
                        (false, false) => 128,
                    }
                }
            };
        }
    }
}

/// Predicts a 4x4 luma subblock (RFC 6386 §12.3) whose top-left pixel is
/// at `ws[at]`. `a[0]` is the corner pixel, `a[1..9]` the row above
/// including the four pixels above-right; `l` is the left column.
fn predict_subblock(ws: &mut [u8], at: usize, stride: usize, mode: u8) {
    let a: [u8; 9] = std::array::from_fn(|i| ws[at - stride - 1 + i]);
    let l: [u8; 4] = std::array::from_fn(|r| ws[at + r * stride - 1]);
    let p = a[0];
    let top = |c: usize| a[1 + c]; // c in 0..8
    // Edge from bottom-left to top-right: L3 L2 L1 L0 P A0 A1 A2 A3.
    let e: [u8; 9] = [l[3], l[2], l[1], l[0], p, a[1], a[2], a[3], a[4]];
    let mut b = [[0u8; 4]; 4];
    match mode {
        B_DC => {
            let s: u32 = (0..4).map(|i| u32::from(top(i)) + u32::from(l[i])).sum();
            b = [[((s + 4) >> 3) as u8; 4]; 4];
        }
        B_TM => {
            for (r, row) in b.iter_mut().enumerate() {
                for (c, v) in row.iter_mut().enumerate() {
                    *v = (i32::from(l[r]) + i32::from(top(c)) - i32::from(p)).clamp(0, 255) as u8;
                }
            }
        }
        B_VE => {
            let row: [u8; 4] =
                std::array::from_fn(|c| avg3(if c == 0 { p } else { top(c - 1) }, top(c), top(c + 1)));
            b = [row; 4];
        }
        B_HE => {
            let left_ext = [p, l[0], l[1], l[2], l[3], l[3]];
            for (r, row) in b.iter_mut().enumerate() {
                *row = [avg3(left_ext[r], left_ext[r + 1], left_ext[r + 2]); 4];
            }
        }
        B_LD => {
            // Down-left diagonals: all pixels with equal r + c share a value.
            let t = |i: usize| top(i.min(7));
            for (r, row) in b.iter_mut().enumerate() {
                for (c, v) in row.iter_mut().enumerate() {
                    let k = r + c;
                    *v = avg3(t(k), t(k + 1), t(k + 2));
                }
            }
        }
        B_RD => {
            // Down-right diagonals along the edge `e`: equal c − r.
            for (r, row) in b.iter_mut().enumerate() {
                for (c, v) in row.iter_mut().enumerate() {
                    let k = 4 + c - r;
                    *v = avg3(e[k - 1], e[k], e[k + 1]);
                }
            }
        }
        B_VR => {
            for c in 0..4 {
                b[0][c] = avg2(e[4 + c], e[5 + c]);
                b[1][c] = avg3(e[3 + c], e[4 + c], e[5 + c]);
            }
            b[2][0] = avg3(e[2], e[3], e[4]);
            b[3][0] = avg3(e[1], e[2], e[3]);
            for c in 1..4 {
                b[2][c] = b[0][c - 1];
                b[3][c] = b[1][c - 1];
            }
        }
        B_VL => {
            // Rows 2 and 3 repeat rows 0 and 1 shifted left by one, except
            // for their last pixel.
            let r0: [u8; 4] = std::array::from_fn(|c| avg2(top(c), top(c + 1)));
            let r1: [u8; 4] = std::array::from_fn(|c| avg3(top(c), top(c + 1), top(c + 2)));
            b = [
                r0,
                r1,
                [r0[1], r0[2], r0[3], avg3(top(4), top(5), top(6))],
                [r1[1], r1[2], r1[3], avg3(top(5), top(6), top(7))],
            ];
        }
        B_HD => {
            for r in 0..4 {
                b[r][0] = avg2(e[3 - r], e[4 - r]);
                b[r][1] = avg3(e[3 - r], e[4 - r], e[5 - r]);
            }
            b[0][2] = avg3(e[4], e[5], e[6]);
            b[0][3] = avg3(e[5], e[6], e[7]);
            for r in 1..4 {
                b[r][2] = b[r - 1][0];
                b[r][3] = b[r - 1][1];
            }
        }
        _ => {
            // B_HU: z = c + 2r walks up the left column in half steps.
            let hu = |z: usize| match z {
                0 => avg2(l[0], l[1]),
                1 => avg3(l[0], l[1], l[2]),
                2 => avg2(l[1], l[2]),
                3 => avg3(l[1], l[2], l[3]),
                4 => avg2(l[2], l[3]),
                5 => avg3(l[2], l[3], l[3]),
                _ => l[3],
            };
            for (r, row) in b.iter_mut().enumerate() {
                for (c, v) in row.iter_mut().enumerate() {
                    *v = hu(c + 2 * r);
                }
            }
        }
    }
    for (r, row) in b.iter().enumerate() {
        ws[at + r * stride..at + r * stride + 4].copy_from_slice(row);
    }
}

// ------------------------------------------------------------ frame

/// A decoded frame: planes cover whole macroblocks.
pub(super) struct Frame {
    pub(super) width: usize,
    pub(super) height: usize,
    pub(super) y: Vec<u8>,
    pub(super) u: Vec<u8>,
    pub(super) v: Vec<u8>,
    pub(super) y_stride: usize,
    pub(super) uv_stride: usize,
}

struct Segmentation {
    enabled: bool,
    update_map: bool,
    absolute: bool,
    quant: [i32; 4],
    filter: [i32; 4],
    probs: [u8; 3],
}

#[derive(Clone, Copy)]
struct Dequant {
    y1: (i32, i32),
    y2: (i32, i32),
    uv: (i32, i32),
}

/// Per-macroblock information the loop filter needs.
#[derive(Clone, Copy, Default)]
struct MbInfo {
    segment: usize,
    bpred: bool,
    has_coeffs: bool,
}

/// Non-zero contexts of one macroblock edge: 4 Y, 2 U, 2 V, Y2.
#[derive(Clone, Copy, Default)]
struct Nz {
    y: [bool; 4],
    u: [bool; 2],
    v: [bool; 2],
    y2: bool,
}

/// Parses the 10-byte key-frame header: (width, height, first partition size).
pub(super) fn header(data: &[u8]) -> Result<(u32, u32, usize)> {
    if data.len() < 10 {
        return Err(bad("truncated frame header"));
    }
    let tag = u32::from(data[0]) | u32::from(data[1]) << 8 | u32::from(data[2]) << 16;
    if tag & 1 != 0 {
        return Err(bad("not a key frame"));
    }
    if (tag >> 1) & 7 > 3 {
        return Err(bad("unknown VP8 version"));
    }
    if data[3..6] != [0x9D, 0x01, 0x2A] {
        return Err(bad("missing start code"));
    }
    let w = u32::from(u16::from_le_bytes([data[6], data[7]]) & 0x3FFF);
    let h = u32::from(u16::from_le_bytes([data[8], data[9]]) & 0x3FFF);
    if w == 0 || h == 0 {
        return Err(bad("zero dimension"));
    }
    Ok((w, h, (tag >> 5) as usize))
}

/// Decodes a VP8 key frame (the payload of a `VP8 ` chunk).
pub(super) fn decode(data: &[u8]) -> Result<Frame> {
    let (width, height, part0_len) = header(data)?;
    let part0 = data.get(10..10 + part0_len).ok_or_else(|| bad("first partition exceeds the data"))?;
    let mut d = BoolDecoder::new(part0);
    let _colour_space = d.flag();
    let _clamping = d.flag(); // results are always clamped, which is harmless

    let mut seg = Segmentation {
        enabled: d.flag(),
        update_map: false,
        absolute: false,
        quant: [0; 4],
        filter: [0; 4],
        probs: [255; 3],
    };
    if seg.enabled {
        seg.update_map = d.flag();
        if d.flag() {
            seg.absolute = d.flag();
            for q in &mut seg.quant {
                *q = d.maybe_signed(7);
            }
            for f in &mut seg.filter {
                *f = d.maybe_signed(6);
            }
        }
        if seg.update_map {
            for p in &mut seg.probs {
                *p = if d.flag() { d.literal(8) as u8 } else { 255 };
            }
        }
    }
    let simple_filter = d.flag();
    let filter_level = d.literal(6) as i32;
    let sharpness = d.literal(3) as i32;
    let mut ref_delta_intra = 0;
    let mut mode_delta_bpred = 0;
    let adjust = d.flag();
    if adjust && d.flag() {
        // Reference-frame deltas (only the intra one applies to key frames),
        // then mode deltas (only B_PRED's applies).
        for i in 0..4 {
            let v = d.maybe_signed(6);
            if i == 0 {
                ref_delta_intra = v;
            }
        }
        for i in 0..4 {
            let v = d.maybe_signed(6);
            if i == 0 {
                mode_delta_bpred = v;
            }
        }
    }
    let partitions = 1usize << d.literal(2);
    let base_q = d.literal(7) as i32;
    let deltas: [i32; 5] = std::array::from_fn(|_| d.maybe_signed(4));
    let [y1dc, y2dc, y2ac, uvdc, uvac] = deltas;
    let _refresh_entropy = d.flag();
    let mut coeff_probs: CoeffProbs = DEFAULT_COEFF_PROB;
    for (i, plane) in coeff_probs.iter_mut().enumerate() {
        for (j, band) in plane.iter_mut().enumerate() {
            for (k, ctx) in band.iter_mut().enumerate() {
                for (t, p) in ctx.iter_mut().enumerate() {
                    if d.read(COEFF_UPDATE_PROB[i][j][k][t]) {
                        *p = d.literal(8) as u8;
                    }
                }
            }
        }
    }
    let skip_prob = if d.flag() { Some(d.literal(8) as u8) } else { None };

    // Token partitions follow the first partition.
    let rest = &data[10 + part0_len..];
    let sizes_len = 3 * (partitions - 1);
    if rest.len() < sizes_len {
        return Err(bad("partition table exceeds the data"));
    }
    let mut parts = Vec::with_capacity(partitions);
    let mut off = sizes_len;
    for p in 0..partitions {
        let len = if p + 1 < partitions {
            let s = &rest[3 * p..3 * p + 3];
            usize::from(s[0]) | usize::from(s[1]) << 8 | usize::from(s[2]) << 16
        } else {
            rest.len() - off.min(rest.len())
        };
        let part = rest.get(off..off + len).ok_or_else(|| bad("partition exceeds the data"))?;
        parts.push(BoolDecoder::new(part));
        off += len;
    }

    // Dequantisation factors per segment (RFC 6386 §9.6, §14.1).
    let dq = |q: i32| {
        let idx = |d: i32| (q + d).clamp(0, 127) as usize;
        Dequant {
            y1: (DC_Q[idx(y1dc)], AC_Q[idx(0)]),
            y2: (DC_Q[idx(y2dc)] * 2, (AC_Q[idx(y2ac)] * 155 / 100).max(8)),
            uv: (DC_Q[idx(uvdc)].min(132), AC_Q[idx(uvac)]),
        }
    };
    let seg_dq: [Dequant; 4] = std::array::from_fn(|s| {
        let q = if !seg.enabled {
            base_q
        } else if seg.absolute {
            seg.quant[s]
        } else {
            base_q + seg.quant[s]
        };
        dq(q)
    });

    let (mbw, mbh) = ((width as usize).div_ceil(16), (height as usize).div_ceil(16));
    let (ys, uvs) = (mbw * 16, mbw * 8);
    let mut frame = Frame {
        width: width as usize,
        height: height as usize,
        y: vec![0; ys * mbh * 16],
        u: vec![0; uvs * mbh * 8],
        v: vec![0; uvs * mbh * 8],
        y_stride: ys,
        uv_stride: uvs,
    };
    let mut info = vec![MbInfo::default(); mbw * mbh];
    let mut above_modes = vec![[B_DC; 4]; mbw];
    let mut above_nz = vec![Nz::default(); mbw];

    for mby in 0..mbh {
        let mut left_modes = [B_DC; 4];
        let mut left_nz = Nz::default();
        let tokens = &mut parts[mby % partitions];
        for mbx in 0..mbw {
            // --- macroblock header (first partition)
            let segment = if seg.update_map { usize::from(d.tree(&SEGMENT_TREE, &seg.probs)) } else { 0 };
            let skip = skip_prob.is_some_and(|p| d.read(p));
            let ymode = d.tree(&KF_YMODE_TREE, &KF_YMODE_PROB);
            let mut bmodes = [0u8; 16];
            if ymode == B_PRED {
                for i in 0..16 {
                    let above = if i < 4 { above_modes[mbx][i] } else { bmodes[i - 4] };
                    let left = if i % 4 == 0 { left_modes[i / 4] } else { bmodes[i - 1] };
                    bmodes[i] = d.tree(&BMODE_TREE, &KF_BMODE_PROB[usize::from(above)][usize::from(left)]);
                }
            } else {
                let implied = match ymode {
                    V_PRED => B_VE,
                    H_PRED => B_HE,
                    TM_PRED => B_TM,
                    _ => B_DC,
                };
                bmodes = [implied; 16];
            }
            above_modes[mbx] = [bmodes[12], bmodes[13], bmodes[14], bmodes[15]];
            left_modes = [bmodes[3], bmodes[7], bmodes[11], bmodes[15]];
            let uvmode = d.tree(&UV_MODE_TREE, &KF_UV_MODE_PROB);

            // --- residue (token partition)
            let q = seg_dq[segment];
            let mut y_coeffs = [[0i32; 16]; 16];
            let mut u_coeffs = [[0i32; 16]; 4];
            let mut v_coeffs = [[0i32; 16]; 4];
            let has_y2 = ymode != B_PRED;
            let an = &mut above_nz[mbx];
            let mut any = false;
            if skip {
                // No residue: neighbours see empty blocks (Y2 context only
                // changes for macroblocks that have a Y2 block).
                an.y = [false; 4];
                an.u = [false; 2];
                an.v = [false; 2];
                left_nz.y = [false; 4];
                left_nz.u = [false; 2];
                left_nz.v = [false; 2];
                if has_y2 {
                    an.y2 = false;
                    left_nz.y2 = false;
                }
            } else {
                let first = if has_y2 {
                    let mut y2 = [0i32; 16];
                    let ctx = usize::from(an.y2) + usize::from(left_nz.y2);
                    let nz = read_block(tokens, &coeff_probs[PLANE_Y2], 0, ctx, q.y2, &mut y2);
                    an.y2 = nz;
                    left_nz.y2 = nz;
                    any |= nz;
                    for (b, dc) in inverse_wht(&y2).into_iter().enumerate() {
                        y_coeffs[b][0] = dc;
                    }
                    1
                } else {
                    0
                };
                let plane = if has_y2 { PLANE_Y_AFTER_Y2 } else { PLANE_Y_WITH_DC };
                for (b, coeffs) in y_coeffs.iter_mut().enumerate() {
                    let (bx, by) = (b % 4, b / 4);
                    let ctx = usize::from(an.y[bx]) + usize::from(left_nz.y[by]);
                    let nz = read_block(tokens, &coeff_probs[plane], first, ctx, q.y1, coeffs);
                    an.y[bx] = nz;
                    left_nz.y[by] = nz;
                    any |= nz;
                }
                for (coeffs, above, left) in
                    [(&mut u_coeffs, &mut an.u, &mut left_nz.u), (&mut v_coeffs, &mut an.v, &mut left_nz.v)]
                {
                    for (b, c) in coeffs.iter_mut().enumerate() {
                        let (bx, by) = (b % 2, b / 2);
                        let ctx = usize::from(above[bx]) + usize::from(left[by]);
                        let nz = read_block(tokens, &coeff_probs[PLANE_CHROMA], 0, ctx, q.uv, c);
                        above[bx] = nz;
                        left[by] = nz;
                        any |= nz;
                    }
                }
            }
            info[mby * mbw + mbx] = MbInfo { segment, bpred: ymode == B_PRED, has_coeffs: any };

            // --- reconstruction
            reconstruct_luma(&mut frame, mbx, mby, mbw, ymode, &bmodes, &y_coeffs);
            reconstruct_chroma(&mut frame, mbx, mby, uvmode, &u_coeffs, &v_coeffs);
        }
        if d.overrun {
            return Err(bad("first partition is truncated"));
        }
        if parts[mby % partitions].overrun {
            return Err(bad("token partition is truncated"));
        }
    }

    // Loop filter over the whole reconstructed frame (RFC 6386 §15). A
    // frame-level level of 0 disables it, whatever the segments say.
    if filter_level > 0 {
        let level_of = |mb: &MbInfo| {
            let mut level = if !seg.enabled {
                filter_level
            } else if seg.absolute {
                seg.filter[mb.segment]
            } else {
                filter_level + seg.filter[mb.segment]
            }
            .clamp(0, 63);
            if adjust {
                level += ref_delta_intra;
                if mb.bpred {
                    level += mode_delta_bpred;
                }
            }
            level.clamp(0, 63)
        };
        for mby in 0..mbh {
            for mbx in 0..mbw {
                let mb = info[mby * mbw + mbx];
                let level = level_of(&mb);
                if level == 0 {
                    continue;
                }
                let mut interior = level;
                if sharpness > 0 {
                    interior >>= if sharpness > 4 { 2 } else { 1 };
                    interior = interior.min(9 - sharpness);
                }
                let interior = interior.max(1);
                let hev = if level >= 40 {
                    2
                } else if level >= 15 {
                    1
                } else {
                    0
                };
                let params = FilterParams {
                    mb_edge: (level + 2) * 2 + interior,
                    sub_edge: level * 2 + interior,
                    interior,
                    hev,
                    inner: mb.bpred || mb.has_coeffs,
                };
                filter_macroblock(&mut frame, mbx, mby, &params, simple_filter);
            }
        }
    }
    Ok(frame)
}

/// Builds the prediction workspace for one plane of a macroblock: row 0
/// holds the corner and the row above (plus `extra` pixels to the
/// right), column 0 the left column, as RFC 6386 §12 defines them at the
/// frame edges (127 above, 129 to the left).
#[allow(clippy::too_many_arguments)]
fn workspace(
    plane: &[u8],
    stride: usize,
    mbx: usize,
    mby: usize,
    size: usize,
    extra: usize,
    last_column: bool,
) -> (Vec<u8>, usize) {
    let ws_stride = 1 + size + extra;
    let mut ws = vec![0u8; ws_stride * (size + 1)];
    let (x0, y0) = (mbx * size, mby * size);
    ws[0] = if mby == 0 {
        127
    } else if mbx == 0 {
        129
    } else {
        plane[(y0 - 1) * stride + x0 - 1]
    };
    for c in 0..size + extra {
        ws[1 + c] = if mby == 0 {
            127
        } else if c >= size && last_column {
            // Beyond the right edge: repeat the last pixel above.
            plane[(y0 - 1) * stride + x0 + size - 1]
        } else {
            plane[(y0 - 1) * stride + x0 + c]
        };
    }
    for r in 0..size {
        ws[(r + 1) * ws_stride] = if mbx == 0 { 129 } else { plane[(y0 + r) * stride + x0 - 1] };
    }
    (ws, ws_stride)
}

fn copy_out(
    ws: &[u8],
    ws_stride: usize,
    plane: &mut [u8],
    stride: usize,
    mbx: usize,
    mby: usize,
    size: usize,
) {
    for r in 0..size {
        let src = &ws[(r + 1) * ws_stride + 1..(r + 1) * ws_stride + 1 + size];
        let dst = (mby * size + r) * stride + mbx * size;
        plane[dst..dst + size].copy_from_slice(src);
    }
}

fn reconstruct_luma(
    frame: &mut Frame,
    mbx: usize,
    mby: usize,
    mbw: usize,
    ymode: u8,
    bmodes: &[u8; 16],
    coeffs: &[[i32; 16]; 16],
) {
    let stride = frame.y_stride;
    let (mut ws, wss) = workspace(&frame.y, stride, mbx, mby, 16, 4, mbx + 1 == mbw);
    if ymode == B_PRED {
        // Right-column subblocks below the top row use the pixels above
        // and to the right of the macroblock (RFC 6386 §12.3).
        let above_right: [u8; 4] = std::array::from_fn(|i| ws[17 + i]);
        for row in [4, 8, 12] {
            ws[row * wss + 17..row * wss + 21].copy_from_slice(&above_right);
        }
        for (b, &mode) in bmodes.iter().enumerate() {
            let at = (1 + (b / 4) * 4) * wss + 1 + (b % 4) * 4;
            predict_subblock(&mut ws, at, wss, mode);
            add_inverse_dct(&coeffs[b], &mut ws, at, wss);
        }
    } else {
        predict_block(&mut ws, wss + 1, wss, 16, ymode, mby > 0, mbx > 0);
        for (b, c) in coeffs.iter().enumerate() {
            let at = (1 + (b / 4) * 4) * wss + 1 + (b % 4) * 4;
            add_inverse_dct(c, &mut ws, at, wss);
        }
    }
    copy_out(&ws, wss, &mut frame.y, stride, mbx, mby, 16);
}

fn reconstruct_chroma(
    frame: &mut Frame,
    mbx: usize,
    mby: usize,
    mode: u8,
    u: &[[i32; 16]; 4],
    v: &[[i32; 16]; 4],
) {
    let stride = frame.uv_stride;
    for (plane, coeffs) in [(&mut frame.u, u), (&mut frame.v, v)] {
        let (mut ws, wss) = workspace(plane, stride, mbx, mby, 8, 0, false);
        predict_block(&mut ws, wss + 1, wss, 8, mode, mby > 0, mbx > 0);
        for (b, c) in coeffs.iter().enumerate() {
            let at = (1 + (b / 2) * 4) * wss + 1 + (b % 2) * 4;
            add_inverse_dct(c, &mut ws, at, wss);
        }
        copy_out(&ws, wss, plane, stride, mbx, mby, 8);
    }
}

// ------------------------------------------------------------ loop filter

struct FilterParams {
    mb_edge: i32,
    sub_edge: i32,
    interior: i32,
    hev: i32,
    /// Filter the edges between subblocks too.
    inner: bool,
}

/// Signed 8-bit clamp.
fn c8(v: i32) -> i32 {
    v.clamp(-128, 127)
}

/// Accessor for the pixels of one segment straddling an edge: index 0 is
/// the first pixel after the edge, −1 the last before it.
struct Seg<'a> {
    buf: &'a mut [u8],
    at: usize,
    step: usize,
}

impl Seg<'_> {
    fn get(&self, k: isize) -> i32 {
        i32::from(self.buf[(self.at as isize + k * self.step as isize) as usize]) - 128
    }

    fn set(&mut self, k: isize, v: i32) {
        self.buf[(self.at as isize + k * self.step as isize) as usize] = (c8(v) + 128) as u8;
    }

    /// The simple-filter threshold on the four pixels at the edge.
    fn edge_ok(&self, limit: i32) -> bool {
        (self.get(-1) - self.get(0)).abs() * 2 + (self.get(-2) - self.get(1)).abs() / 2 <= limit
    }

    fn normal_ok(&self, edge: i32, interior: i32) -> bool {
        self.edge_ok(edge)
            && (-4..3).filter(|&k| k != -1).all(|k| (self.get(k) - self.get(k + 1)).abs() <= interior)
    }

    fn high_variance(&self, hev: i32) -> bool {
        (self.get(-2) - self.get(-1)).abs() > hev || (self.get(1) - self.get(0)).abs() > hev
    }

    /// Moves the two edge pixels towards each other (RFC 6386 §15.2);
    /// returns the adjustment applied to the pixel after the edge.
    fn common_adjust(&mut self, outer_taps: bool) -> i32 {
        let (p1, p0, q0, q1) = (self.get(-2), self.get(-1), self.get(0), self.get(1));
        let a = c8(if outer_taps { c8(p1 - q1) } else { 0 } + 3 * (q0 - p0));
        let b = c8(a + 3) >> 3;
        let a = c8(a + 4) >> 3;
        self.set(0, q0 - a);
        self.set(-1, p0 + b);
        a
    }
}

fn simple_segment(s: &mut Seg<'_>, limit: i32) {
    if s.edge_ok(limit) {
        s.common_adjust(true);
    }
}

fn subblock_segment(s: &mut Seg<'_>, p: &FilterParams) {
    if !s.normal_ok(p.sub_edge, p.interior) {
        return;
    }
    let hv = s.high_variance(p.hev);
    let a = (s.common_adjust(hv) + 1) >> 1;
    if !hv {
        let (p1, q1) = (s.get(-2), s.get(1));
        s.set(1, q1 - a);
        s.set(-2, p1 + a);
    }
}

fn macroblock_segment(s: &mut Seg<'_>, p: &FilterParams) {
    if !s.normal_ok(p.mb_edge, p.interior) {
        return;
    }
    if s.high_variance(p.hev) {
        s.common_adjust(true);
        return;
    }
    let w = c8(c8(s.get(-2) - s.get(1)) + 3 * (s.get(0) - s.get(-1)));
    for (k, weight) in [(0isize, 27), (1, 18), (2, 9)] {
        let a = c8((weight * w + 63) >> 7);
        let (pk, qk) = (s.get(-1 - k), s.get(k));
        s.set(k, qk - a);
        s.set(-1 - k, pk + a);
    }
}

#[derive(Clone, Copy)]
enum EdgeKind {
    Macroblock,
    Subblock,
}

/// Filters one edge of `len` segments. Vertical edges (between columns)
/// have neighbours along the row, horizontal edges along the column.
#[allow(clippy::too_many_arguments)]
fn filter_edge(
    buf: &mut [u8],
    stride: usize,
    x: usize,
    y: usize,
    vertical: bool,
    len: usize,
    kind: EdgeKind,
    p: &FilterParams,
    simple: bool,
) {
    let (step, along) = if vertical { (1, stride) } else { (stride, 1) };
    for i in 0..len {
        let mut s = Seg { buf: &mut *buf, at: y * stride + x + i * along, step };
        match (simple, kind) {
            (true, EdgeKind::Macroblock) => simple_segment(&mut s, p.mb_edge),
            (true, EdgeKind::Subblock) => simple_segment(&mut s, p.sub_edge),
            (false, EdgeKind::Macroblock) => macroblock_segment(&mut s, p),
            (false, EdgeKind::Subblock) => subblock_segment(&mut s, p),
        }
    }
}

fn filter_macroblock(frame: &mut Frame, mbx: usize, mby: usize, p: &FilterParams, simple: bool) {
    let (ys, uvs) = (frame.y_stride, frame.uv_stride);
    let (x, y) = (mbx * 16, mby * 16);
    let (cx, cy) = (mbx * 8, mby * 8);
    // The simple filter touches luma only.
    let chroma = !simple;
    // 1. Left macroblock edge; 2. inner vertical edges;
    // 3. top macroblock edge; 4. inner horizontal edges.
    for vertical in [true, false] {
        let at_border = if vertical { mbx == 0 } else { mby == 0 };
        if !at_border {
            filter_edge(&mut frame.y, ys, x, y, vertical, 16, EdgeKind::Macroblock, p, simple);
            if chroma {
                filter_edge(&mut frame.u, uvs, cx, cy, vertical, 8, EdgeKind::Macroblock, p, simple);
                filter_edge(&mut frame.v, uvs, cx, cy, vertical, 8, EdgeKind::Macroblock, p, simple);
            }
        }
        if p.inner {
            for k in [4, 8, 12] {
                let (ex, ey) = if vertical { (x + k, y) } else { (x, y + k) };
                filter_edge(&mut frame.y, ys, ex, ey, vertical, 16, EdgeKind::Subblock, p, simple);
            }
            if chroma {
                let (ex, ey) = if vertical { (cx + 4, cy) } else { (cx, cy + 4) };
                filter_edge(&mut frame.u, uvs, ex, ey, vertical, 8, EdgeKind::Subblock, p, simple);
                filter_edge(&mut frame.v, uvs, ex, ey, vertical, 8, EdgeKind::Subblock, p, simple);
            }
        }
    }
}
