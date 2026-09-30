//! WebP lossless (VP8L) decoder, written from RFC 9649 section 3.
//!
//! The decoder produces ARGB pixels packed as `0xAARRGGBB`. Every read is
//! bounds-checked: a truncated or inconsistent stream is an error, never a
//! panic or an out-of-bounds access.

use sf_core::{Error, Result};

fn bad(what: impl std::fmt::Display) -> Error {
    Error::invalid_input(format!("webp lossless: {what}"))
}

/// Neighbourhood offsets `(dx, dy)` for distance codes 1–120, where the
/// scan-line distance is `dx + dy × width` (RFC 9649 §3.6.2.2.1; extracted
/// from the RFC text by script).
const DISTANCE_MAP: [(i8, i8); 120] = [
    (0, 1),
    (1, 0),
    (1, 1),
    (-1, 1),
    (0, 2),
    (2, 0),
    (1, 2),
    (-1, 2),
    (2, 1),
    (-2, 1),
    (2, 2),
    (-2, 2),
    (0, 3),
    (3, 0),
    (1, 3),
    (-1, 3),
    (3, 1),
    (-3, 1),
    (2, 3),
    (-2, 3),
    (3, 2),
    (-3, 2),
    (0, 4),
    (4, 0),
    (1, 4),
    (-1, 4),
    (4, 1),
    (-4, 1),
    (3, 3),
    (-3, 3),
    (2, 4),
    (-2, 4),
    (4, 2),
    (-4, 2),
    (0, 5),
    (3, 4),
    (-3, 4),
    (4, 3),
    (-4, 3),
    (5, 0),
    (1, 5),
    (-1, 5),
    (5, 1),
    (-5, 1),
    (2, 5),
    (-2, 5),
    (5, 2),
    (-5, 2),
    (4, 4),
    (-4, 4),
    (3, 5),
    (-3, 5),
    (5, 3),
    (-5, 3),
    (0, 6),
    (6, 0),
    (1, 6),
    (-1, 6),
    (6, 1),
    (-6, 1),
    (2, 6),
    (-2, 6),
    (6, 2),
    (-6, 2),
    (4, 5),
    (-4, 5),
    (5, 4),
    (-5, 4),
    (3, 6),
    (-3, 6),
    (6, 3),
    (-6, 3),
    (0, 7),
    (7, 0),
    (1, 7),
    (-1, 7),
    (5, 5),
    (-5, 5),
    (7, 1),
    (-7, 1),
    (4, 6),
    (-4, 6),
    (6, 4),
    (-6, 4),
    (2, 7),
    (-2, 7),
    (7, 2),
    (-7, 2),
    (3, 7),
    (-3, 7),
    (7, 3),
    (-7, 3),
    (5, 6),
    (-5, 6),
    (6, 5),
    (-6, 5),
    (8, 0),
    (4, 7),
    (-4, 7),
    (7, 4),
    (-7, 4),
    (8, 1),
    (8, 2),
    (6, 6),
    (-6, 6),
    (8, 3),
    (5, 7),
    (-5, 7),
    (7, 5),
    (-7, 5),
    (8, 4),
    (6, 7),
    (-6, 7),
    (7, 6),
    (-7, 6),
    (8, 5),
    (7, 7),
    (-7, 7),
    (8, 6),
    (8, 7),
];

/// Order in which code-length code lengths are transmitted (RFC 9649 §3.7.2.1.2).
const CODE_LENGTH_ORDER: [usize; 19] = [17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];

/// Number of green-alphabet symbols that are LZ77 length prefixes.
const LENGTH_PREFIXES: usize = 24;

/// Least-significant-bit-first reader over a VP8L stream.
pub(super) struct BitReader<'a> {
    data: &'a [u8],
    pos: usize,
    buf: u64,
    have: u32,
}

impl<'a> BitReader<'a> {
    pub(super) fn new(data: &'a [u8]) -> Self {
        BitReader { data, pos: 0, buf: 0, have: 0 }
    }

