//! JPEG decoder: baseline and progressive Huffman-coded DCT (ITU-T T.81),
//! 8-bit precision, 1 or 3 components, any sampling factors up to 4,
//! restart intervals. Arithmetic coding, lossless, hierarchical, 12-bit
//! and CMYK files are rejected with `Unsupported`.

use sf_core::{Error, Limits, Result};

use super::dct::{ZIGZAG, idct};
use crate::image::{FileFormat, Image, ImageBuffer, ImageMeta, JpegInfo, Samples};

fn bad(what: impl std::fmt::Display) -> Error {
    Error::invalid_input(format!("jpeg: {what}"))
}

/// Upper bound on scans, against files that repeat scans forever.
const MAX_SCANS: usize = 1_000;

#[derive(Clone)]
struct Huffman {
    /// 9-bit lookup: (length << 8) | symbol, 0 = use slow path.
    fast: Vec<u16>,
    /// maxcode[l]: largest code of length l, or -1.
    maxcode: [i32; 18],
    /// valptr[l]: index of the first symbol of length l.
    valptr: [i32; 17],
    mincode: [i32; 17],
    symbols: Vec<u8>,
}

impl Huffman {
    fn new(counts: &[u8; 16], symbols: &[u8]) -> Result<Huffman> {
        let mut maxcode = [-1i32; 18];
        let mut valptr = [0i32; 17];
        let mut mincode = [0i32; 17];
        let mut fast = vec![0u16; 512];
        let (mut code, mut k) = (0i32, 0usize);
        for len in 1..=16usize {
            let n = counts[len - 1] as usize;
            valptr[len] = k as i32;
            mincode[len] = code;
            for _ in 0..n {
                if len <= 9 {
                    let shift = 9 - len;
                    let base = (code as usize) << shift;
                    for j in 0..(1usize << shift) {
                        fast[base + j] = ((len as u16) << 8) | u16::from(symbols[k]);
                    }
                }
                code += 1;
                k += 1;
            }
            if n > 0 {
                maxcode[len] = code - 1;
            }
            if code > (1 << len) {
                return Err(bad("over-subscribed Huffman table"));
            }
            code <<= 1;
        }
        maxcode[17] = i32::MAX;
        Ok(Huffman { fast, maxcode, valptr, mincode, symbols: symbols.to_vec() })
    }
}

/// MSB-first bit reader over entropy-coded data, handling byte stuffing
/// and stopping at markers.
struct Bits<'a> {
    data: &'a [u8],
    pos: usize,
    buf: u32,
    count: u32,
    /// Set once a marker is reached; further reads yield zero bits.
    marker: Option<u8>,
}

impl<'a> Bits<'a> {
    fn fill(&mut self) {
        while self.count <= 24 {
            let byte = if self.marker.is_some() || self.pos >= self.data.len() {
                0
            } else if self.data[self.pos] == 0xFF {
                let next = self.data.get(self.pos + 1).copied().unwrap_or(0);
                if next == 0x00 {
                    self.pos += 2;
                    0xFF
                } else {
                    self.marker = Some(next);
                    0
                }
            } else {
                self.pos += 1;
                self.data[self.pos - 1]
            };
            self.buf |= u32::from(byte) << (24 - self.count);
            self.count += 8;
        }
    }

    fn bit(&mut self) -> u32 {
        self.fill();
        let b = self.buf >> 31;
        self.buf <<= 1;
        self.count -= 1;
        b
    }

    fn receive(&mut self, n: u32) -> u32 {
        if n == 0 {
            return 0;
        }
        self.fill();
        let v = self.buf >> (32 - n);
        self.buf <<= n;
        self.count -= n;
        v
    }

