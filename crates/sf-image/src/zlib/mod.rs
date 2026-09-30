//! DEFLATE (RFC 1951) and the zlib wrapper (RFC 1950).
//!
//! The decoder validates everything (block types, code completeness,
//! distances, the Adler-32 trailer) and enforces an output size limit, so
//! a compressed "bomb" fails fast. The encoder uses LZ77 with hash chains
//! and emits, per block, whichever of dynamic-Huffman, fixed-Huffman or
//! stored coding is smallest. Every Huffman code it emits is complete, as
//! strict decoders require.

use sf_core::{Error, Result};

use crate::checksum::adler32;
use crate::huffman::huffman_lengths;

// ---------------------------------------------------------------- tables

const LEN_BASE: [u16; 29] = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195,
    227, 258,
];
const LEN_EXTRA: [u8; 29] =
    [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
const DIST_BASE: [u16; 30] = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
    4097, 6145, 8193, 12289, 16385, 24577,
];
const DIST_EXTRA: [u8; 30] =
    [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
/// Order in which code-length code lengths are transmitted.
const CL_ORDER: [usize; 19] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

fn fixed_litlen_lengths() -> [u8; 288] {
    let mut l = [0u8; 288];
    for (i, v) in l.iter_mut().enumerate() {
        *v = match i {
            0..=143 => 8,
            144..=255 => 9,
            256..=279 => 7,
            _ => 8,
        };
    }
    l
}

fn corrupt(what: &str) -> Error {
    Error::invalid_input(format!("deflate: {what}"))
}

// ---------------------------------------------------------------- decoder

struct BitReader<'a> {
    data: &'a [u8],
    pos: usize,
    buf: u64,
    count: u32,
}

impl<'a> BitReader<'a> {
    fn new(data: &'a [u8]) -> Self {
        BitReader { data, pos: 0, buf: 0, count: 0 }
    }

    fn refill(&mut self) {
        while self.count <= 56 && self.pos < self.data.len() {
            self.buf |= u64::from(self.data[self.pos]) << self.count;
            self.pos += 1;
            self.count += 8;
        }
    }

    fn bits(&mut self, n: u32) -> Result<u32> {
        if n == 0 {
            return Ok(0);
        }
        self.refill();
        if self.count < n {
            return Err(corrupt("unexpected end of data"));
        }
        let v = (self.buf & ((1u64 << n) - 1)) as u32;
        self.buf >>= n;
        self.count -= n;
        Ok(v)
    }

    fn align(&mut self) {
        let drop = self.count % 8;
        self.buf >>= drop;
        self.count -= drop;
    }

    /// Bytes of input consumed so far (after aligning).
    fn consumed(&self) -> usize {
        self.pos - (self.count / 8) as usize
    }
}

const FAST_BITS: u32 = 10;

/// Canonical Huffman decoder with a direct lookup table for short codes.
struct Huffman {
    fast: Vec<u16>,
    counts: [u16; 16],
    symbols: Vec<u16>,
}

impl Huffman {
    fn new(lengths: &[u8]) -> Result<Huffman> {
        let mut counts = [0u16; 16];
        for &l in lengths {
            counts[l as usize] += 1;
        }
        counts[0] = 0;
        // Over-subscription check (Kraft inequality).
        let mut left: i32 = 1;
        for &count in &counts[1..] {
            left <<= 1;
            left -= i32::from(count);
            if left < 0 {
                return Err(corrupt("over-subscribed Huffman code"));
            }
        }
        let used: u32 = counts.iter().map(|&c| u32::from(c)).sum();
        // Incomplete codes are accepted only for the degenerate one-symbol
        // case the format explicitly allows.
        if left > 0 && used > 1 {
            return Err(corrupt("incomplete Huffman code"));
        }
        let mut offsets = [0u16; 16];
        for len in 1..15 {
            offsets[len + 1] = offsets[len] + counts[len];
        }
        let mut symbols = vec![0u16; used as usize];
        for (sym, &l) in lengths.iter().enumerate() {
            if l != 0 {
                symbols[offsets[l as usize] as usize] = sym as u16;
                offsets[l as usize] += 1;
            }
        }
        // Fast table: index is the next FAST_BITS input bits (LSB first).
        let mut fast = vec![0u16; 1 << FAST_BITS];
        let mut code: u32 = 0;
        let mut index = 0usize;
        for len in 1..=15u32 {
            for _ in 0..counts[len as usize] {
                if len <= FAST_BITS {
                    let rev = code.reverse_bits() >> (32 - len);
                    let entry = ((len as u16) << 12) | symbols[index];
                    let mut k = rev;
                    while k < (1 << FAST_BITS) {
                        fast[k as usize] = entry;
                        k += 1 << len;
                    }
                }
                code += 1;
                index += 1;
            }
            code <<= 1;
        }
        Ok(Huffman { fast, counts, symbols })
    }

