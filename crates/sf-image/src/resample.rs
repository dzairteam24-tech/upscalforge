//! Separable resampling of interleaved `f32` images.
//!
//! Sample centres are aligned: destination pixel `i` maps to source
//! position `(i + 0.5)·(src/dst) − 0.5`. When downscaling, the kernel is
//! widened by the scale ratio, which band-limits the signal and so
//! prevents aliasing. Edges are handled by clamping coordinates.

/// Resampling kernels.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Filter {
    /// Nearest neighbour.
    Nearest,
    /// Linear interpolation (triangle kernel).
    Bilinear,
    /// Lanczos-windowed sinc with 3 lobes.
    Lanczos3,
    /// Box average of the covered area (downscaling).
    Area,
}

impl Filter {
    fn support(self) -> f64 {
        match self {
            Filter::Nearest | Filter::Area => 0.5,
            Filter::Bilinear => 1.0,
            Filter::Lanczos3 => 3.0,
        }
    }

    fn weight(self, x: f64) -> f64 {
        let x = x.abs();
        match self {
            Filter::Nearest | Filter::Area => {
                if x < 0.5 {
                    1.0
                } else if x == 0.5 {
                    0.5
                } else {
                    0.0
                }
            }
            Filter::Bilinear => (1.0 - x).max(0.0),
            Filter::Lanczos3 => {
                if x < 1e-8 {
                    1.0
                } else if x < 3.0 {
                    let px = std::f64::consts::PI * x;
                    3.0 * px.sin() * (px / 3.0).sin() / (px * px)
                } else {
                    0.0
                }
            }
        }
    }
}

/// Per-destination-sample contributions: (first source index, weights).
fn contributions(src: usize, dst: usize, filter: Filter) -> Vec<(usize, Vec<f32>)> {
    let scale = src as f64 / dst as f64;
    let stretch = if filter == Filter::Nearest { 1.0 } else { scale.max(1.0) };
    let support = filter.support() * stretch;
    (0..dst)
        .map(|i| {
            let center = (i as f64 + 0.5) * scale - 0.5;
            if filter == Filter::Nearest {
                let j = (center.round().max(0.0) as usize).min(src - 1);
                return (j, vec![1.0]);
            }
            let lo = (center - support).floor() as isize;
            let hi = (center + support).ceil() as isize;
            let mut w: Vec<f64> = (lo..=hi).map(|j| filter.weight((j as f64 - center) / stretch)).collect();
            let sum: f64 = w.iter().sum();
            if sum.abs() > 1e-12 {
                w.iter_mut().for_each(|v| *v /= sum);
            }
            // Fold out-of-range taps onto the edge samples (clamping).
            let first = lo.clamp(0, src as isize - 1) as usize;
            let last = hi.clamp(0, src as isize - 1) as usize;
            let mut folded = vec![0f32; last - first + 1];
            for (k, j) in (lo..=hi).enumerate() {
                let idx = j.clamp(0, src as isize - 1) as usize;
                folded[idx - first] += w[k] as f32;
            }
            (first, folded)
        })
        .collect()
}

fn workers(rows: usize) -> usize {
    let n = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
    n.min(rows.max(1) / 16).max(1)
}

