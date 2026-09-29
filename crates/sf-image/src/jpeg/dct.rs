//! 8×8 DCT helpers shared by the JPEG decoder and encoder.

/// Zig-zag scan order: `ZIGZAG[k]` is the natural (row-major) index of
/// the k-th coefficient in scan order.
pub const ZIGZAG: [usize; 64] = zigzag();

const fn zigzag() -> [usize; 64] {
    let mut out = [0usize; 64];
    let (mut x, mut y) = (0i32, 0i32);
    let mut k = 0;
    while k < 64 {
        out[k] = (y * 8 + x) as usize;
        // Even diagonals run up-right, odd diagonals down-left.
        if (x + y) % 2 == 0 {
            if x == 7 {
                y += 1;
            } else if y == 0 {
                x += 1;
            } else {
                x += 1;
                y -= 1;
            }
        } else if y == 7 {
            x += 1;
        } else if x == 0 {
            y += 1;
        } else {
            x -= 1;
            y += 1;
        }
        k += 1;
    }
    out
}

/// Basis matrix `B[u][x] = C(u)/2 · cos((2x+1)uπ/16)`, `C(0) = 1/√2`.
fn basis() -> [[f32; 8]; 8] {
    let mut b = [[0f32; 8]; 8];
    for (u, row) in b.iter_mut().enumerate() {
        let c = if u == 0 { std::f64::consts::FRAC_1_SQRT_2 } else { 1.0 };
        for (x, v) in row.iter_mut().enumerate() {
            *v = (c / 2.0 * ((2 * x + 1) as f64 * u as f64 * std::f64::consts::PI / 16.0).cos()) as f32;
        }
    }
    b
}

thread_local! {
    static BASIS: [[f32; 8]; 8] = basis();
}

/// Inverse DCT of a dequantised block (natural order). Returns samples
/// before the +128 level shift.
pub fn idct(coef: &[f32; 64], out: &mut [f32; 64]) {
    BASIS.with(|b| {
        let mut tmp = [0f32; 64];
        // Columns: tmp[y][u] = Σ_v B[v][y] · F[v][u]
        for u in 0..8 {
            for y in 0..8 {
                let mut s = 0.0;
                for v in 0..8 {
                    s += b[v][y] * coef[v * 8 + u];
                }
                tmp[y * 8 + u] = s;
            }
        }
        // Rows: out[y][x] = Σ_u B[u][x] · tmp[y][u]
        for y in 0..8 {
            for x in 0..8 {
                let mut s = 0.0;
                for u in 0..8 {
                    s += b[u][x] * tmp[y * 8 + u];
                }
                out[y * 8 + x] = s;
            }
        }
    });
}

/// Forward DCT of level-shifted samples (natural order).
pub fn fdct(samples: &[f32; 64], out: &mut [f32; 64]) {
    BASIS.with(|b| {
        let mut tmp = [0f32; 64];
        for y in 0..8 {
            for u in 0..8 {
                let mut s = 0.0;
                for x in 0..8 {
                    s += b[u][x] * samples[y * 8 + x];
                }
                tmp[y * 8 + u] = s;
            }
        }
        for v in 0..8 {
            for u in 0..8 {
                let mut s = 0.0;
                for y in 0..8 {
                    s += b[v][y] * tmp[y * 8 + u];
                }
                out[v * 8 + u] = s;
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zigzag_is_a_permutation_with_known_start() {
        let mut seen = [false; 64];
        for &i in &ZIGZAG {
            seen[i] = true;
        }
        assert!(seen.iter().all(|&s| s));
        assert_eq!(&ZIGZAG[..10], &[0, 1, 8, 16, 9, 2, 3, 10, 17, 24]);
        assert_eq!(ZIGZAG[63], 63);
    }

    #[test]
    fn dct_round_trip_and_dc_scaling() {
        let mut s = [0f32; 64];
        for (i, v) in s.iter_mut().enumerate() {
            *v = ((i * 37) % 255) as f32 - 128.0;
        }
        let (mut f, mut back) = ([0f32; 64], [0f32; 64]);
        fdct(&s, &mut f);
        idct(&f, &mut back);
        for (a, b) in s.iter().zip(&back) {
            assert!((a - b).abs() < 1e-3);
        }
        // A flat block of value v has DC = 8v under this normalisation.
        let flat = [10f32; 64];
        fdct(&flat, &mut f);
        assert!((f[0] - 80.0).abs() < 1e-3);
        assert!(f[1..].iter().all(|v| v.abs() < 1e-4));
    }
}