    fn decode(&mut self, h: &Huffman) -> Result<u8> {
        self.fill();
        let e = h.fast[(self.buf >> 23) as usize];
        if e != 0 {
            let len = u32::from(e >> 8);
            self.buf <<= len;
            self.count -= len;
            return Ok(e as u8);
        }
        let mut code = 0i32;
        for len in 1..=16 {
            code = (code << 1) | self.bit() as i32;
            if code <= h.maxcode[len] {
                let idx = h.valptr[len] + code - h.mincode[len];
                return h.symbols.get(idx as usize).copied().ok_or_else(|| bad("invalid Huffman code"));
            }
        }
        Err(bad("invalid Huffman code"))
    }

    /// Resynchronises after a restart marker.
    fn restart(&mut self) -> Result<()> {
        self.buf = 0;
        self.count = 0;
        match self.marker.take() {
            Some(m @ 0xD0..=0xD7) => {
                let _ = m;
                self.pos += 2;
                Ok(())
            }
            _ => {
                // Tolerate missing restart markers only if we are exactly
                // at one after byte-aligning.
                if self.pos + 1 < self.data.len()
                    && self.data[self.pos] == 0xFF
                    && (0xD0..=0xD7).contains(&self.data[self.pos + 1])
                {
                    self.pos += 2;
                    Ok(())
                } else {
                    Err(bad("expected a restart marker"))
                }
            }
        }
    }
}

fn extend(v: u32, t: u32) -> i32 {
    if t == 0 {
        0
    } else if v < (1 << (t - 1)) {
        v as i32 - (1 << t) + 1
    } else {
        v as i32
    }
}

struct Component {
    id: u8,
    h: usize,
    v: usize,
    tq: usize,
    /// Blocks per line / column covering the MCU grid.
    bw: usize,
    bh: usize,
    /// Blocks actually covering the component's own size.
    cw: usize,
    ch: usize,
    coef: Vec<i32>,
    dc_pred: i32,
}

struct Frame {
    width: usize,
    height: usize,
    progressive: bool,
    comps: Vec<Component>,
    hmax: usize,
    vmax: usize,
    mcux: usize,
    mcuy: usize,
}

struct ScanComp {
    idx: usize,
    dc: usize,
    ac: usize,
}

#[allow(clippy::too_many_arguments)]
fn decode_block(
    bits: &mut Bits<'_>,
    comp: &mut Component,
    block: usize,
    dc: &Huffman,
    ac: &Huffman,
    ss: usize,
    se: usize,
    ah: u32,
    al: u32,
    progressive: bool,
    eobrun: &mut u32,
) -> Result<()> {
    let coef = &mut comp.coef[block * 64..block * 64 + 64];
    if !progressive {
        let t = u32::from(bits.decode(dc)?);
        if t > 11 {
            return Err(bad("DC magnitude out of range"));
        }
        comp.dc_pred += extend(bits.receive(t), t);
        coef[0] = comp.dc_pred;
        let mut k = 1;
        while k < 64 {
            let rs = bits.decode(ac)?;
            let (r, s) = (usize::from(rs >> 4), u32::from(rs & 15));
            if s == 0 {
                if r == 15 {
                    k += 16;
                    continue;
                }
                break;
            }
            k += r;
            if k > 63 {
                return Err(bad("AC coefficient index out of range"));
            }
            coef[ZIGZAG[k]] = extend(bits.receive(s), s);
            k += 1;
        }
        return Ok(());
    }
    if ss == 0 {
        // DC scans.
        if ah == 0 {
            let t = u32::from(bits.decode(dc)?);
            if t > 11 {
                return Err(bad("DC magnitude out of range"));
            }
            comp.dc_pred += extend(bits.receive(t), t);
            coef[0] = comp.dc_pred * (1 << al);
        } else if bits.bit() == 1 {
            coef[0] |= 1 << al;
        }
        return Ok(());
    }
    if ah == 0 {
        // AC first pass.
        if *eobrun > 0 {
            *eobrun -= 1;
            return Ok(());
        }
        let mut k = ss;
        while k <= se {
            let rs = bits.decode(ac)?;
            let (r, s) = (u32::from(rs >> 4), u32::from(rs & 15));
            if s == 0 {
                if r < 15 {
                    *eobrun = (1 << r) - 1;
                    if r > 0 {
                        *eobrun += bits.receive(r);
                    }
                    break;
                }
                k += 16;
                continue;
            }
            k += r as usize;
            if k > 63 {
                return Err(bad("AC coefficient index out of range"));
            }
            coef[ZIGZAG[k]] = extend(bits.receive(s), s) * (1 << al);
            k += 1;
        }
        return Ok(());
    }
    // AC refinement.
    let p1 = 1i32 << al;
    let m1 = -1i32 << al;
    let refine = |bits: &mut Bits<'_>, c: &mut i32| {
        if bits.bit() == 1 && (*c & p1) == 0 {
            *c += if *c >= 0 { p1 } else { m1 };
        }
    };
    let mut k = ss;
    if *eobrun == 0 {
        while k <= se {
            let rs = bits.decode(ac)?;
            let (mut r, s) = (u32::from(rs >> 4), u32::from(rs & 15));
            let mut value = 0;
            if s == 0 {
                if r < 15 {
                    *eobrun = 1 << r;
                    if r > 0 {
                        *eobrun += bits.receive(r);
                    }
                    break;
                }
            } else {
                if s != 1 {
                    return Err(bad("invalid refinement magnitude"));
                }
                value = if bits.bit() == 1 { p1 } else { m1 };
            }
            while k <= se {
                let z = ZIGZAG[k];
                if coef[z] != 0 {
                    refine(bits, &mut coef[z]);
                } else {
                    if r == 0 {
                        if value != 0 {
                            coef[z] = value;
                        }
                        k += 1;
                        break;
                    }
                    r -= 1;
                }
                k += 1;
            }
        }
    }
    if *eobrun > 0 {
        while k <= se {
            let z = ZIGZAG[k];
            if coef[z] != 0 {
                refine(bits, &mut coef[z]);
            }
            k += 1;
        }
        *eobrun -= 1;
    }
    Ok(())
}

