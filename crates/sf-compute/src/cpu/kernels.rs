//! CPU reference kernels (f32, NCHW).
//!
//! Determinism rule: each output element is computed by exactly one thread,
//! with a fixed accumulation order that does not depend on the thread count
//! or on the element's position.

use sf_graph::Activation;

/// Spatial tensor dimensions.
#[derive(Debug, Clone, Copy)]
pub(super) struct Dims {
    pub n: usize,
    pub c: usize,
    pub h: usize,
    pub w: usize,
}

impl Dims {
    pub fn new(n: u32, c: u32, h: u32, w: u32) -> Dims {
        Dims { n: n as usize, c: c as usize, h: h as usize, w: w as usize }
    }

    fn plane(&self) -> usize {
        self.h * self.w
    }
}

/// Convolution parameters.
#[derive(Debug, Clone, Copy)]
pub(super) struct Conv {
    pub out_channels: usize,
    pub kernel: usize,
    pub stride: usize,
    pub depthwise: bool,
}

/// Zero-padded "same" convolution; `stride` 2 halves each dimension.
///
/// Accumulation order per output element: bias, then input channel,
/// kernel row and kernel column, in increasing order.
pub(super) fn conv2d(
    x: &[f32],
    d: Dims,
    weight: &[f32],
    bias: Option<&[f32]>,
    out: &mut [f32],
    p: Conv,
    threads: usize,
) {
    let (ho, wo) = (d.h / p.stride, d.w / p.stride);
    let plane_out = ho * wo;
    let planes = d.n * p.out_channels;
    let pad = (p.kernel / 2) as isize;
    let k = p.kernel;

    let compute_plane = |index: usize, dst: &mut [f32]| {
        let (ni, oc) = (index / p.out_channels, index % p.out_channels);
        dst.fill(bias.map_or(0.0, |b| b[oc]));
        let channels = if p.depthwise { oc..oc + 1 } else { 0..d.c };
        for ic in channels {
            let src = &x[(ni * d.c + ic) * d.plane()..][..d.plane()];
            let wbase = if p.depthwise { oc * k * k } else { (oc * d.c + ic) * k * k };
            for ky in 0..k {
                for y in 0..ho {
                    let iy = (y * p.stride + ky) as isize - pad;
                    if iy < 0 || iy >= d.h as isize {
                        continue;
                    }
                    let row = &src[iy as usize * d.w..][..d.w];
                    let dst_row = &mut dst[y * wo..][..wo];
                    for kx in 0..k {
                        let wv = weight[wbase + ky * k + kx];
                        let shift = kx as isize - pad;
                        // Valid x: 0 <= x*stride + shift < w.
                        let lo = if shift < 0 { ((-shift) as usize).div_ceil(p.stride) } else { 0 };
                        let hi_num = d.w as isize - 1 - shift;
                        if hi_num < 0 {
                            continue;
                        }
                        let hi = (hi_num as usize / p.stride + 1).min(wo);
                        if lo >= hi {
                            continue;
                        }
                        if p.stride == 1 {
                            let s0 = (lo as isize + shift) as usize;
                            let src_run = &row[s0..s0 + (hi - lo)];
                            for (o, &v) in dst_row[lo..hi].iter_mut().zip(src_run) {
                                *o += wv * v;
                            }
                        } else {
                            for (xo, o) in dst_row.iter_mut().enumerate().take(hi).skip(lo) {
                                // In range by construction of lo..hi.
                                *o += wv * row[xo * p.stride + kx - pad as usize];
                            }
                        }
                    }
                }
            }
        }
    };

    let out = &mut out[..planes * plane_out];
    let workers = threads.clamp(1, planes.max(1));
    if workers == 1 {
        for (i, dst) in out.chunks_mut(plane_out).enumerate() {
            compute_plane(i, dst);
        }
        return;
    }
    let per_worker = planes.div_ceil(workers);
    std::thread::scope(|scope| {
        for (w, chunk) in out.chunks_mut(per_worker * plane_out).enumerate() {
            let compute_plane = &compute_plane;
            scope.spawn(move || {
                for (j, dst) in chunk.chunks_mut(plane_out).enumerate() {
                    compute_plane(w * per_worker + j, dst);
                }
            });
        }
    });
}