    fn fill(&mut self) {
        while self.have <= 56 && self.pos < self.data.len() {
            self.buf |= u64::from(self.data[self.pos]) << self.have;
            self.pos += 1;
            self.have += 8;
        }
    }

    /// Reads `n` ≤ 32 bits.
    pub(super) fn bits(&mut self, n: u32) -> Result<u32> {
        if n == 0 {
            return Ok(0);
        }
        if self.have < n {
            self.fill();
            if self.have < n {
                return Err(bad("truncated stream"));
            }
        }
        let v = (self.buf & ((1u64 << n) - 1)) as u32;
        self.buf >>= n;
        self.have -= n;
        Ok(v)
    }

    fn bit(&mut self) -> Result<bool> {
        Ok(self.bits(1)? == 1)
    }

    /// The next 8 bits without consuming them (missing bits read as zero;
    /// consuming them later fails).
    fn peek8(&mut self) -> u32 {
        if self.have < 8 {
            self.fill();
        }
        (self.buf & 0xFF) as u32
    }

    fn consume(&mut self, n: u32) -> Result<()> {
        if self.have < n {
            return Err(bad("truncated stream"));
        }
        self.buf >>= n;
        self.have -= n;
        Ok(())
    }
}

/// A canonical prefix code. Codes up to 8 bits long are found with one
/// table lookup; longer ones are walked bit by bit.
struct PrefixCode {
    /// The only symbol, for codes with a single used symbol (zero bits).
    single: Option<u16>,
    /// Indexed by the next 8 input bits: `symbol << 4 | length`, or 0.
    fast: Vec<u16>,
    /// Number of codes of each length.
    counts: [u16; 16],
    /// Symbols sorted by (length, value).
    symbols: Vec<u16>,
}

impl PrefixCode {
    fn new(lengths: &[u8]) -> Result<PrefixCode> {
        let used: Vec<usize> = (0..lengths.len()).filter(|&s| lengths[s] != 0).collect();
        match used.len() {
            0 => return Err(bad("empty prefix code")),
            1 => {
                return Ok(PrefixCode {
                    single: Some(used[0] as u16),
                    fast: Vec::new(),
                    counts: [0; 16],
                    symbols: Vec::new(),
                });
            }
            _ => {}
        }
        let mut counts = [0u16; 16];
        for &s in &used {
            counts[lengths[s] as usize] += 1;
        }
        // The code must be complete: the Kraft sum is exactly one.
        let mut room: i64 = 1;
        for &c in &counts[1..] {
            room = room * 2 - i64::from(c);
            if room < 0 {
                return Err(bad("over-subscribed prefix code"));
            }
        }
        if room != 0 {
            return Err(bad("incomplete prefix code"));
        }
        let mut sorted = used;
        sorted.sort_by_key(|&s| (lengths[s], s));
        let symbols: Vec<u16> = sorted.into_iter().map(|s| s as u16).collect();
        // Assign canonical codes; spread those of at most 8 bits over the
        // fast table. Code bits arrive most significant first.
        let mut fast = vec![0u16; 256];
        let mut code = 0u32;
        let mut k = 0usize;
        for len in 1..16u32 {
            for _ in 0..counts[len as usize] {
                if len <= 8 {
                    let mut i = (code.reverse_bits() >> (32 - len)) as usize;
                    while i < 256 {
                        fast[i] = (symbols[k] << 4) | len as u16;
                        i += 1 << len;
                    }
                }
                code += 1;
                k += 1;
            }
            code <<= 1;
        }
        Ok(PrefixCode { single: None, fast, counts, symbols })
    }

    fn read(&self, br: &mut BitReader<'_>) -> Result<u16> {
        if let Some(s) = self.single {
            return Ok(s);
        }
        let e = self.fast[br.peek8() as usize];
        if e != 0 {
            br.consume(u32::from(e & 15))?;
            return Ok(e >> 4);
        }
        // Canonical walk: `first` is the first code of the current length.
        let (mut code, mut first, mut index) = (0i32, 0i32, 0i32);
        for len in 1..16 {
            code |= br.bits(1)? as i32;
            let count = i32::from(self.counts[len]);
            if code - first < count {
                return Ok(self.symbols[(index + code - first) as usize]);
            }
            index += count;
            first = (first + count) << 1;
            code <<= 1;
        }
        Err(bad("invalid prefix code"))
    }
}