    fn decode(&self, br: &mut BitReader<'_>) -> Result<u16> {
        br.refill();
        let entry = self.fast[(br.buf & ((1 << FAST_BITS) - 1)) as usize];
        if entry != 0 {
            let len = u32::from(entry >> 12);
            if len > br.count {
                return Err(corrupt("unexpected end of data"));
            }
            br.buf >>= len;
            br.count -= len;
            return Ok(entry & 0x0FFF);
        }
        // Slow path for codes longer than FAST_BITS.
        let (mut code, mut first, mut index) = (0i32, 0i32, 0i32);
        for len in 1..16 {
            code |= br.bits(1)? as i32;
            let count = i32::from(self.counts[len]);
            if code - first < count {
                return Ok(self.symbols[(index + code - first) as usize]);
            }
            index += count;
            first += count;
            first <<= 1;
            code <<= 1;
        }
        Err(corrupt("invalid Huffman code"))
    }
}

/// Decompresses a raw DEFLATE stream. Returns the data and the number of
/// input bytes consumed. Fails with `LimitExceeded` beyond `max_out` bytes.
pub fn inflate(data: &[u8], max_out: usize) -> Result<(Vec<u8>, usize)> {
    let mut br = BitReader::new(data);
    let mut out: Vec<u8> = Vec::new();
    let too_big = || Error::limit_exceeded(format!("deflate: output exceeds the limit of {max_out} bytes"));
    loop {
        let last = br.bits(1)? == 1;
        match br.bits(2)? {
            0 => {
                br.align();
                let len = br.bits(16)? as usize;
                let nlen = br.bits(16)? as usize;
                if len != (!nlen & 0xFFFF) {
                    return Err(corrupt("stored block length check failed"));
                }
                if out.len() + len > max_out {
                    return Err(too_big());
                }
                for _ in 0..len {
                    out.push(br.bits(8)? as u8);
                }
            }
            1 => {
                let lit = Huffman::new(&fixed_litlen_lengths())?;
                // 32 five-bit codes; symbols 30 and 31 are invalid in data.
                let dist = Huffman::new(&[5u8; 32])?;
                inflate_block(&mut br, &lit, &dist, &mut out, max_out)?;
            }
            2 => {
                let (lit, dist) = read_dynamic_tables(&mut br)?;
                inflate_block(&mut br, &lit, &dist, &mut out, max_out)?;
            }
            _ => return Err(corrupt("reserved block type")),
        }
        if last {
            break;
        }
    }
    br.align();
    Ok((out, br.consumed()))
}