/// Resizes an interleaved image of `c` channels from `w×h` to `nw×nh`.
pub fn resize(src: &[f32], w: usize, h: usize, c: usize, nw: usize, nh: usize, filter: Filter) -> Vec<f32> {
    assert_eq!(src.len(), w * h * c, "source length");
    assert!(nw > 0 && nh > 0, "empty destination");
    // Horizontal pass: h rows of nw pixels.
    let hc = contributions(w, nw, filter);
    let mut mid = vec![0f32; nw * h * c];
    let per = h.div_ceil(workers(h));
    std::thread::scope(|s| {
        for (bi, band) in mid.chunks_mut(per * nw * c).enumerate() {
            let hc = &hc;
            s.spawn(move || {
                for (r, row) in band.chunks_mut(nw * c).enumerate() {
                    let y = bi * per + r;
                    let srow = &src[y * w * c..(y + 1) * w * c];
                    for (x, (first, wts)) in hc.iter().enumerate() {
                        for ch in 0..c {
                            let mut acc = 0f32;
                            for (k, &wt) in wts.iter().enumerate() {
                                acc += wt * srow[(first + k) * c + ch];
                            }
                            row[x * c + ch] = acc;
                        }
                    }
                }
            });
        }
    });
    // Vertical pass.
    let vc = contributions(h, nh, filter);
    let mut out = vec![0f32; nw * nh * c];
    let per = nh.div_ceil(workers(nh));
    std::thread::scope(|s| {
        for (bi, band) in out.chunks_mut(per * nw * c).enumerate() {
            let (vc, mid) = (&vc, &mid);
            s.spawn(move || {
                for (r, row) in band.chunks_mut(nw * c).enumerate() {
                    let (first, wts) = &vc[bi * per + r];
                    for (k, &wt) in wts.iter().enumerate() {
                        let srow = &mid[(first + k) * nw * c..(first + k + 1) * nw * c];
                        for (o, &v) in row.iter_mut().zip(srow) {
                            *o += wt * v;
                        }
                    }
                }
            });
        }
    });
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_size_is_exact_for_interpolating_filters() {
        let src: Vec<f32> = (0..7 * 5 * 3).map(|i| (i % 13) as f32).collect();
        for f in [Filter::Nearest, Filter::Bilinear, Filter::Lanczos3, Filter::Area] {
            let out = resize(&src, 7, 5, 3, 7, 5, f);
            for (a, b) in out.iter().zip(&src) {
                assert!((a - b).abs() < 1e-4, "{f:?}");
            }
        }
    }

    #[test]
    fn constant_images_stay_constant_and_weights_normalise() {
        let src = vec![0.25f32; 9 * 6];
        for f in [Filter::Bilinear, Filter::Lanczos3, Filter::Area] {
            for (nw, nh) in [(20, 13), (3, 2), (9, 1)] {
                let out = resize(&src, 9, 6, 1, nw, nh, f);
                assert!(out.iter().all(|v| (v - 0.25).abs() < 1e-5), "{f:?} {nw}x{nh}");
            }
        }
    }

    #[test]
    fn area_downscale_by_two_averages_blocks() {
        let src = vec![0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0];
        // 4×2 → 2×1: blocks {0,1,4,5} and {2,3,6,7}.
        let out = resize(&src, 4, 2, 1, 2, 1, Filter::Area);
        assert!((out[0] - 2.5).abs() < 1e-6 && (out[1] - 4.5).abs() < 1e-6, "{out:?}");
    }

    #[test]
    fn bilinear_upscale_of_a_ramp_is_linear_inside() {
        let src: Vec<f32> = (0..8).map(|i| i as f32).collect();
        let out = resize(&src, 8, 1, 1, 16, 1, Filter::Bilinear);
        // Output i maps to source (i + 0.5)/2 − 0.5.
        for (i, &v) in out.iter().enumerate().take(15).skip(1) {
            assert!((v - ((i as f32 + 0.5) / 2.0 - 0.5)).abs() < 1e-5, "{i}: {v}");
        }
    }

    #[test]
    fn lanczos_downscale_suppresses_aliasing() {
        // A near-Nyquist stripe pattern must average out when downscaled 4×,
        // whereas nearest-neighbour sampling aliases it.
        let w = 64;
        let src: Vec<f32> = (0..w).map(|i| if i % 2 == 0 { 1.0 } else { 0.0 }).collect();
        let lz = resize(&src, w, 1, 1, w / 4, 1, Filter::Lanczos3);
        assert!(lz[2..14].iter().all(|v| (v - 0.5).abs() < 0.02), "{lz:?}");
        let nn = resize(&src, w, 1, 1, w / 4, 1, Filter::Nearest);
        assert!(
            nn.iter().all(|&v| v == nn[0]) && (nn[0] - 0.5).abs() > 0.4,
            "nearest aliases to a constant 0 or 1"
        );
    }
}
