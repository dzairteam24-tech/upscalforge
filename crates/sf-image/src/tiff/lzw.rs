//! TIFF LZW decoding: MSB-first codes of 9–12 bits, clear code 256,
//! end-of-information 257, and the TIFF "early change" rule (the code
//! width grows one code before the table would overflow the current width).

use sf_core::{Error, Result};

const CLEAR: u16 = 256;
const EOI: u16 = 257;

/// Decodes up to `expected` bytes.
pub fn decode(src: &[u8], expected: usize) -> Result<Vec<u8>> {
    let bad = |w: &str| Error::invalid_input(format!("tiff: LZW {w}"));
    let mut prefix = [0u16; 4096];
    let mut suffix = [0u8; 4096];
    let mut length = [0u16; 4096];
    for i in 0..256 {
        suffix[i] = i as u8;
        length[i] = 1;
    }
    let mut out: Vec<u8> = Vec::with_capacity(expected);
    let (mut acc, mut nbits, mut pos) = (0u32, 0u32, 0usize);
    let mut width = 9u32;
    let mut next = 258u16;
    let mut prev: Option<u16> = None;
    let mut scratch = [0u8; 4096];

    // Writes the string for `code` into `scratch`, returning its length.
    let spell = |code: u16,
                 scratch: &mut [u8; 4096],
                 prefix: &[u16; 4096],
                 suffix: &[u8; 4096],
                 length: &[u16; 4096]| {
        let n = length[code as usize] as usize;
        let mut c = code;
        for i in (0..n).rev() {
            scratch[i] = suffix[c as usize];
            c = prefix[c as usize];
        }
        n
    };

    while out.len() < expected {
        while nbits < width {
            if pos >= src.len() {
                return Ok(out); // tolerate a missing EOI at the end of data
            }
            acc = (acc << 8) | u32::from(src[pos]);
            pos += 1;
            nbits += 8;
        }
        let code = ((acc >> (nbits - width)) & ((1 << width) - 1)) as u16;
        nbits -= width;
        if code == EOI {
            break;
        }
        if code == CLEAR {
            width = 9;
            next = 258;
            prev = None;
            continue;
        }
        let Some(p) = prev else {
            if code > 255 {
                return Err(bad("stream starts with a non-literal code"));
            }
            out.push(code as u8);
            prev = Some(code);
            continue;
        };
        let (n, first) = if code < next {
            let n = spell(code, &mut scratch, &prefix, &suffix, &length);
            (n, scratch[0])
        } else if code == next {
            let n = spell(p, &mut scratch, &prefix, &suffix, &length);
            let first = scratch[0];
            scratch[n] = first;
            (n + 1, first)
        } else {
            return Err(bad("code out of range"));
        };
        out.extend_from_slice(&scratch[..n.min(expected - out.len())]);
        if next < 4096 {
            prefix[next as usize] = p;
            suffix[next as usize] = first;
            length[next as usize] = length[p as usize] + 1;
            next += 1;
        }
        if u32::from(next) + 1 >= (1 << width) && width < 12 {
            width += 1;
        }
        prev = Some(code);
    }
    Ok(out)
}

#[cfg(test)]
pub(super) mod test_encoder {
    //! A minimal LZW encoder used only to produce test inputs.

    use std::collections::HashMap;

    pub fn encode(data: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        let (mut acc, mut nbits) = (0u64, 0u32);
        let mut put = |code: u32, width: u32, out: &mut Vec<u8>| {
            acc = (acc << width) | u64::from(code);
            nbits += width;
            while nbits >= 8 {
                out.push((acc >> (nbits - 8)) as u8);
                nbits -= 8;
            }
        };
        let mut dict: HashMap<Vec<u8>, u32> = HashMap::new();
        let mut next = 258u32;
        let mut width = 9u32;
        put(256, width, &mut out);
        let mut cur: Vec<u8> = Vec::new();
        for &b in data {
            let mut cand = cur.clone();
            cand.push(b);
            if cand.len() == 1 || dict.contains_key(&cand) {
                cur = cand;
                continue;
            }
            let code = if cur.len() == 1 { u32::from(cur[0]) } else { dict[&cur] };
            put(code, width, &mut out);
            dict.insert(cand, next);
            next += 1;
            // The decoder's table lags one entry behind the encoder's, so
            // the encoder's early-change point is one entry later.
            if next >= (1 << width) && width < 12 {
                width += 1;
            }
            if next >= 4094 {
                put(256, width, &mut out);
                dict.clear();
                next = 258;
                width = 9;
            }
            cur = vec![b];
        }
        if !cur.is_empty() {
            let code = if cur.len() == 1 { u32::from(cur[0]) } else { dict[&cur] };
            put(code, width, &mut out);
        }
        put(257, width, &mut out);
        put(0, 7, &mut out);
        out
    }
}