fn u16_at(d: &[u8], p: usize) -> Result<usize> {
    d.get(p..p + 2)
        .map(|b| usize::from(u16::from_be_bytes([b[0], b[1]])))
        .ok_or_else(|| bad("truncated segment"))
}

/// Decodes a JPEG file to 8-bit grey or RGB.
pub fn decode(data: &[u8], limits: &Limits) -> Result<Image> {
    if !data.starts_with(&[0xFF, 0xD8]) {
        return Err(bad("missing SOI marker"));
    }
    let mut pos = 2;
    let mut qt: [Option<[u16; 64]>; 4] = [None; 4];
    let mut dc_tables: [Option<Huffman>; 4] = [None, None, None, None];
    let mut ac_tables: [Option<Huffman>; 4] = [None, None, None, None];
    let mut frame: Option<Frame> = None;
    let mut restart = 0usize;
    let mut meta = ImageMeta::default();
    let mut info = JpegInfo::default();
    let mut icc_chunks: Vec<(u8, Vec<u8>)> = Vec::new();
    let mut adobe_transform: Option<u8> = None;
    let mut scans = 0usize;

    loop {
        // Find the next marker, skipping fill bytes.
        if pos >= data.len() {
            return Err(bad("missing EOI marker"));
        }
        if data[pos] != 0xFF {
            return Err(bad(format!("expected a marker at byte {pos}")));
        }
        while pos < data.len() && data[pos] == 0xFF {
            pos += 1;
        }
        let marker = *data.get(pos).ok_or_else(|| bad("truncated marker"))?;
        pos += 1;
        match marker {
            0xD9 => break,
            0xD0..=0xD7 | 0x01 => continue,
            _ => {}
        }
        let len = u16_at(data, pos)?;
        if len < 2 {
            return Err(bad("segment length too small"));
        }
        let seg = data.get(pos + 2..pos + len).ok_or_else(|| bad("truncated segment"))?;
        let seg_end = pos + len;
        match marker {
            0xDB => {
                let mut p = 0;
                while p < seg.len() {
                    let (pq, tq) = (seg[p] >> 4, usize::from(seg[p] & 15));
                    if tq > 3 || pq > 1 {
                        return Err(bad("invalid quantisation table"));
                    }
                    let n = if pq == 1 { 128 } else { 64 };
                    let body =
                        seg.get(p + 1..p + 1 + n).ok_or_else(|| bad("truncated quantisation table"))?;
                    let mut t = [0u16; 64];
                    for (i, v) in t.iter_mut().enumerate() {
                        *v = if pq == 1 {
                            u16::from_be_bytes([body[2 * i], body[2 * i + 1]])
                        } else {
                            u16::from(body[i])
                        };
                    }
                    info.quant_tables.retain(|(id, _)| usize::from(*id) != tq);
                    info.quant_tables.push((tq as u8, t.to_vec()));
                    qt[tq] = Some(t);
                    p += 1 + n;
                }
            }
            0xC4 => {
                let mut p = 0;
                while p < seg.len() {
                    let (tc, th) = (seg[p] >> 4, usize::from(seg[p] & 15));
                    if tc > 1 || th > 3 {
                        return Err(bad("invalid Huffman table id"));
                    }
                    let counts: [u8; 16] = seg
                        .get(p + 1..p + 17)
                        .ok_or_else(|| bad("truncated Huffman table"))?
                        .try_into()
                        .expect("16 bytes");
                    let total: usize = counts.iter().map(|&c| usize::from(c)).sum();
                    if total > 256 {
                        return Err(bad("too many Huffman symbols"));
                    }
                    let syms =
                        seg.get(p + 17..p + 17 + total).ok_or_else(|| bad("truncated Huffman table"))?;
                    let table = Huffman::new(&counts, syms)?;
                    if tc == 0 {
                        dc_tables[th] = Some(table);
                    } else {
                        ac_tables[th] = Some(table);
                    }
                    p += 17 + total;
                }
            }
            0xDD => restart = u16_at(data, pos + 2)?,
            0xE1 if seg.starts_with(b"Exif\0\0") => meta.orientation = crate::exif::orientation(&seg[6..]),
            0xE2 if seg.starts_with(b"ICC_PROFILE\0") && seg.len() >= 14 => {
                let total: usize = icc_chunks.iter().map(|c| c.1.len()).sum::<usize>() + seg.len() - 14;
                if total > limits.max_icc_bytes as usize {
                    return Err(Error::limit_exceeded("jpeg: ICC profile exceeds the limit"));
                }
                icc_chunks.push((seg[12], seg[14..].to_vec()));
            }
            0xEE if seg.starts_with(b"Adobe") && seg.len() >= 12 => adobe_transform = Some(seg[11]),
            0xC0..=0xC2 => {
                if frame.is_some() {
                    return Err(bad("more than one frame"));
                }
                frame = Some(parse_frame(seg, marker == 0xC2, limits, &mut info)?);
            }
            0xC3 | 0xC5..=0xC7 | 0xC9..=0xCB | 0xCD..=0xCF => {
                return Err(Error::unsupported(
                    "jpeg: lossless, hierarchical or arithmetic-coded files are not supported",
                ));
            }
            0xDA => {
                scans += 1;
                if scans > MAX_SCANS {
                    return Err(Error::limit_exceeded("jpeg: too many scans"));
                }
                let f = frame.as_mut().ok_or_else(|| bad("scan before frame header"))?;
                let used = decode_scan(f, seg, &data[seg_end..], restart, &dc_tables, &ac_tables)?;
                pos = seg_end + used;
                continue;
            }
            _ => {}
        }
        pos = seg_end;
    }

    let f = frame.ok_or_else(|| bad("no frame header"))?;
    if !icc_chunks.is_empty() {
        icc_chunks.sort_by_key(|c| c.0);
        meta.icc_profile = Some(icc_chunks.into_iter().flat_map(|c| c.1).collect());
    }
    let buffer = reconstruct(&f, &qt, adobe_transform)?;
    meta.jpeg = Some(info);
    Ok(Image { buffer, meta, format: FileFormat::Jpeg })
}