/// Reads one prefix code over an alphabet of `size` symbols.
fn read_code(br: &mut BitReader<'_>, size: usize) -> Result<PrefixCode> {
    let mut lengths = vec![0u8; size];
    if br.bit()? {
        // Simple code: one or two symbols of length 1.
        let two = br.bit()?;
        let first_bits = if br.bit()? { 8 } else { 1 };
        let mut symbols = vec![br.bits(first_bits)? as usize];
        if two {
            symbols.push(br.bits(8)? as usize);
        }
        for s in symbols {
            *lengths.get_mut(s).ok_or_else(|| bad("symbol outside the alphabet"))? = 1;
        }
        return PrefixCode::new(&lengths);
    }
    let n = 4 + br.bits(4)? as usize;
    let mut cl_lengths = [0u8; 19];
    for &i in &CODE_LENGTH_ORDER[..n] {
        cl_lengths[i] = br.bits(3)? as u8;
    }
    let cl = PrefixCode::new(&cl_lengths)?;
    // The optional limit counts code-length symbols read, not lengths set.
    let mut budget = if br.bit()? {
        let nbits = 2 + 2 * br.bits(3)?;
        let m = 2 + br.bits(nbits)? as usize;
        if m > size {
            return Err(bad("code length count exceeds the alphabet"));
        }
        m
    } else {
        size
    };
    let mut sym = 0usize;
    let mut previous = 8u8;
    while sym < size && budget > 0 {
        budget -= 1;
        let c = cl.read(br)?;
        let (value, repeat) = match c {
            0..=15 => {
                lengths[sym] = c as u8;
                sym += 1;
                if c != 0 {
                    previous = c as u8;
                }
                continue;
            }
            16 => (previous, 3 + br.bits(2)? as usize),
            17 => (0, 3 + br.bits(3)? as usize),
            _ => (0, 11 + br.bits(7)? as usize),
        };
        if sym + repeat > size {
            return Err(bad("code length repeat runs past the alphabet"));
        }
        lengths[sym..sym + repeat].fill(value);
        sym += repeat;
    }
    PrefixCode::new(&lengths)
}

/// The five codes used for one region of the image.
struct Group {
    green: PrefixCode,
    red: PrefixCode,
    blue: PrefixCode,
    alpha: PrefixCode,
    distance: PrefixCode,
}

fn read_group(br: &mut BitReader<'_>, cache_bits: u32) -> Result<Group> {
    let cache = if cache_bits > 0 { 1usize << cache_bits } else { 0 };
    Ok(Group {
        green: read_code(br, 256 + LENGTH_PREFIXES + cache)?,
        red: read_code(br, 256)?,
        blue: read_code(br, 256)?,
        alpha: read_code(br, 256)?,
        distance: read_code(br, 40)?,
    })
}

/// Value of an LZ77 length or distance prefix symbol plus its extra bits.
fn prefix_value(br: &mut BitReader<'_>, symbol: u16) -> Result<usize> {
    let s = u32::from(symbol);
    if s < 4 {
        return Ok(s as usize + 1);
    }
    let extra = (s - 2) >> 1;
    let offset = (2 + (s & 1)) << extra;
    Ok((offset + br.bits(extra)?) as usize + 1)
}

fn div_up(v: usize, bits: u32) -> usize {
    (v + (1 << bits) - 1) >> bits
}

