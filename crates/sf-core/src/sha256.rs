//! SHA-256 (FIPS 180-4), used to check the integrity of model and
//! checkpoint files.
//!
//! The round constants and initial hash values are not transcribed: they
//! are *derived* from their definition (the first 32 bits of the
//! fractional parts of the cube roots of the first 64 primes, and of the
//! square roots of the first 8 primes). The FIPS test vectors in the tests
//! confirm the derivation.
//!
//! This checks integrity against corruption. It does not authenticate the
//! author of a file; signatures are a separate, future mechanism.

use std::sync::OnceLock;

fn primes(n: usize) -> Vec<u64> {
    let mut out = Vec::with_capacity(n);
    let mut c = 2u64;
    while out.len() < n {
        if out.iter().take_while(|&&p| p * p <= c).all(|&p| c % p != 0) {
            out.push(c);
        }
        c += 1;
    }
    out
}

/// First 32 bits of the fractional part of `p^(1/root)`, computed exactly
/// with integer arithmetic: the largest `r` with `r^root ≤ p·2^(32·root)`,
/// taken modulo 2^32.
fn frac_bits(p: u64, root: u32) -> u32 {
    let target = u128::from(p) << (32 * root);
    let pow = |r: u128| -> Option<u128> { (1..root).try_fold(r, |acc, _| acc.checked_mul(r)) };
    let (mut lo, mut hi) = (0u128, 1u128 << (32 + 4));
    while lo < hi {
        let mid = (lo + hi).div_ceil(2);
        if pow(mid).is_some_and(|v| v <= target) { lo = mid } else { hi = mid - 1 }
    }
    lo as u32
}

struct Constants {
    k: [u32; 64],
    h0: [u32; 8],
}

fn constants() -> &'static Constants {
    static C: OnceLock<Constants> = OnceLock::new();
    C.get_or_init(|| {
        let p = primes(64);
        let mut k = [0u32; 64];
        let mut h0 = [0u32; 8];
        for i in 0..64 {
            k[i] = frac_bits(p[i], 3);
        }
        for i in 0..8 {
            h0[i] = frac_bits(p[i], 2);
        }
        Constants { k, h0 }
    })
}

/// Incremental SHA-256.
#[derive(Clone)]
pub struct Sha256 {
    h: [u32; 8],
    buf: [u8; 64],
    len: usize,
    total: u64,
}

impl Default for Sha256 {
    fn default() -> Self {
        Sha256 { h: constants().h0, buf: [0; 64], len: 0, total: 0 }
    }
}

impl Sha256 {
    /// A new hasher.
    pub fn new() -> Sha256 {
        Sha256::default()
    }

    fn compress(h: &mut [u32; 8], block: &[u8]) {
        let k = &constants().k;
        let mut w = [0u32; 64];
        for (i, chunk) in block.chunks(4).enumerate() {
            w[i] = u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = *h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ (!e & g);
            let t1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(k[i]).wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        for (x, v) in h.iter_mut().zip([a, b, c, d, e, f, g, hh]) {
            *x = x.wrapping_add(v);
        }
    }

    /// Feeds data.
    pub fn update(&mut self, mut data: &[u8]) {
        self.total += data.len() as u64;
        if self.len > 0 {
            let take = (64 - self.len).min(data.len());
            self.buf[self.len..self.len + take].copy_from_slice(&data[..take]);
            self.len += take;
            data = &data[take..];
            if self.len < 64 {
                return; // buffer still partial and input consumed
            }
            let block = self.buf;
            Self::compress(&mut self.h, &block);
            self.len = 0;
        }
        let mut chunks = data.chunks_exact(64);
        for block in &mut chunks {
            Self::compress(&mut self.h, block);
        }
        let rest = chunks.remainder();
        self.buf[..rest.len()].copy_from_slice(rest);
        self.len = rest.len();
    }

    /// Final 32-byte digest.
    pub fn finish(mut self) -> [u8; 32] {
        let bits = self.total.wrapping_mul(8);
        let mut pad = vec![0x80u8];
        let padded_len = (self.len + 1 + 8).div_ceil(64) * 64;
        pad.resize(padded_len - self.len - 8, 0);
        pad.extend(bits.to_be_bytes());
        let total = self.total;
        self.update(&pad);
        self.total = total;
        let mut out = [0u8; 32];
        for (i, v) in self.h.iter().enumerate() {
            out[4 * i..4 * i + 4].copy_from_slice(&v.to_be_bytes());
        }
        out
    }
}

/// One-shot SHA-256 as lowercase hex.
pub fn sha256_hex(data: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(data);
    h.finish().iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fips_180_test_vectors() {
        assert_eq!(sha256_hex(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        assert_eq!(sha256_hex(b""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        assert_eq!(
            sha256_hex(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
    }

    #[test]
    fn one_million_a() {
        let data = vec![b'a'; 1_000_000];
        assert_eq!(sha256_hex(&data), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
    }

    #[test]
    fn incremental_equals_one_shot() {
        let data: Vec<u8> = (0..10_000u32).map(|i| (i * 31 + 7) as u8).collect();
        for split in [0, 1, 63, 64, 65, 127, 5000, 9999] {
            let mut h = Sha256::new();
            h.update(&data[..split]);
            h.update(&data[split..]);
            let hex: String = h.finish().iter().map(|b| format!("{b:02x}")).collect();
            assert_eq!(hex, sha256_hex(&data));
        }
    }

    #[test]
    fn derived_constants_have_known_endpoints() {
        let c = constants();
        // FIPS 180-4 lists these as the first and last round constants and
        // the first initial hash word.
        assert_eq!(c.k[0], 0x428a_2f98);
        assert_eq!(c.k[63], 0xc671_78f2);
        assert_eq!(c.h0[0], 0x6a09_e667);
    }
}