fn parse_frame(seg: &[u8], progressive: bool, limits: &Limits, info: &mut JpegInfo) -> Result<Frame> {
    if seg.len() < 6 {
        return Err(bad("truncated frame header"));
    }
    if seg[0] != 8 {
        return Err(Error::unsupported(format!("jpeg: {}-bit precision is not supported", seg[0])));
    }
    let height = u16_at(seg, 1)?;
    let width = u16_at(seg, 3)?;
    let n = usize::from(seg[5]);
    if height == 0 {
        return Err(Error::unsupported("jpeg: height defined by a later DNL marker is not supported"));
    }
    if n != 1 && n != 3 {
        return Err(Error::unsupported(format!(
            "jpeg: {n} components (only greyscale and 3-component colour)"
        )));
    }
    limits.check_decoded_bytes(width as u32, height as u32, n as u32 * 3)?;
    let mut comps = Vec::with_capacity(n);
    for i in 0..n {
        let c = seg.get(6 + i * 3..9 + i * 3).ok_or_else(|| bad("truncated frame header"))?;
        let (h, v) = (usize::from(c[1] >> 4), usize::from(c[1] & 15));
        if !(1..=4).contains(&h) || !(1..=4).contains(&v) || c[2] > 3 {
            return Err(bad("invalid component parameters"));
        }
        info.sampling.push((h as u8, v as u8));
        comps.push(Component {
            id: c[0],
            h,
            v,
            tq: usize::from(c[2]),
            bw: 0,
            bh: 0,
            cw: 0,
            ch: 0,
            coef: Vec::new(),
            dc_pred: 0,
        });
    }
    info.progressive = progressive;
    let hmax = comps.iter().map(|c| c.h).max().expect("components");
    let vmax = comps.iter().map(|c| c.v).max().expect("components");
    let mcux = width.div_ceil(8 * hmax);
    let mcuy = height.div_ceil(8 * vmax);
    for c in &mut comps {
        c.bw = mcux * c.h;
        c.bh = mcuy * c.v;
        c.cw = (width * c.h).div_ceil(hmax).div_ceil(8);
        c.ch = (height * c.v).div_ceil(vmax).div_ceil(8);
        c.coef = vec![0; c.bw * c.bh * 64];
    }
    Ok(Frame { width, height, progressive, comps, hmax, vmax, mcux, mcuy })
}