pub(super) fn avg_pool2(x: &[f32], d: Dims, out: &mut [f32]) {
    let (ho, wo) = (d.h / 2, d.w / 2);
    for p in 0..d.n * d.c {
        let src = &x[p * d.plane()..][..d.plane()];
        let dst = &mut out[p * ho * wo..][..ho * wo];
        for y in 0..ho {
            for xo in 0..wo {
                let a = src[2 * y * d.w + 2 * xo] + src[2 * y * d.w + 2 * xo + 1];
                let b = src[(2 * y + 1) * d.w + 2 * xo] + src[(2 * y + 1) * d.w + 2 * xo + 1];
                dst[y * wo + xo] = (a + b) * 0.25;
            }
        }
    }
}

pub(super) fn upsample_nearest2(x: &[f32], d: Dims, out: &mut [f32]) {
    let (ho, wo) = (d.h * 2, d.w * 2);
    for p in 0..d.n * d.c {
        let src = &x[p * d.plane()..][..d.plane()];
        let dst = &mut out[p * ho * wo..][..ho * wo];
        for y in 0..ho {
            for xo in 0..wo {
                dst[y * wo + xo] = src[(y / 2) * d.w + xo / 2];
            }
        }
    }
}

/// `[N, C·r², H, W] → [N, C, rH, rW]`, source channel `c·r² + dy·r + dx`.
pub(super) fn pixel_shuffle(x: &[f32], d: Dims, r: usize, out: &mut [f32]) {
    let c_out = d.c / (r * r);
    let (ho, wo) = (d.h * r, d.w * r);
    for n in 0..d.n {
        for c in 0..c_out {
            let dst = &mut out[(n * c_out + c) * ho * wo..][..ho * wo];
            for y in 0..ho {
                for xo in 0..wo {
                    let src_c = c * r * r + (y % r) * r + (xo % r);
                    dst[y * wo + xo] = x[((n * d.c + src_c) * d.h + y / r) * d.w + xo / r];
                }
            }
        }
    }
}

/// Exact inverse of [`pixel_shuffle`].
pub(super) fn pixel_unshuffle(x: &[f32], d: Dims, r: usize, out: &mut [f32]) {
    let (ho, wo) = (d.h / r, d.w / r);
    let c_out = d.c * r * r;
    for n in 0..d.n {
        for c in 0..c_out {
            let (src_c, dy, dx) = (c / (r * r), (c % (r * r)) / r, c % r);
            let dst = &mut out[(n * c_out + c) * ho * wo..][..ho * wo];
            for y in 0..ho {
                for xo in 0..wo {
                    dst[y * wo + xo] = x[((n * d.c + src_c) * d.h + r * y + dy) * d.w + r * xo + dx];
                }
            }
        }
    }
}

pub(super) fn binary(a: &[f32], b: &[f32], out: &mut [f32], f: impl Fn(f32, f32) -> f32) {
    for ((o, &x), &y) in out.iter_mut().zip(a).zip(b) {
        *o = f(x, y);
    }
}

pub(super) fn unary(a: &[f32], out: &mut [f32], f: impl Fn(f32) -> f32) {
    for (o, &x) in out.iter_mut().zip(a) {
        *o = f(x);
    }
}

fn sigmoid(v: f32) -> f32 {
    1.0 / (1.0 + (-v).exp())
}