fn read_dynamic_tables(br: &mut BitReader<'_>) -> Result<(Huffman, Huffman)> {
    let hlit = br.bits(5)? as usize + 257;
    let hdist = br.bits(5)? as usize + 1;
    let hclen = br.bits(4)? as usize + 4;
    if hlit > 286 || hdist > 30 {
        return Err(corrupt("too many length or distance codes"));
    }
    let mut cl_lengths = [0u8; 19];
    for &i in CL_ORDER.iter().take(hclen) {
        cl_lengths[i] = br.bits(3)? as u8;
    }
    let cl = Huffman::new(&cl_lengths)?;
    let mut lengths = vec![0u8; hlit + hdist];
    let mut i = 0;
    while i < lengths.len() {
        let sym = cl.decode(br)?;
        let (value, repeat) = match sym {
            0..=15 => (sym as u8, 1),
            16 => {
                if i == 0 {
                    return Err(corrupt("repeat with no previous length"));
                }
                (lengths[i - 1], 3 + br.bits(2)? as usize)
            }
            17 => (0, 3 + br.bits(3)? as usize),
            18 => (0, 11 + br.bits(7)? as usize),
            _ => return Err(corrupt("invalid code-length symbol")),
        };
        if i + repeat > lengths.len() {
            return Err(corrupt("code lengths overflow"));
        }
        lengths[i..i + repeat].fill(value);
        i += repeat;
    }
    if lengths[256] == 0 {
        return Err(corrupt("no end-of-block code"));
    }
    Ok((Huffman::new(&lengths[..hlit])?, Huffman::new(&lengths[hlit..])?))
}

fn inflate_block(
    br: &mut BitReader<'_>,
    lit: &Huffman,
    dist: &Huffman,
    out: &mut Vec<u8>,
    max_out: usize,
) -> Result<()> {
    loop {
        let sym = lit.decode(br)?;
        if sym < 256 {
            if out.len() >= max_out {
                return Err(Error::limit_exceeded(format!(
                    "deflate: output exceeds the limit of {max_out} bytes"
                )));
            }
            out.push(sym as u8);
            continue;
        }
        if sym == 256 {
            return Ok(());
        }
        let li = (sym - 257) as usize;
        if li >= 29 {
            return Err(corrupt("invalid length symbol"));
        }
        let len = LEN_BASE[li] as usize + br.bits(u32::from(LEN_EXTRA[li]))? as usize;
        let di = dist.decode(br)? as usize;
        if di >= 30 {
            return Err(corrupt("invalid distance symbol"));
        }
        let d = DIST_BASE[di] as usize + br.bits(u32::from(DIST_EXTRA[di]))? as usize;
        if d > out.len() {
            return Err(corrupt("distance reaches before the start of the output"));
        }
        if out.len() + len > max_out {
            return Err(Error::limit_exceeded(format!(
                "deflate: output exceeds the limit of {max_out} bytes"
            )));
        }
        let start = out.len() - d;
        for k in 0..len {
            let b = out[start + k];
            out.push(b);
        }
    }
}

/// Decompresses a zlib stream and verifies its Adler-32 trailer.
pub fn zlib_decompress(data: &[u8], max_out: usize) -> Result<Vec<u8>> {
    if data.len() < 6 {
        return Err(corrupt("zlib stream too short"));
    }
    let (cmf, flg) = (data[0], data[1]);
    if cmf & 0x0F != 8 || cmf >> 4 > 7 {
        return Err(corrupt("unsupported zlib compression method or window"));
    }
    if (u16::from(cmf) * 256 + u16::from(flg)) % 31 != 0 {
        return Err(corrupt("zlib header check failed"));
    }
    if flg & 0x20 != 0 {
        return Err(Error::unsupported("zlib preset dictionaries are not supported"));
    }
    let (out, used) = inflate(&data[2..], max_out)?;
    let trailer = data.get(2 + used..2 + used + 4).ok_or_else(|| corrupt("missing Adler-32 trailer"))?;
    let expected = u32::from_be_bytes([trailer[0], trailer[1], trailer[2], trailer[3]]);
    if adler32(&out) != expected {
        return Err(corrupt("Adler-32 mismatch"));
    }
    Ok(out)
}

// ---------------------------------------------------------------- encoder

/// Compression effort.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    /// Short match search.
    Fast,
    /// Balanced (default).
    Default,
    /// Long match search.
    Best,
}

