//! CRC-32 (IEEE 802.3, reflected, polynomial 0xEDB88320) and Adler-32.

const fn crc_table() -> [u32; 256] {
    let mut table = [0u32; 256];
    let mut i = 0;
    while i < 256 {
        let mut c = i as u32;
        let mut k = 0;
        while k < 8 {
            c = if c & 1 != 0 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 };
            k += 1;
        }
        table[i] = c;
        i += 1;
    }
    table
}

static CRC_TABLE: [u32; 256] = crc_table();

/// Incremental CRC-32.
#[derive(Debug, Clone, Copy)]
pub struct Crc32(u32);

impl Default for Crc32 {
    fn default() -> Self {
        Crc32(0xFFFF_FFFF)
    }
}

impl Crc32 {
    /// Feeds bytes.
    pub fn update(&mut self, data: &[u8]) {
        let mut c = self.0;
        for &b in data {
            c = CRC_TABLE[((c ^ u32::from(b)) & 0xFF) as usize] ^ (c >> 8);
        }
        self.0 = c;
    }

    /// Final checksum.
    pub fn finish(self) -> u32 {
        self.0 ^ 0xFFFF_FFFF
    }
}

/// One-shot CRC-32.
pub fn crc32(data: &[u8]) -> u32 {
    let mut c = Crc32::default();
    c.update(data);
    c.finish()
}

/// Incremental Adler-32 as used by zlib.
#[derive(Debug, Clone, Copy)]
pub struct Adler32 {
    a: u32,
    b: u32,
}

impl Default for Adler32 {
    fn default() -> Self {
        Adler32 { a: 1, b: 0 }
    }
}

impl Adler32 {
    /// Feeds bytes.
    pub fn update(&mut self, data: &[u8]) {
        const MOD: u32 = 65_521;
        // 5552 is the largest block length for which the sums cannot overflow.
        for chunk in data.chunks(5552) {
            for &x in chunk {
                self.a += u32::from(x);
                self.b += self.a;
            }
            self.a %= MOD;
            self.b %= MOD;
        }
    }

    /// Final checksum.
    pub fn finish(self) -> u32 {
        (self.b << 16) | self.a
    }
}

/// One-shot Adler-32.
pub fn adler32(data: &[u8]) -> u32 {
    let mut s = Adler32::default();
    s.update(data);
    s.finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_values() {
        // Standard check value for the ASCII digits "123456789".
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
        assert_eq!(crc32(b""), 0);
        assert_eq!(adler32(b""), 1);
        // Hand computation: a = 1+97+98+99 = 295, b = 98+196+295 = 589.
        assert_eq!(adler32(b"abc"), (589 << 16) | 295);
    }

    #[test]
    fn adler_long_input_matches_naive_modular_sum() {
        let data: Vec<u8> = (0..100_000u32).map(|i| (i * 7 + 3) as u8).collect();
        let (mut a, mut b) = (1u64, 0u64);
        for &x in &data {
            a = (a + u64::from(x)) % 65_521;
            b = (b + a) % 65_521;
        }
        assert_eq!(adler32(&data), ((b << 16) | a) as u32);
    }
}