/// Decodes entropy-coded pixels. `meta` is `(prefix_bits, entropy image)`
/// when the main image uses several prefix code groups.
fn decode_pixels(
    br: &mut BitReader<'_>,
    width: usize,
    height: usize,
    cache_bits: u32,
    meta: Option<(u32, Vec<u32>)>,
) -> Result<Vec<u32>> {
    // Only groups the entropy image refers to are kept. The others must
    // still be read, but are dropped, so a hostile index range cannot
    // force large allocations.
    let (bits, index_of, groups) = match meta {
        None => (0, Vec::new(), vec![read_group(br, cache_bits)?]),
        Some((bits, image)) => {
            let raw: Vec<usize> = image.iter().map(|&p| ((p >> 8) & 0xFFFF) as usize).collect();
            let count = raw.iter().copied().max().unwrap_or(0) + 1;
            let mut referenced = vec![false; count];
            for &r in &raw {
                referenced[r] = true;
            }
            let mut slot = vec![0usize; count];
            let mut groups = Vec::new();
            for (s, &keep) in slot.iter_mut().zip(&referenced) {
                let g = read_group(br, cache_bits)?;
                if keep {
                    *s = groups.len();
                    groups.push(g);
                }
            }
            (bits, raw.iter().map(|&r| slot[r]).collect(), groups)
        }
    };
    let block_w = div_up(width, bits);
    let total = width * height;
    let mut out = vec![0u32; total];
    let mut cache = vec![0u32; if cache_bits > 0 { 1 << cache_bits } else { 0 }];
    let cache_shift = 32 - cache_bits;
    let remember = |cache: &mut Vec<u32>, px: u32| {
        if !cache.is_empty() {
            cache[(0x1E35_A7BDu32.wrapping_mul(px) >> cache_shift) as usize] = px;
        }
    };
    let mut pos = 0usize;
    while pos < total {
        let g = if index_of.is_empty() {
            &groups[0]
        } else {
            let (x, y) = (pos % width, pos / width);
            &groups[index_of[(y >> bits) * block_w + (x >> bits)]]
        };
        let s = g.green.read(br)?;
        if s < 256 {
            let r = u32::from(g.red.read(br)?);
            let b = u32::from(g.blue.read(br)?);
            let a = u32::from(g.alpha.read(br)?);
            let px = a << 24 | r << 16 | u32::from(s) << 8 | b;
            out[pos] = px;
            remember(&mut cache, px);
            pos += 1;
        } else if (s as usize) < 256 + LENGTH_PREFIXES {
            let len = prefix_value(br, s - 256)?;
            let dsym = g.distance.read(br)?;
            let code = prefix_value(br, dsym)?;
            let dist = if code > 120 {
                code - 120
            } else {
                let (dx, dy) = DISTANCE_MAP[code - 1];
                (i64::from(dx) + i64::from(dy) * width as i64).max(1) as usize
            };
            if dist > pos || len > total - pos {
                return Err(bad("backward reference outside the image"));
            }
            for _ in 0..len {
                let px = out[pos - dist];
                out[pos] = px;
                remember(&mut cache, px);
                pos += 1;
            }
        } else {
            let i = s as usize - 256 - LENGTH_PREFIXES;
            let px = *cache.get(i).ok_or_else(|| bad("colour cache index without a cache"))?;
            out[pos] = px;
            pos += 1;
        }
    }
    Ok(out)
}

fn read_cache_bits(br: &mut BitReader<'_>) -> Result<u32> {
    if !br.bit()? {
        return Ok(0);
    }
    let b = br.bits(4)?;
    if !(1..=11).contains(&b) {
        return Err(bad("invalid colour cache size"));
    }
    Ok(b)
}

/// A sub-resolution image (predictor modes, colour transform elements,
/// entropy image or colour table): no transforms, one prefix code group.
fn decode_sub_image(br: &mut BitReader<'_>, width: usize, height: usize) -> Result<Vec<u32>> {
    let cache_bits = read_cache_bits(br)?;
    decode_pixels(br, width, height, cache_bits, None)
}

enum Transform {
    Predictor {
        bits: u32,
        width: usize,
        modes: Vec<u32>,
    },
    Colour {
        bits: u32,
        width: usize,
        elements: Vec<u32>,
    },
    SubtractGreen,
    /// `width` is the full width; pixels arrive packed below it.
    Indexing {
        bits: u32,
        width: usize,
        table: Vec<u32>,
    },
}