impl Level {
    fn chain(self) -> usize {
        match self {
            Level::Fast => 8,
            Level::Default => 48,
            Level::Best => 512,
        }
    }
}

#[derive(Clone, Copy)]
enum Token {
    Literal(u8),
    Match { len: u16, dist: u16 },
}

struct BitWriter {
    out: Vec<u8>,
    buf: u64,
    count: u32,
}

impl BitWriter {
    fn put(&mut self, value: u32, n: u32) {
        self.buf |= u64::from(value) << self.count;
        self.count += n;
        while self.count >= 8 {
            self.out.push(self.buf as u8);
            self.buf >>= 8;
            self.count -= 8;
        }
    }

    fn align(&mut self) {
        if self.count > 0 {
            self.put(0, 8 - self.count);
        }
    }
}

/// Canonical codes (bit-reversed for LSB-first output) from lengths.
fn canonical_codes(lengths: &[u8]) -> Vec<u32> {
    let mut counts = [0u32; 16];
    for &l in lengths {
        counts[l as usize] += 1;
    }
    counts[0] = 0;
    let mut next = [0u32; 16];
    let mut code = 0;
    for len in 1..16 {
        code = (code + counts[len - 1]) << 1;
        next[len] = code;
    }
    lengths
        .iter()
        .map(|&l| {
            if l == 0 {
                return 0;
            }
            let c = next[l as usize];
            next[l as usize] += 1;
            c.reverse_bits() >> (32 - u32::from(l))
        })
        .collect()
}

fn length_symbol(len: u16) -> (usize, u32, u32) {
    let i = LEN_BASE.iter().rposition(|&b| b <= len).expect("length is at least 3");
    (257 + i, u32::from(len - LEN_BASE[i]), u32::from(LEN_EXTRA[i]))
}

fn distance_symbol(dist: u16) -> (usize, u32, u32) {
    let i = DIST_BASE.iter().rposition(|&b| b <= dist).expect("distance is at least 1");
    (i, u32::from(dist - DIST_BASE[i]), u32::from(DIST_EXTRA[i]))
}

fn lz77(data: &[u8], level: Level) -> Vec<Token> {
    const WINDOW: usize = 32_768;
    const HASH_BITS: u32 = 15;
    let chain_limit = level.chain();
    let mut head = vec![usize::MAX; 1 << HASH_BITS];
    let mut prev = vec![usize::MAX; WINDOW];
    let hash = |p: usize| -> usize {
        let v = u32::from(data[p]) << 16 | u32::from(data[p + 1]) << 8 | u32::from(data[p + 2]);
        (v.wrapping_mul(0x9E37_79B1) >> (32 - HASH_BITS)) as usize
    };
    let insert = |p: usize, head: &mut Vec<usize>, prev: &mut Vec<usize>| {
        if p + 3 <= data.len() {
            let h = hash(p);
            prev[p % WINDOW] = head[h];
            head[h] = p;
        }
    };
    let mut tokens = Vec::with_capacity(data.len() / 2);
    let mut i = 0;
    while i < data.len() {
        let mut best_len = 0usize;
        let mut best_dist = 0usize;
        if i + 3 <= data.len() {
            let max = (data.len() - i).min(258);
            let mut cand = head[hash(i)];
            let mut steps = 0;
            while cand != usize::MAX && i - cand <= WINDOW && steps < chain_limit {
                if data[cand + best_len.min(max - 1)] == data[i + best_len.min(max - 1)] {
                    let l = data[cand..].iter().zip(&data[i..i + max]).take_while(|(a, b)| a == b).count();
                    if l > best_len {
                        best_len = l;
                        best_dist = i - cand;
                        if l == max {
                            break;
                        }
                    }
                }
                let p = prev[cand % WINDOW];
                if p == usize::MAX || p >= cand {
                    break;
                }
                cand = p;
                steps += 1;
            }
        }
        if best_len >= 3 {
            tokens.push(Token::Match { len: best_len as u16, dist: best_dist as u16 });
            for p in i..i + best_len {
                insert(p, &mut head, &mut prev);
            }
            i += best_len;
        } else {
            tokens.push(Token::Literal(data[i]));
            insert(i, &mut head, &mut prev);
            i += 1;
        }
    }
    tokens
}