/// Decodes one scan; returns the number of entropy-coded bytes consumed.
fn decode_scan(
    f: &mut Frame,
    seg: &[u8],
    data: &[u8],
    restart: usize,
    dc_tables: &[Option<Huffman>; 4],
    ac_tables: &[Option<Huffman>; 4],
) -> Result<usize> {
    let ns = usize::from(*seg.first().ok_or_else(|| bad("empty scan header"))?);
    if ns == 0 || ns > 4 || seg.len() < 1 + 2 * ns + 3 {
        return Err(bad("invalid scan header"));
    }
    let mut sc = Vec::with_capacity(ns);
    for i in 0..ns {
        let id = seg[1 + 2 * i];
        let idx = f
            .comps
            .iter()
            .position(|c| c.id == id)
            .ok_or_else(|| bad("scan references an unknown component"))?;
        let t = seg[2 + 2 * i];
        sc.push(ScanComp { idx, dc: usize::from(t >> 4), ac: usize::from(t & 15) });
    }
    let p = 1 + 2 * ns;
    let (ss, se, ah, al) = (
        usize::from(seg[p]),
        usize::from(seg[p + 1]),
        u32::from(seg[p + 2] >> 4),
        u32::from(seg[p + 2] & 15),
    );
    if f.progressive {
        if ss > se || se > 63 || al > 13 || (ss == 0 && se != 0) || (ss > 0 && ns != 1) {
            return Err(bad("invalid progressive scan parameters"));
        }
    } else if ss != 0 || se != 63 || ah != 0 || al != 0 {
        return Err(bad("invalid baseline scan parameters"));
    }
    let empty = || bad("scan uses an undefined Huffman table");
    let dummy = Huffman::new(&[0; 16], &[])?;
    let tables: Vec<(&Huffman, &Huffman)> = sc
        .iter()
        .map(|s| {
            let need_dc = ss == 0 && ah == 0 || !f.progressive;
            let need_ac = se > 0;
            let dc = if need_dc {
                dc_tables.get(s.dc).and_then(Option::as_ref).ok_or_else(empty)?
            } else {
                &dummy
            };
            let ac = if need_ac {
                ac_tables.get(s.ac).and_then(Option::as_ref).ok_or_else(empty)?
            } else {
                &dummy
            };
            Ok((dc, ac))
        })
        .collect::<Result<_>>()?;

    for s in &sc {
        f.comps[s.idx].dc_pred = 0;
    }
    let mut bits = Bits { data, pos: 0, buf: 0, count: 0, marker: None };
    let mut eobrun = 0u32;
    let progressive = f.progressive;
    let mut units_done = 0usize;
    let mut unit_boundary = |bits: &mut Bits<'_>, comps: &mut [Component], eob: &mut u32| -> Result<()> {
        units_done += 1;
        if restart > 0 && units_done.is_multiple_of(restart) {
            bits.restart()?;
            for c in comps.iter_mut() {
                c.dc_pred = 0;
            }
            *eob = 0;
        }
        Ok(())
    };

    if ns == 1 {
        // Non-interleaved: the component's own block grid.
        let ci = sc[0].idx;
        let (cw, ch, bw) = (f.comps[ci].cw, f.comps[ci].ch, f.comps[ci].bw);
        let total = cw * ch;
        for i in 0..total {
            let (by, bx) = (i / cw, i % cw);
            decode_block(
                &mut bits,
                &mut f.comps[ci],
                by * bw + bx,
                tables[0].0,
                tables[0].1,
                ss,
                se,
                ah,
                al,
                progressive,
                &mut eobrun,
            )?;
            if i + 1 < total {
                unit_boundary(&mut bits, &mut f.comps, &mut eobrun)?;
            }
        }
    } else {
        let total = f.mcux * f.mcuy;
        for m in 0..total {
            let (my, mx) = (m / f.mcux, m % f.mcux);
            for (s, t) in sc.iter().zip(&tables) {
                let c = &mut f.comps[s.idx];
                for v in 0..c.v {
                    for h in 0..c.h {
                        let block = (my * c.v + v) * c.bw + mx * c.h + h;
                        decode_block(
                            &mut bits,
                            c,
                            block,
                            t.0,
                            t.1,
                            ss,
                            se,
                            ah,
                            al,
                            progressive,
                            &mut eobrun,
                        )?;
                    }
                }
            }
            if m + 1 < total {
                unit_boundary(&mut bits, &mut f.comps, &mut eobrun)?;
            }
        }
    }
    // Consumed bytes: up to the next marker.
    let mut end = bits.pos;
    while end + 1 < data.len()
        && !(data[end] == 0xFF && data[end + 1] != 0x00 && !(0xD0..=0xD7).contains(&data[end + 1]))
    {
        end += 1;
    }
    Ok(end)
}