/// Per-channel sum modulo 256.
fn add_px(a: u32, b: u32) -> u32 {
    let ag = (a & 0xFF00_FF00).wrapping_add(b & 0xFF00_FF00) & 0xFF00_FF00;
    let rb = (a & 0x00FF_00FF).wrapping_add(b & 0x00FF_00FF) & 0x00FF_00FF;
    ag | rb
}

fn channels(p: u32) -> [i32; 4] {
    [(p >> 24) as i32, (p >> 16 & 0xFF) as i32, (p >> 8 & 0xFF) as i32, (p & 0xFF) as i32]
}

fn pack(c: [i32; 4]) -> u32 {
    (c[0] as u32) << 24 | (c[1] as u32) << 16 | (c[2] as u32) << 8 | c[3] as u32
}

fn average2(a: u32, b: u32) -> u32 {
    let (x, y) = (channels(a), channels(b));
    pack([0, 1, 2, 3].map(|i| (x[i] + y[i]) / 2))
}

fn predict(mode: u32, l: u32, t: u32, tr: u32, tl: u32) -> Result<u32> {
    Ok(match mode {
        0 => 0xFF00_0000,
        1 => l,
        2 => t,
        3 => tr,
        4 => tl,
        5 => average2(average2(l, tr), t),
        6 => average2(l, tl),
        7 => average2(l, t),
        8 => average2(tl, t),
        9 => average2(t, tr),
        10 => average2(average2(l, tl), average2(t, tr)),
        11 => {
            let (cl, ct, ctl) = (channels(l), channels(t), channels(tl));
            let estimate = [0, 1, 2, 3].map(|i| cl[i] + ct[i] - ctl[i]);
            let distance = |c: &[i32; 4]| (0..4).map(|i| (estimate[i] - c[i]).abs()).sum::<i32>();
            if distance(&cl) < distance(&ct) { l } else { t }
        }
        12 => {
            let (cl, ct, ctl) = (channels(l), channels(t), channels(tl));
            pack([0, 1, 2, 3].map(|i| (cl[i] + ct[i] - ctl[i]).clamp(0, 255)))
        }
        13 => {
            let (a, ctl) = (channels(average2(l, t)), channels(tl));
            pack([0, 1, 2, 3].map(|i| (a[i] + (a[i] - ctl[i]) / 2).clamp(0, 255)))
        }
        m => return Err(bad(format!("invalid predictor mode {m}"))),
    })
}

/// Signed 3.5 fixed-point multiplier `t` applied to signed channel `c`.
fn colour_delta(t: u32, c: u32) -> i32 {
    (i32::from(t as u8 as i8) * i32::from(c as u8 as i8)) >> 5
}

impl Transform {
    /// Inverts the transform over `height` rows.
    fn invert(&self, px: Vec<u32>, height: usize) -> Result<Vec<u32>> {
        match self {
            Transform::Predictor { bits, width, modes } => {
                let (w, mut px) = (*width, px);
                let bw = div_up(w, *bits);
                for y in 0..height {
                    for x in 0..w {
                        let i = y * w + x;
                        let pred = if y == 0 {
                            if x == 0 { 0xFF00_0000 } else { px[i - 1] }
                        } else if x == 0 {
                            px[i - w]
                        } else {
                            let mode = modes[(y >> bits) * bw + (x >> bits)] >> 8 & 0xFF;
                            // In the last column, index i - w + 1 is the first
                            // pixel of the current row, as the format specifies.
                            predict(mode, px[i - 1], px[i - w], px[i - w + 1], px[i - w - 1])?
                        };
                        px[i] = add_px(px[i], pred);
                    }
                }
                Ok(px)
            }
            Transform::Colour { bits, width, elements } => {
                let (w, mut px) = (*width, px);
                let bw = div_up(w, *bits);
                for y in 0..height {
                    for x in 0..w {
                        let e = elements[(y >> bits) * bw + (x >> bits)];
                        let (g2r, g2b, r2b) = (e & 0xFF, e >> 8 & 0xFF, e >> 16 & 0xFF);
                        let p = &mut px[y * w + x];
                        let g = *p >> 8 & 0xFF;
                        let r = ((*p >> 16 & 0xFF) as i32 + colour_delta(g2r, g)) as u32 & 0xFF;
                        let b =
                            ((*p & 0xFF) as i32 + colour_delta(g2b, g) + colour_delta(r2b, r)) as u32 & 0xFF;
                        *p = (*p & 0xFF00_FF00) | r << 16 | b;
                    }
                }
                Ok(px)
            }
            Transform::SubtractGreen => Ok(px
                .into_iter()
                .map(|p| {
                    let g = p >> 8 & 0xFF;
                    let r = ((p >> 16) + g) & 0xFF;
                    let b = (p + g) & 0xFF;
                    (p & 0xFF00_FF00) | r << 16 | b
                })
                .collect()),
            Transform::Indexing { bits, width, table } => {
                let w = *width;
                let packed_w = div_up(w, *bits);
                let per = 8u32 >> bits; // bits per packed index
                let mask = (1u32 << per) - 1;
                let mut out = vec![0u32; w * height];
                for y in 0..height {
                    for x in 0..w {
                        let g = px[y * packed_w + (x >> bits)] >> 8 & 0xFF;
                        let idx = (g >> ((x as u32 & ((1 << bits) - 1)) * per)) & mask;
                        out[y * w + x] = table.get(idx as usize).copied().unwrap_or(0);
                    }
                }
                Ok(out)
            }
        }
    }
}

