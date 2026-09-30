//! Deterministic pseudo-random numbers for reproducible seeding.
//!
//! State expansion uses the SplitMix64 mixing function. Generation uses
//! the xoshiro256** scheme. Both are small, well-understood public
//! algorithms. This generator is **not** cryptographically secure and must
//! never be used for security purposes.

/// SplitMix64 step: advances `state` and returns a well-mixed output.
fn splitmix64(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// A deterministic 64-bit generator (xoshiro256**).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rng {
    s: [u64; 4],
}

impl Rng {
    /// Seeds the generator from one 64-bit value.
    pub fn seed_from_u64(seed: u64) -> Rng {
        let mut sm = seed;
        let s = [splitmix64(&mut sm), splitmix64(&mut sm), splitmix64(&mut sm), splitmix64(&mut sm)];
        // SplitMix64 cannot produce four zero words from any seed, but the
        // all-zero state is a fixed point of xoshiro; guard it explicitly.
        debug_assert!(s.iter().any(|&w| w != 0));
        Rng { s }
    }

    /// Derives an independent stream from a base seed and a path of stream
    /// identifiers, e.g. `(global_seed, [epoch, sample_index])`. Different
    /// paths give unrelated streams; the same path always gives the same one.
    pub fn derive(seed: u64, path: &[u64]) -> Rng {
        let mut acc = seed;
        let mut h = splitmix64(&mut acc);
        for &id in path {
            let mut mixed = h ^ id.wrapping_mul(0xD6E8_FEB8_6659_FD93);
            h = splitmix64(&mut mixed);
        }
        Rng::seed_from_u64(h)
    }

    /// Next 64 random bits.
    pub fn next_u64(&mut self) -> u64 {
        let result = self.s[1].wrapping_mul(5).rotate_left(7).wrapping_mul(9);
        let t = self.s[1] << 17;
        self.s[2] ^= self.s[0];
        self.s[3] ^= self.s[1];
        self.s[1] ^= self.s[2];
        self.s[0] ^= self.s[3];
        self.s[2] ^= t;
        self.s[3] = self.s[3].rotate_left(45);
        result
    }

    /// Uniform `f64` in `[0, 1)` with 53 bits of precision.
    pub fn next_f64(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 * (1.0 / (1u64 << 53) as f64)
    }

    /// Uniform integer in `[0, n)`; `n` must be positive. Unbiased
    /// (rejection sampling).
    pub fn below(&mut self, n: u64) -> u64 {
        assert!(n > 0, "Rng::below requires a positive bound");
        // Reject the final partial block so every residue is equally likely.
        let zone = u64::MAX - (u64::MAX % n + 1) % n;
        loop {
            let v = self.next_u64();
            if v <= zone {
                return v % n;
            }
        }
    }

    /// Uniform `f64` in `[lo, hi)`.
    pub fn range_f64(&mut self, lo: f64, hi: f64) -> f64 {
        lo + (hi - lo) * self.next_f64()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splitmix_known_first_output() {
        // The first SplitMix64 output for state 0 is a widely published
        // reference value for this mixing function.
        let mut s = 0u64;
        assert_eq!(splitmix64(&mut s), 0xE220_A839_7B1D_CDAF);
    }

    #[test]
    fn same_seed_same_stream_different_seed_different_stream() {
        let a: Vec<u64> = {
            let mut r = Rng::seed_from_u64(7);
            (0..8).map(|_| r.next_u64()).collect()
        };
        let b: Vec<u64> = {
            let mut r = Rng::seed_from_u64(7);
            (0..8).map(|_| r.next_u64()).collect()
        };
        let c: Vec<u64> = {
            let mut r = Rng::seed_from_u64(8);
            (0..8).map(|_| r.next_u64()).collect()
        };
        assert_eq!(a, b);
        assert_ne!(a, c);
    }

    #[test]
    fn derived_streams_are_distinct_and_stable() {
        let first = |seed, path: &[u64]| Rng::derive(seed, path).next_u64();
        assert_eq!(first(1, &[2, 3]), first(1, &[2, 3]));
        assert_ne!(first(1, &[2, 3]), first(1, &[3, 2]));
        assert_ne!(first(1, &[2]), first(1, &[2, 0]));
        assert_ne!(first(1, &[2, 3]), first(2, &[2, 3]));
    }

    #[test]
    fn below_is_in_range_and_roughly_uniform() {
        let mut r = Rng::seed_from_u64(42);
        let mut counts = [0u32; 6];
        for _ in 0..60_000 {
            counts[r.below(6) as usize] += 1;
        }
        for c in counts {
            assert!((9_300..10_700).contains(&c), "{counts:?}");
        }
        assert_eq!(r.below(1), 0);
    }

    #[test]
    fn f64_in_unit_interval_with_plausible_mean() {
        let mut r = Rng::seed_from_u64(3);
        let n = 100_000;
        let mut sum = 0.0;
        for _ in 0..n {
            let v = r.next_f64();
            assert!((0.0..1.0).contains(&v));
            sum += v;
        }
        let mean = sum / f64::from(n);
        assert!((mean - 0.5).abs() < 0.01, "{mean}");
    }
}