fn reconstruct(f: &Frame, qt: &[Option<[u16; 64]>; 4], adobe: Option<u8>) -> Result<ImageBuffer> {
    // Dequantise and inverse-transform each component into a padded plane.
    let mut planes: Vec<(Vec<u8>, usize, usize)> = Vec::with_capacity(f.comps.len());
    for c in &f.comps {
        let q = qt[c.tq].ok_or_else(|| bad("component uses an undefined quantisation table"))?;
        let (pw, ph) = (c.bw * 8, c.bh * 8);
        let mut plane = vec![0u8; pw * ph];
        let mut block = [0f32; 64];
        let mut out = [0f32; 64];
        for by in 0..c.bh {
            for bx in 0..c.bw {
                let coef = &c.coef[(by * c.bw + bx) * 64..][..64];
                for k in 0..64 {
                    block[ZIGZAG[k]] = (coef[ZIGZAG[k]] * i32::from(q[k])) as f32;
                }
                idct(&block, &mut out);
                for y in 0..8 {
                    for x in 0..8 {
                        plane[(by * 8 + y) * pw + bx * 8 + x] =
                            (out[y * 8 + x] + 128.0).round().clamp(0.0, 255.0) as u8;
                    }
                }
            }
        }
        planes.push((plane, pw, ph));
    }
    let (w, h) = (f.width, f.height);
    if f.comps.len() == 1 {
        let (plane, pw, _) = &planes[0];
        let mut out = Vec::with_capacity(w * h);
        for y in 0..h {
            out.extend_from_slice(&plane[y * pw..y * pw + w]);
        }
        return ImageBuffer::new(w as u32, h as u32, 1, Samples::U8(out));
    }
    // Upsample every component to full resolution (centre-aligned linear
    // interpolation for subsampled components).
    let full: Vec<Vec<f32>> = f
        .comps
        .iter()
        .zip(&planes)
        .map(|(c, (plane, pw, ph))| upsample(plane, *pw, *ph, f.hmax / c.h, f.vmax / c.v, w, h))
        .collect();
    // Without an Adobe marker, component ids 'R','G','B' signal RGB data;
    // otherwise three components are YCbCr (JFIF).
    let ids: Vec<u8> = f.comps.iter().map(|c| c.id).collect();
    let transform = match adobe {
        Some(t) => t != 0,
        None => ids != b"RGB",
    };
    let mut out = Vec::with_capacity(w * h * 3);
    for ((&a, &b), &c) in full[0].iter().zip(&full[1]).zip(&full[2]) {
        let (r, g, bl) = if transform {
            let (cb, cr) = (b - 128.0, c - 128.0);
            (a + 1.402 * cr, a - 0.344_136 * cb - 0.714_136 * cr, a + 1.772 * cb)
        } else {
            (a, b, c)
        };
        out.extend([r, g, bl].map(|v| v.round().clamp(0.0, 255.0) as u8));
    }
    ImageBuffer::new(w as u32, h as u32, 3, Samples::U8(out))
}

