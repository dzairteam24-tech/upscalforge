//! Full-reference quality metrics. No single metric decides quality;
//! these are inputs to evaluation, alongside human judgement.

use sf_image::ImageBuffer;

use crate::Plane;

/// Peak signal-to-noise ratio in dB over all channels (values normalised
/// to 0–1). Identical images give `f64::INFINITY`.
pub fn psnr(a: &ImageBuffer, b: &ImageBuffer) -> Option<f64> {
    if (a.width(), a.height(), a.channels()) != (b.width(), b.height(), b.channels()) {
        return None;
    }
    let (x, y) = (a.to_f32(), b.to_f32());
    let mse: f64 = x.iter().zip(&y).map(|(p, q)| f64::from(p - q).powi(2)).sum::<f64>() / x.len() as f64;
    Some(if mse == 0.0 { f64::INFINITY } else { 10.0 * (1.0 / mse).log10() })
}

fn gaussian_blur(p: &Plane) -> Plane {
    // 11-tap Gaussian, sigma 1.5, normalised; edges clamped.
    let k: Vec<f32> = (-5..=5).map(|i: i32| (-(i * i) as f32 / (2.0 * 1.5 * 1.5)).exp()).collect();
    let s: f32 = k.iter().sum();
    let k: Vec<f32> = k.iter().map(|v| v / s).collect();
    let (w, h) = (p.width, p.height);
    let clampx = |x: isize| x.clamp(0, w as isize - 1) as usize;
    let clampy = |y: isize| y.clamp(0, h as isize - 1) as usize;
    let mut tmp = vec![0f32; w * h];
    for y in 0..h {
        for x in 0..w {
            tmp[y * w + x] =
                (0..11).map(|i| k[i] * p.data[y * w + clampx(x as isize + i as isize - 5)]).sum();
        }
    }
    let mut out = vec![0f32; w * h];
    for y in 0..h {
        for x in 0..w {
            out[y * w + x] = (0..11).map(|i| k[i] * tmp[clampy(y as isize + i as isize - 5) * w + x]).sum();
        }
    }
    Plane { width: w, height: h, data: out }
}

/// Mean structural similarity of luma (Gaussian window σ = 1.5,
/// K1 = 0.01, K2 = 0.03, dynamic range 255).
pub fn ssim(a: &ImageBuffer, b: &ImageBuffer) -> Option<f64> {
    if (a.width(), a.height()) != (b.width(), b.height()) {
        return None;
    }
    let (x, y) = (Plane::luma_full(a), Plane::luma_full(b));
    let prod = |p: &Plane, q: &Plane| Plane {
        width: p.width,
        height: p.height,
        data: p.data.iter().zip(&q.data).map(|(u, v)| u * v).collect(),
    };
    let (mx, my) = (gaussian_blur(&x), gaussian_blur(&y));
    let (sxx, syy, sxy) =
        (gaussian_blur(&prod(&x, &x)), gaussian_blur(&prod(&y, &y)), gaussian_blur(&prod(&x, &y)));
    let (c1, c2) = ((0.01f64 * 255.0).powi(2), (0.03f64 * 255.0).powi(2));
    let n = x.data.len();
    let total: f64 = (0..n)
        .map(|i| {
            let (m1, m2) = (f64::from(mx.data[i]), f64::from(my.data[i]));
            let v1 = f64::from(sxx.data[i]) - m1 * m1;
            let v2 = f64::from(syy.data[i]) - m2 * m2;
            let cov = f64::from(sxy.data[i]) - m1 * m2;
            ((2.0 * m1 * m2 + c1) * (2.0 * cov + c2)) / ((m1 * m1 + m2 * m2 + c1) * (v1 + v2 + c2))
        })
        .sum();
    Some(total / n as f64)
}