pub(super) fn activation(a: &[f32], out: &mut [f32], act: Activation) {
    match act {
        Activation::Relu => unary(a, out, |v| v.max(0.0)),
        Activation::LeakyRelu(s) => unary(a, out, |v| if v >= 0.0 { v } else { s * v }),
        Activation::Sigmoid => unary(a, out, sigmoid),
        Activation::Silu => unary(a, out, |v| v * sigmoid(v)),
        Activation::Gelu => {
            // Tanh approximation: 0.5·x·(1 + tanh(√(2/π)·(x + 0.044715·x³))).
            const K: f32 = 0.797_884_6;
            unary(a, out, |v| 0.5 * v * (1.0 + (K * (v + 0.044_715 * v * v * v)).tanh()))
        }
    }
}

/// `x · scale[c] + shift[c]`; scale and shift carry their own batch size
/// (1 broadcasts over the batch).
pub(super) fn affine_channel(
    x: &[f32],
    d: Dims,
    scale: (&[f32], usize),
    shift: (&[f32], usize),
    out: &mut [f32],
) {
    let pick = |v: (&[f32], usize), n: usize, c: usize| v.0[if v.1 == 1 { c } else { n * d.c + c }];
    for n in 0..d.n {
        for c in 0..d.c {
            let (s, t) = (pick(scale, n, c), pick(shift, n, c));
            let base = (n * d.c + c) * d.plane();
            for (o, &v) in out[base..base + d.plane()].iter_mut().zip(&x[base..base + d.plane()]) {
                *o = v * s + t;
            }
        }
    }
}

pub(super) fn prelu(x: &[f32], d: Dims, slope: &[f32], out: &mut [f32]) {
    for n in 0..d.n {
        for (c, &s) in slope.iter().enumerate().take(d.c) {
            let base = (n * d.c + c) * d.plane();
            for (o, &v) in out[base..base + d.plane()].iter_mut().zip(&x[base..base + d.plane()]) {
                *o = if v >= 0.0 { v } else { s * v };
            }
        }
    }
}

pub(super) fn concat(parts: &[(&[f32], Dims)], out: &mut [f32]) {
    let n = parts[0].1.n;
    let mut at = 0;
    for ni in 0..n {
        for (data, d) in parts {
            let block = d.c * d.plane();
            out[at..at + block].copy_from_slice(&data[ni * block..][..block]);
            at += block;
        }
    }
}

pub(super) fn slice_channels(x: &[f32], d: Dims, start: usize, len: usize, out: &mut [f32]) {
    let block = len * d.plane();
    for n in 0..d.n {
        out[n * block..][..block].copy_from_slice(&x[(n * d.c + start) * d.plane()..][..block]);
    }
}

/// Margins are `[top, left, bottom, right]`.
pub(super) fn crop(x: &[f32], d: Dims, m: [usize; 4], out: &mut [f32]) {
    let (ho, wo) = (d.h - m[0] - m[2], d.w - m[1] - m[3]);
    for p in 0..d.n * d.c {
        for y in 0..ho {
            let src = &x[p * d.plane() + (y + m[0]) * d.w + m[1]..][..wo];
            out[(p * ho + y) * wo..][..wo].copy_from_slice(src);
        }
    }
}

/// Mean over each plane, accumulated in f64 in row-major order.
pub(super) fn global_mean(x: &[f32], d: Dims, out: &mut [f32]) {
    for p in 0..d.n * d.c {
        let sum: f64 = x[p * d.plane()..][..d.plane()].iter().map(|&v| f64::from(v)).sum();
        out[p] = (sum / d.plane() as f64) as f32;
    }
}

pub(super) fn linear(
    x: &[f32],
    n: usize,
    c: usize,
    weight: &[f32],
    bias: Option<&[f32]>,
    out_features: usize,
    out: &mut [f32],
) {
    for ni in 0..n {
        let xi = &x[ni * c..][..c];
        for o in 0..out_features {
            let row = &weight[o * c..][..c];
            let dot: f32 = row.iter().zip(xi).map(|(a, b)| a * b).sum();
            out[ni * out_features + o] = dot + bias.map_or(0.0, |b| b[o]);
        }
    }
}