/// Decodes a complete image stream (transforms and main image) of the
/// given size, as found after the VP8L header or in an `ALPH` chunk.
pub(super) fn decode_stream(br: &mut BitReader<'_>, width: usize, height: usize) -> Result<Vec<u32>> {
    let mut transforms = Vec::new();
    let mut seen = [false; 4];
    let mut w = width;
    while br.bit()? {
        let kind = br.bits(2)? as usize;
        if std::mem::replace(&mut seen[kind], true) {
            return Err(bad("transform used twice"));
        }
        transforms.push(match kind {
            0 | 1 => {
                let bits = br.bits(3)? + 2;
                let data = decode_sub_image(br, div_up(w, bits), div_up(height, bits))?;
                if kind == 0 {
                    Transform::Predictor { bits, width: w, modes: data }
                } else {
                    Transform::Colour { bits, width: w, elements: data }
                }
            }
            2 => Transform::SubtractGreen,
            _ => {
                let size = br.bits(8)? as usize + 1;
                let mut table = decode_sub_image(br, size, 1)?;
                for i in 1..table.len() {
                    table[i] = add_px(table[i], table[i - 1]);
                }
                let bits = match size {
                    1..=2 => 3,
                    3..=4 => 2,
                    5..=16 => 1,
                    _ => 0,
                };
                let t = Transform::Indexing { bits, width: w, table };
                w = div_up(w, bits);
                t
            }
        });
    }
    let cache_bits = read_cache_bits(br)?;
    let meta = if br.bit()? {
        let bits = br.bits(3)? + 2;
        Some((bits, decode_sub_image(br, div_up(w, bits), div_up(height, bits))?))
    } else {
        None
    };
    let mut px = decode_pixels(br, w, height, cache_bits, meta)?;
    for t in transforms.iter().rev() {
        px = t.invert(px, height)?;
    }
    Ok(px)
}

/// Parses the 5-byte VP8L header and returns (width, height).
pub(super) fn header(data: &[u8]) -> Result<(u32, u32)> {
    if data.len() < 5 || data[0] != 0x2F {
        return Err(bad("missing signature"));
    }
    let mut br = BitReader::new(&data[1..5]);
    let w = br.bits(14)? + 1;
    let h = br.bits(14)? + 1;
    let _alpha_hint = br.bits(1)?;
    if br.bits(3)? != 0 {
        return Err(bad("unknown version"));
    }
    Ok((w, h))
}

/// Decodes the pixels of a VP8L bitstream (the payload of a `VP8L` chunk)
/// whose header has already been checked, as ARGB.
pub(super) fn decode(data: &[u8], width: u32, height: u32) -> Result<Vec<u32>> {
    let mut br = BitReader::new(&data[5..]);
    decode_stream(&mut br, width as usize, height as usize)
}