fn token_cost(tokens: &[Token], lit_len: &[u8], dist_len: &[u8]) -> u64 {
    let mut bits = u64::from(lit_len[256]);
    for t in tokens {
        match *t {
            Token::Literal(b) => bits += u64::from(lit_len[b as usize]),
            Token::Match { len, dist } => {
                let (ls, _, le) = length_symbol(len);
                let (ds, _, de) = distance_symbol(dist);
                bits += u64::from(lit_len[ls]) + u64::from(le) + u64::from(dist_len[ds]) + u64::from(de);
            }
        }
    }
    bits
}

fn write_tokens(w: &mut BitWriter, tokens: &[Token], lit_len: &[u8], dist_len: &[u8]) {
    let (lc, dc) = (canonical_codes(lit_len), canonical_codes(dist_len));
    for t in tokens {
        match *t {
            Token::Literal(b) => w.put(lc[b as usize], u32::from(lit_len[b as usize])),
            Token::Match { len, dist } => {
                let (ls, lv, le) = length_symbol(len);
                w.put(lc[ls], u32::from(lit_len[ls]));
                w.put(lv, le);
                let (ds, dv, de) = distance_symbol(dist);
                w.put(dc[ds], u32::from(dist_len[ds]));
                w.put(dv, de);
            }
        }
    }
    w.put(lc[256], u32::from(lit_len[256]));
}

/// Run-length encodes code lengths into (symbol, extra value) pairs.
fn encode_code_lengths(lengths: &[u8]) -> Vec<(u8, u8)> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < lengths.len() {
        let v = lengths[i];
        let run = lengths[i..].iter().take_while(|&&x| x == v).count();
        if v == 0 && run >= 3 {
            let r = run.min(138);
            if r >= 11 {
                out.push((18, (r - 11) as u8))
            } else {
                out.push((17, (r - 3) as u8))
            }
            i += r;
        } else if v != 0 && run >= 4 {
            out.push((v, 0));
            let r = (run - 1).min(6);
            out.push((16, (r - 3) as u8));
            i += 1 + r;
        } else {
            out.push((v, 0));
            i += 1;
        }
    }
    out
}

