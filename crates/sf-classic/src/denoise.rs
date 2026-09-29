//! Wavelet denoising and deblocking.

const LEVELS: usize = 4;
/// B3-spline smoothing kernel (1, 4, 6, 4, 1) / 16, applied with holes.
const B3: [f32; 5] = [1.0 / 16.0, 4.0 / 16.0, 6.0 / 16.0, 4.0 / 16.0, 1.0 / 16.0];

fn smooth(src: &[f32], w: usize, h: usize, step: usize) -> Vec<f32> {
    let clamp = |v: isize, n: usize| v.clamp(0, n as isize - 1) as usize;
    let mut tmp = vec![0f32; w * h];
    for y in 0..h {
        for x in 0..w {
            tmp[y * w + x] = (0..5)
                .map(|k| B3[k] * src[y * w + clamp(x as isize + (k as isize - 2) * step as isize, w)])
                .sum();
        }
    }
    let mut out = vec![0f32; w * h];
    for y in 0..h {
        for x in 0..w {
            out[y * w + x] = (0..5)
                .map(|k| B3[k] * tmp[clamp(y as isize + (k as isize - 2) * step as isize, h) * w + x])
                .sum();
        }
    }
    out
}

/// Standard deviation of each detail level for unit white noise, measured
/// by transforming a unit impulse (the level's filter energy).
fn level_noise() -> [f32; LEVELS] {
    let n = 129;
    let mut img = vec![0f32; n * n];
    img[(n / 2) * n + n / 2] = 1.0;
    let mut out = [0f32; LEVELS];
    let mut cur = img;
    for (j, o) in out.iter_mut().enumerate() {
        let next = smooth(&cur, n, n, 1 << j);
        *o = cur.iter().zip(&next).map(|(a, b)| (a - b).powi(2)).sum::<f32>().sqrt();
        cur = next;
    }
    out
}

fn shrink_plane(plane: &mut [f32], w: usize, h: usize, threshold: f32, factors: &[f32; LEVELS]) {
    let mut cur = plane.to_vec();
    let mut result = vec![0f32; w * h];
    for (j, f) in factors.iter().enumerate() {
        let next = smooth(&cur, w, h, 1 << j);
        let t = threshold * f;
        for i in 0..w * h {
            let d = cur[i] - next[i];
            // Soft thresholding: shrink every coefficient towards zero by t.
            result[i] += d.signum() * (d.abs() - t).max(0.0);
        }
        cur = next;
    }
    for i in 0..w * h {
        plane[i] = result[i] + cur[i];
    }
}

/// Removes noise of standard deviation `sigma` (0–1 units, luma) with
/// strength `strength` (1 = calibrated default; 0 = no change). Colour
/// images are processed in an opponent space (luma and two colour
/// differences). Chroma noise is removed more strongly than luma noise,
/// because the eye is less sensitive to colour detail.
pub fn denoise(data: &mut [f32], w: usize, h: usize, channels: usize, sigma: f32, strength: f32) {
    if sigma <= 0.0 || strength <= 0.0 {
        return;
    }
    let factors = level_noise();
    // ~2.2σ removes most Gaussian noise while keeping edges.
    let t = 2.2 * sigma * strength;
    if channels == 1 {
        shrink_plane(data, w, h, t, &factors);
        return;
    }
    let n = w * h;
    let (mut y, mut u, mut v) = (vec![0f32; n], vec![0f32; n], vec![0f32; n]);
    for i in 0..n {
        let (r, g, b) = (data[3 * i], data[3 * i + 1], data[3 * i + 2]);
        y[i] = 0.299 * r + 0.587 * g + 0.114 * b;
        u[i] = b - y[i];
        v[i] = r - y[i];
    }
    shrink_plane(&mut y, w, h, t, &factors);
    shrink_plane(&mut u, w, h, 1.5 * t, &factors);
    shrink_plane(&mut v, w, h, 1.5 * t, &factors);
    for i in 0..n {
        let r = v[i] + y[i];
        let b = u[i] + y[i];
        let g = (y[i] - 0.299 * r - 0.114 * b) / 0.587;
        data[3 * i] = r;
        data[3 * i + 1] = g;
        data[3 * i + 2] = b;
    }
}

/// Smooths steps across 8-pixel block boundaries (grid offset `phase`)
/// when they are smaller than `step` (0–1 units, typically about the
/// JPEG quantisation step of low frequencies) and both sides are flat.
/// Real edges, which are larger or textured, are left alone.
pub fn deblock(data: &mut [f32], w: usize, h: usize, channels: usize, step: f32, phase: usize) {
    if step <= 0.0 {
        return;
    }
    let c = channels;
    let filter = |a: usize, b: usize, s: usize, data: &mut [f32]| {
        // Samples: p1 = a − s, p0 = a, q0 = b, q1 = b + s.
        for ch in 0..c {
            let (p1, p0, q0, q1) =
                (data[(a - s) * c + ch], data[a * c + ch], data[b * c + ch], data[(b + s) * c + ch]);
            let d = q0 - p0;
            if d.abs() < step && (p1 - p0).abs() < step / 2.0 && (q1 - q0).abs() < step / 2.0 {
                data[a * c + ch] = p0 + d / 4.0;
                data[b * c + ch] = q0 - d / 4.0;
                data[(a - s) * c + ch] = p1 + d / 8.0;
                data[(b + s) * c + ch] = q1 - d / 8.0;
            }
        }
    };
    for y in 0..h {
        let mut x = (phase % 8) + 8;
        while x + 1 < w {
            // Boundary between columns x−1 and x.
            if x >= 2 {
                filter(y * w + x - 1, y * w + x, 1, data);
            }
            x += 8;
        }
    }
    let mut y = (phase % 8) + 8;
    while y + 1 < h {
        if y >= 2 {
            for x in 0..w {
                filter((y - 1) * w + x, y * w + x, w, data);
            }
        }
        y += 8;
    }
}