fn upsample(plane: &[u8], pw: usize, ph: usize, sx: usize, sy: usize, w: usize, h: usize) -> Vec<f32> {
    let mut out = vec![0f32; w * h];
    if sx == 1 && sy == 1 {
        for y in 0..h {
            for x in 0..w {
                out[y * w + x] = f32::from(plane[y * pw + x]);
            }
        }
        return out;
    }
    // Source sample i covers output [i·s, (i+1)·s); its centre is at
    // (i + 0.5)·s − 0.5 in output coordinates.
    let sample = |x: isize, y: isize| -> f32 {
        let xx = x.clamp(0, pw as isize - 1) as usize;
        let yy = y.clamp(0, ph as isize - 1) as usize;
        f32::from(plane[yy * pw + xx])
    };
    for y in 0..h {
        let fy = (y as f32 + 0.5) / sy as f32 - 0.5;
        let y0 = fy.floor();
        let ty = fy - y0;
        for x in 0..w {
            let fx = (x as f32 + 0.5) / sx as f32 - 0.5;
            let x0 = fx.floor();
            let tx = fx - x0;
            let (xi, yi) = (x0 as isize, y0 as isize);
            let top = sample(xi, yi) * (1.0 - tx) + sample(xi + 1, yi) * tx;
            let bottom = sample(xi, yi + 1) * (1.0 - tx) + sample(xi + 1, yi + 1) * tx;
            out[y * w + x] = top * (1.0 - ty) + bottom * ty;
        }
    }
    out
}