fn write_block(w: &mut BitWriter, tokens: &[Token], raw: &[u8], last: bool) {
    let mut lit_freq = vec![0u32; 286];
    let mut dist_freq = vec![0u32; 30];
    lit_freq[256] = 1;
    for t in tokens {
        match *t {
            Token::Literal(b) => lit_freq[b as usize] += 1,
            Token::Match { len, dist } => {
                lit_freq[length_symbol(len).0] += 1;
                dist_freq[distance_symbol(dist).0] += 1;
            }
        }
    }
    let lit_len = huffman_lengths(&lit_freq, 15);
    let dist_len = huffman_lengths(&dist_freq, 15);
    let hlit = (257..=286).rev().find(|&n| lit_len[n - 1] != 0).unwrap_or(257).max(257);
    let hdist = (1..=30).rev().find(|&n| dist_len[n - 1] != 0).unwrap_or(1).max(1);
    let mut all = lit_len[..hlit].to_vec();
    all.extend_from_slice(&dist_len[..hdist]);
    let cl_syms = encode_code_lengths(&all);
    let mut cl_freq = vec![0u32; 19];
    for &(s, _) in &cl_syms {
        cl_freq[s as usize] += 1;
    }
    let cl_len = huffman_lengths(&cl_freq, 7);
    let hclen = (4..=19).rev().find(|&n| cl_len[CL_ORDER[n - 1]] != 0).unwrap_or(4);
    let extra_bits = |s: u8| match s {
        16 => 2,
        17 => 3,
        18 => 7,
        _ => 0,
    };
    let header_bits: u64 = 14
        + 3 * hclen as u64
        + cl_syms.iter().map(|&(s, _)| u64::from(cl_len[s as usize]) + extra_bits(s)).sum::<u64>();
    let dynamic_bits = header_bits + token_cost(tokens, &lit_len, &dist_len);
    let fixed_lit = fixed_litlen_lengths();
    let fixed_dist = [5u8; 32];
    let fixed_bits = token_cost(tokens, &fixed_lit, &fixed_dist);
    let stored_bits = (raw.len() as u64 + 5 * raw.len().div_ceil(65_535).max(1) as u64) * 8;

    let flag = u32::from(last);
    if stored_bits <= dynamic_bits.min(fixed_bits) {
        let chunks: Vec<&[u8]> = if raw.is_empty() { vec![&[]] } else { raw.chunks(65_535).collect() };
        let n = chunks.len();
        for (k, chunk) in chunks.into_iter().enumerate() {
            w.put(if last && k + 1 == n { 1 } else { 0 }, 1);
            w.put(0, 2);
            w.align();
            let len = chunk.len() as u32;
            w.put(len, 16);
            w.put(!len & 0xFFFF, 16);
            for &b in chunk {
                w.put(u32::from(b), 8);
            }
        }
    } else if fixed_bits <= dynamic_bits {
        w.put(flag, 1);
        w.put(1, 2);
        write_tokens(w, tokens, &fixed_lit, &fixed_dist);
    } else {
        w.put(flag, 1);
        w.put(2, 2);
        w.put((hlit - 257) as u32, 5);
        w.put((hdist - 1) as u32, 5);
        w.put((hclen - 4) as u32, 4);
        for &i in CL_ORDER.iter().take(hclen) {
            w.put(u32::from(cl_len[i]), 3);
        }
        let cl_codes = canonical_codes(&cl_len);
        for &(s, extra) in &cl_syms {
            w.put(cl_codes[s as usize], u32::from(cl_len[s as usize]));
            w.put(u32::from(extra), extra_bits(s) as u32);
        }
        write_tokens(w, tokens, &lit_len, &dist_len);
    }
}

/// Compresses to a raw DEFLATE stream.
pub fn deflate(data: &[u8], level: Level) -> Vec<u8> {
    const BLOCK_TOKENS: usize = 1 << 15;
    let tokens = lz77(data, level);
    let mut w = BitWriter { out: Vec::with_capacity(data.len() / 2 + 64), buf: 0, count: 0 };
    if tokens.is_empty() {
        write_block(&mut w, &[], &[], true);
    }
    let mut pos = 0usize;
    let chunks: Vec<&[Token]> = tokens.chunks(BLOCK_TOKENS).collect();
    for (k, chunk) in chunks.iter().enumerate() {
        let span: usize = chunk
            .iter()
            .map(|t| match t {
                Token::Literal(_) => 1,
                Token::Match { len, .. } => *len as usize,
            })
            .sum();
        write_block(&mut w, chunk, &data[pos..pos + span], k + 1 == chunks.len());
        pos += span;
    }
    w.align();
    w.out
}

/// Compresses to a zlib stream.
pub fn zlib_compress(data: &[u8], level: Level) -> Vec<u8> {
    // CMF: deflate, 32 KiB window. FLG: chosen so the header is a multiple of 31.
    let cmf = 0x78u8;
    let flevel = match level {
        Level::Fast => 1u8,
        Level::Default => 2,
        Level::Best => 3,
    };
    let mut flg = flevel << 6;
    flg += (31 - ((u16::from(cmf) * 256 + u16::from(flg)) % 31) as u8) % 31;
    let mut out = vec![cmf, flg];
    out.extend(deflate(data, level));
    out.extend_from_slice(&adler32(data).to_be_bytes());
    out
}

#[cfg(test)]
mod tests;
