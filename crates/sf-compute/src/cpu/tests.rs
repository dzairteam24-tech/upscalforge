//! CPU backend tests: kernels vs. naive references, determinism, memory,
//! strict-mode hazards, out-of-memory handling, and exact tiling.

use std::sync::Arc;

use sf_core::{DeviceErrorKind, ErrorKind, Rng};
use sf_graph::{Activation, Graph, GraphRole, InputKind, Op, OutputKind, Shape, ValueRef, locality};

use super::{CpuBackend, CpuConfig, CpuDevice};
use crate::{Binding, Bindings, Device, MemoryKind, Precision};

fn device(threads: usize, strict: bool) -> Arc<CpuDevice> {
    CpuBackend::new(CpuConfig { threads, strict, memory_limit: None }).device().unwrap()
}

fn random_vec(rng: &mut Rng, len: usize) -> Vec<f32> {
    (0..len).map(|_| rng.range_f64(-1.0, 1.0) as f32).collect()
}

/// Input data for one graph input.
enum In {
    Tensor(Shape, Vec<f32>),
    Scalar(f32),
}

/// Compiles and runs `g` through the full device path (allocate, upload,
/// execute, download) and returns every output.
fn run(dev: &CpuDevice, g: &Graph, inputs: &[In], params: &[Vec<f32>]) -> sf_core::Result<Vec<Vec<f32>>> {
    let shapes: Vec<Shape> = inputs
        .iter()
        .map(|i| match i {
            In::Tensor(s, _) => *s,
            In::Scalar(_) => Shape::Scalar,
        })
        .collect();
    let exe = dev.compile(g, &shapes, Precision::F32)?;
    let mut q = dev.create_queue()?;
    let upload = |q: &mut Box<dyn crate::Queue>, data: &[f32]| -> sf_core::Result<crate::Buffer> {
        let b = dev.allocate(data.len() as u64 * 4, MemoryKind::Device)?;
        q.upload(&b, data)?;
        Ok(b)
    };
    let in_bufs: Vec<Option<crate::Buffer>> = inputs
        .iter()
        .map(|i| match i {
            In::Tensor(_, d) => upload(&mut q, d).map(Some),
            In::Scalar(_) => Ok(None),
        })
        .collect::<sf_core::Result<_>>()?;
    let param_bufs: Vec<crate::Buffer> =
        params.iter().map(|p| upload(&mut q, p)).collect::<sf_core::Result<_>>()?;
    let sh = sf_graph::infer_shapes(g, &shapes)?;
    let out_bufs: Vec<crate::Buffer> = g
        .outputs
        .iter()
        .map(|o| dev.allocate(sh.value(g, o.value).unwrap().elements() * 4, MemoryKind::Device))
        .collect::<sf_core::Result<_>>()?;
    let arena = dev.allocate(exe.memory().arena_bytes.max(4), MemoryKind::Device)?;
    let bindings = Bindings {
        inputs: inputs
            .iter()
            .zip(&in_bufs)
            .map(|(i, b)| match i {
                In::Scalar(v) => Binding::Scalar(*v),
                In::Tensor(..) => Binding::Buffer(b.as_ref().unwrap()),
            })
            .collect(),
        params: param_bufs.iter().collect(),
        outputs: out_bufs.iter().collect(),
        arena: &arena,
    };
    q.execute(exe.as_ref(), &bindings)?;
    out_bufs.iter().map(|b| q.download(b)?.wait()).collect()
}

fn sp(n: u32, c: u32, h: u32, w: u32) -> Shape {
    Shape::Spatial { n, c, h, w }
}

fn assert_close(a: &[f32], b: &[f32], tol: f32) {
    assert_eq!(a.len(), b.len());
    for (i, (x, y)) in a.iter().zip(b).enumerate() {
        assert!((x - y).abs() <= tol * (1.0 + y.abs()), "element {i}: {x} vs {y}");
    }
}

// ---------- naive references (written for clarity, not speed) ----------

#[allow(clippy::too_many_arguments)]
fn conv_ref(
    x: &[f32],
    (n, c, h, w): (usize, usize, usize, usize),
    wt: &[f32],
    bias: Option<&[f32]>,
    cout: usize,
    k: usize,
    s: usize,
    dw: bool,
) -> Vec<f32> {
    let (ho, wo, p) = (h / s, w / s, (k / 2) as isize);
    let mut out = vec![0.0; n * cout * ho * wo];
    for ni in 0..n {
        for oc in 0..cout {
            for y in 0..ho {
                for xo in 0..wo {
                    let mut acc = f64::from(bias.map_or(0.0, |b| b[oc]));
                    let ics: Vec<usize> = if dw { vec![oc] } else { (0..c).collect() };
                    for ic in ics {
                        for ky in 0..k {
                            for kx in 0..k {
                                let iy = (y * s + ky) as isize - p;
                                let ix = (xo * s + kx) as isize - p;
                                if iy < 0 || ix < 0 || iy >= h as isize || ix >= w as isize {
                                    continue;
                                }
                                let wv = if dw {
                                    wt[(oc * k + ky) * k + kx]
                                } else {
                                    wt[((oc * c + ic) * k + ky) * k + kx]
                                };
                                acc += f64::from(wv)
                                    * f64::from(x[((ni * c + ic) * h + iy as usize) * w + ix as usize]);
                            }
                        }
                    }
                    out[((ni * cout + oc) * ho + y) * wo + xo] = acc as f32;
                }
            }
        }
    }
    out
}

fn single_op_graph(op: Op, input_c: u32, params: &[&[u32]]) -> Graph {
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", InputKind::Spatial { channels: input_c, spacing_log2: 0 });
    let mut ins = vec![x];
    for (i, dims) in params.iter().enumerate() {
        ins.push(g.param(format!("p{i}"), dims));
    }
    let y = g.node(op, &ins);
    g.output("y", y, OutputKind::Tensor);
    g
}

// ---------- kernels ----------

#[test]
fn conv2d_matches_reference_across_configurations() {
    let dev = device(3, true);
    let mut rng = Rng::seed_from_u64(0xC0_4F);
    for case in 0..120 {
        let k = [1, 3, 5, 7][case % 4];
        let s = 1 + (case / 4) % 2;
        let dw = (case / 8) % 2 == 1;
        let has_bias = (case / 16) % 2 == 1;
        let n = 1 + rng.below(2) as usize;
        let c = 1 + rng.below(4) as usize;
        let cout = if dw { c } else { 1 + rng.below(5) as usize };
        let h = s * (1 + rng.below(9) as usize);
        let w = s * (1 + rng.below(9) as usize);
        let x = random_vec(&mut rng, n * c * h * w);
        let wdims = if dw { [cout, 1, k, k] } else { [cout, c, k, k] };
        let wt = random_vec(&mut rng, wdims.iter().product());
        let bias = random_vec(&mut rng, cout);
        let op = Op::Conv2d {
            out_channels: cout as u32,
            kernel: k as u32,
            stride: s as u32,
            depthwise: dw,
            bias: has_bias,
        };
        let wd: Vec<u32> = wdims.iter().map(|&v| v as u32).collect();
        let bd = [cout as u32];
        let pdims: Vec<&[u32]> = if has_bias { vec![&wd, &bd] } else { vec![&wd] };
        let g = single_op_graph(op, c as u32, &pdims);
        let mut params = vec![wt.clone()];
        if has_bias {
            params.push(bias.clone());
        }
        let got =
            run(&dev, &g, &[In::Tensor(sp(n as u32, c as u32, h as u32, w as u32), x.clone())], &params)
                .unwrap();
        let want = conv_ref(&x, (n, c, h, w), &wt, has_bias.then_some(&bias[..]), cout, k, s, dw);
        assert_close(&got[0], &want, 1e-5);
    }
}

#[test]
fn results_do_not_depend_on_thread_count() {
    let mut rng = Rng::seed_from_u64(99);
    let (c, cout, h, w) = (5usize, 7usize, 13usize, 11usize);
    let x = random_vec(&mut rng, c * h * w);
    let wt = random_vec(&mut rng, cout * c * 9);
    let g = single_op_graph(
        Op::Conv2d { out_channels: cout as u32, kernel: 3, stride: 1, depthwise: false, bias: false },
        c as u32,
        &[&[cout as u32, c as u32, 3, 3]],
    );
    let input = [In::Tensor(sp(1, c as u32, h as u32, w as u32), x)];
    let one = run(&device(1, false), &g, &input, std::slice::from_ref(&wt)).unwrap();
    for threads in [2, 3, 8] {
        let many = run(&device(threads, false), &g, &input, std::slice::from_ref(&wt)).unwrap();
        let bits = |v: &[f32]| v.iter().map(|f| f.to_bits()).collect::<Vec<_>>();
        assert_eq!(bits(&one[0]), bits(&many[0]), "threads = {threads}");
    }
}

#[test]
fn resampling_ops_match_definitions() {
    let dev = device(2, true);
    let mut rng = Rng::seed_from_u64(5);
    let (n, c, h, w) = (2usize, 8usize, 4usize, 6usize);
    let x = random_vec(&mut rng, n * c * h * w);
    let at = |v: &[f32], cc: usize, ni: usize, ci: usize, y: usize, xx: usize, ww: usize, hh: usize| {
        v[((ni * cc + ci) * hh + y) * ww + xx]
    };
    let input = [In::Tensor(sp(n as u32, c as u32, h as u32, w as u32), x.clone())];

    let pool = run(&dev, &single_op_graph(Op::AvgPool2, c as u32, &[]), &input, &[]).unwrap().remove(0);
    let up = run(&dev, &single_op_graph(Op::UpsampleNearest2, c as u32, &[]), &input, &[]).unwrap().remove(0);
    let shuf = run(&dev, &single_op_graph(Op::PixelShuffle { factor: 2 }, c as u32, &[]), &input, &[])
        .unwrap()
        .remove(0);
    for ni in 0..n {
        for ci in 0..c {
            for y in 0..h / 2 {
                for xx in 0..w / 2 {
                    let s = at(&x, c, ni, ci, 2 * y, 2 * xx, w, h)
                        + at(&x, c, ni, ci, 2 * y, 2 * xx + 1, w, h)
                        + at(&x, c, ni, ci, 2 * y + 1, 2 * xx, w, h)
                        + at(&x, c, ni, ci, 2 * y + 1, 2 * xx + 1, w, h);
                    assert!((at(&pool, c, ni, ci, y, xx, w / 2, h / 2) - s / 4.0).abs() < 1e-6);
                }
            }
            for y in 0..2 * h {
                for xx in 0..2 * w {
                    assert_eq!(
                        at(&up, c, ni, ci, y, xx, 2 * w, 2 * h),
                        at(&x, c, ni, ci, y / 2, xx / 2, w, h)
                    );
                }
            }
        }
        for co in 0..c / 4 {
            for y in 0..2 * h {
                for xx in 0..2 * w {
                    let src_c = co * 4 + (y % 2) * 2 + xx % 2;
                    assert_eq!(
                        at(&shuf, c / 4, ni, co, y, xx, 2 * w, 2 * h),
                        at(&x, c, ni, src_c, y / 2, xx / 2, w, h)
                    );
                }
            }
        }
    }
    // Space-to-depth undoes depth-to-space exactly.
    let mut g = Graph::new(GraphRole::Main);
    let xi = g.input("x", InputKind::Spatial { channels: c as u32, spacing_log2: 0 });
    let a = g.node(Op::PixelShuffle { factor: 2 }, &[xi]);
    let b = g.node(Op::PixelUnshuffle { factor: 2 }, &[a]);
    g.output("y", b, OutputKind::Tensor);
    assert_eq!(run(&dev, &g, &input, &[]).unwrap()[0], x);
}

#[test]
fn elementwise_channel_and_vector_ops() {
    let dev = device(2, true);
    let mut rng = Rng::seed_from_u64(11);
    let (n, c, h, w) = (2u32, 3u32, 3u32, 4u32);
    let len = (n * c * h * w) as usize;
    let (a, b) = (random_vec(&mut rng, len), random_vec(&mut rng, len));
    let plane = (h * w) as usize;

    let mut g = Graph::new(GraphRole::Main);
    let xa = g.input("a", InputKind::Spatial { channels: c, spacing_log2: 0 });
    let xb = g.input("b", InputKind::Spatial { channels: c, spacing_log2: 0 });
    let cond = g.input("cond", InputKind::Vector { channels: c });
    let s = g.input("s", InputKind::Scalar);
    let shift = g.param("shift", &[c]);
    let slope = g.param("slope", &[c]);
    let ops = [
        g.node(Op::Add, &[xa, xb]),
        g.node(Op::Sub, &[xa, xb]),
        g.node(Op::Mul, &[xa, xb]),
        g.node(Op::AffineChannel, &[xa, cond, shift]),
        g.node(Op::PRelu, &[xa, slope]),
        g.node(Op::Clamp { lo: -0.25, hi: 0.5 }, &[xa]),
        g.node(Op::ScaleScalar, &[xa, s]),
        g.node(Op::Activation(Activation::Relu), &[xa]),
        g.node(Op::Activation(Activation::LeakyRelu(0.2)), &[xa]),
        g.node(Op::Activation(Activation::Sigmoid), &[xa]),
        g.node(Op::Activation(Activation::Silu), &[xa]),
        g.node(Op::Activation(Activation::Gelu), &[xa]),
    ];
    for (i, v) in ops.iter().enumerate() {
        g.output(format!("o{i}"), *v, OutputKind::Tensor);
    }
    let condv = random_vec(&mut rng, (n * c) as usize);
    let shiftv = random_vec(&mut rng, c as usize);
    let slopev = random_vec(&mut rng, c as usize);
    let out = run(
        &dev,
        &g,
        &[
            In::Tensor(sp(n, c, h, w), a.clone()),
            In::Tensor(sp(n, c, h, w), b.clone()),
            In::Tensor(Shape::Vector { n, c }, condv.clone()),
            In::Scalar(-1.5),
        ],
        &[shiftv.clone(), slopev.clone()],
    )
    .unwrap();
    let sig = |v: f64| 1.0 / (1.0 + (-v).exp());
    for i in 0..len {
        let (ni, ci) = (i / plane / c as usize, (i / plane) % c as usize);
        let (x, y) = (f64::from(a[i]), f64::from(b[i]));
        let gelu =
            0.5 * x * (1.0 + ((2.0 / std::f64::consts::PI).sqrt() * (x + 0.044715 * x.powi(3))).tanh());
        let expect = [
            x + y,
            x - y,
            x * y,
            x * f64::from(condv[ni * c as usize + ci]) + f64::from(shiftv[ci]),
            if x >= 0.0 { x } else { f64::from(slopev[ci]) * x },
            x.clamp(-0.25, 0.5),
            -1.5 * x,
            x.max(0.0),
            if x >= 0.0 { x } else { 0.2 * x },
            sig(x),
            x * sig(x),
            gelu,
        ];
        for (k, e) in expect.iter().enumerate() {
            assert!((f64::from(out[k][i]) - e).abs() < 1e-5, "op {k} element {i}: {} vs {e}", out[k][i]);
        }
    }
}

#[test]
fn channel_crop_and_reduction_ops() {
    let dev = device(1, true);
    let mut rng = Rng::seed_from_u64(12);
    let (n, h, w) = (2u32, 4u32, 5u32);
    let a = random_vec(&mut rng, (n * 2 * h * w) as usize);
    let b = random_vec(&mut rng, (n * 3 * h * w) as usize);
    let mut g = Graph::new(GraphRole::Context);
    let xa = g.input("a", InputKind::Spatial { channels: 2, spacing_log2: 0 });
    let xb = g.input("b", InputKind::Spatial { channels: 3, spacing_log2: 0 });
    let cat = g.node(Op::Concat, &[xa, xb]);
    let sl = g.node(Op::SliceChannels { start: 1, len: 3 }, &[cat]);
    let cr = g.node(Op::Crop { top: 1, left: 2, bottom: 0, right: 1 }, &[sl]);
    let mean = g.node(Op::GlobalMean, &[cat]);
    let wl = g.param("w", &[2, 5]);
    let bl = g.param("b", &[2]);
    let lin = g.node(Op::Linear { out_features: 2, bias: true }, &[mean, wl, bl]);
    for (i, v) in [cat, cr, mean, lin].into_iter().enumerate() {
        g.output(format!("o{i}"), v, OutputKind::Tensor);
    }
    let wv = random_vec(&mut rng, 10);
    let bv = random_vec(&mut rng, 2);
    let out = run(
        &dev,
        &g,
        &[In::Tensor(sp(n, 2, h, w), a.clone()), In::Tensor(sp(n, 3, h, w), b.clone())],
        &[wv.clone(), bv.clone()],
    )
    .unwrap();
    let plane = (h * w) as usize;
    // Concatenation: per batch item, a's channels then b's.
    let cat_ref = |ni: usize, ci: usize, p: usize| {
        if ci < 2 { a[(ni * 2 + ci) * plane + p] } else { b[(ni * 3 + ci - 2) * plane + p] }
    };
    for ni in 0..n as usize {
        for ci in 0..5 {
            for p in 0..plane {
                assert_eq!(out[0][(ni * 5 + ci) * plane + p], cat_ref(ni, ci, p));
            }
        }
        // Slice channels 1..4, crop rows 1..4, cols 2..4 → 3×3×2.
        for ci in 0..3 {
            for y in 0..3 {
                for x in 0..2 {
                    let want = cat_ref(ni, ci + 1, (y + 1) * w as usize + x + 2);
                    assert_eq!(out[1][((ni * 3 + ci) * 3 + y) * 2 + x], want);
                }
            }
        }
        let means: Vec<f64> = (0..5)
            .map(|ci| (0..plane).map(|p| f64::from(cat_ref(ni, ci, p))).sum::<f64>() / plane as f64)
            .collect();
        for ci in 0..5 {
            assert!((f64::from(out[2][ni * 5 + ci]) - means[ci]).abs() < 1e-6);
        }
        for o in 0..2 {
            let dot: f64 =
                (0..5).map(|i| f64::from(wv[o * 5 + i]) * means[i]).sum::<f64>() + f64::from(bv[o]);
            assert!((f64::from(out[3][ni * 2 + o]) - dot).abs() < 1e-5);
        }
    }
}

/// A residual block with a strided and a shuffled path, checked against a
/// composition of the reference functions. This exercises arena reuse
/// across many live tensors.
#[test]
fn multi_node_graph_matches_composed_references() {
    let dev = device(4, true);
    let mut rng = Rng::seed_from_u64(21);
    let (c, h, w) = (4usize, 8usize, 10usize);
    let x = random_vec(&mut rng, c * h * w);
    let w1 = random_vec(&mut rng, c * c * 9);
    let w2 = random_vec(&mut rng, 4 * c * c * 9);
    let mut g = Graph::new(GraphRole::Main);
    let xi = g.input("x", InputKind::Spatial { channels: c as u32, spacing_log2: 0 });
    let p1 = g.param("w1", &[c as u32, c as u32, 3, 3]);
    let p2 = g.param("w2", &[4 * c as u32, c as u32, 3, 3]);
    let a = g.node(
        Op::Conv2d { out_channels: c as u32, kernel: 3, stride: 1, depthwise: false, bias: false },
        &[xi, p1],
    );
    let a = g.node(Op::Activation(Activation::Relu), &[a]);
    let r = g.node(Op::Add, &[a, xi]);
    let d = g.node(
        Op::Conv2d { out_channels: 4 * c as u32, kernel: 3, stride: 2, depthwise: false, bias: false },
        &[r, p2],
    );
    let y = g.node(Op::PixelShuffle { factor: 2 }, &[d]);
    let y = g.node(Op::Add, &[y, r]);
    g.output("y", y, OutputKind::Tensor);
    let got = run(
        &dev,
        &g,
        &[In::Tensor(sp(1, c as u32, h as u32, w as u32), x.clone())],
        &[w1.clone(), w2.clone()],
    )
    .unwrap()
    .remove(0);

    let a = conv_ref(&x, (1, c, h, w), &w1, None, c, 3, 1, false);
    let r: Vec<f32> = a.iter().zip(&x).map(|(v, xv)| v.max(0.0) + xv).collect();
    let d = conv_ref(&r, (1, c, h, w), &w2, None, 4 * c, 3, 2, false);
    let mut want = vec![0.0; c * h * w];
    for co in 0..c {
        for yy in 0..h {
            for xx in 0..w {
                let src_c = co * 4 + (yy % 2) * 2 + xx % 2;
                let i = (co * h + yy) * w + xx;
                want[i] = d[(src_c * (h / 2) + yy / 2) * (w / 2) + xx / 2] + r[i];
            }
        }
    }
    assert_close(&got, &want, 1e-4);
}

// ---------- memory, bindings, failures ----------

#[test]
fn memory_requirement_is_exact_and_enforced() {
    let dev = device(1, false);
    let g = single_op_graph(Op::Activation(Activation::Relu), 2, &[]);
    let shapes = [sp(1, 2, 8, 8)];
    let req = dev.memory_requirement(&g, &shapes, Precision::F32).unwrap();
    let exe = dev.compile(&g, &shapes, Precision::F32).unwrap();
    assert_eq!(req, exe.memory());
    assert_eq!(req.arena_bytes, 512, "2·8·8 floats = 512 bytes, already 256-aligned");

    let mut q = dev.create_queue().unwrap();
    let x = dev.allocate(512, MemoryKind::Device).unwrap();
    let out = dev.allocate(512, MemoryKind::Device).unwrap();
    let small = dev.allocate(req.arena_bytes - 4, MemoryKind::Device).unwrap();
    let bind =
        |arena| Bindings { inputs: vec![Binding::Buffer(&x)], params: vec![], outputs: vec![&out], arena };
    let e = q.execute(exe.as_ref(), &bind(&small)).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::InvalidInput);
    let exact = dev.allocate(req.arena_bytes, MemoryKind::Device).unwrap();
    q.execute(exe.as_ref(), &bind(&exact)).unwrap();
    // The arena must not alias an output.
    let e = q.execute(
        exe.as_ref(),
        &Bindings { inputs: vec![Binding::Buffer(&x)], params: vec![], outputs: vec![&exact], arena: &exact },
    );
    assert_eq!(e.unwrap_err().kind(), ErrorKind::InvalidInput);
    // Wrong number of bindings.
    let e = q.execute(
        exe.as_ref(),
        &Bindings { inputs: vec![], params: vec![], outputs: vec![&out], arena: &exact },
    );
    assert_eq!(e.unwrap_err().kind(), ErrorKind::InvalidInput);
}

#[test]
fn f16_is_reported_unsupported() {
    let g = single_op_graph(Op::Activation(Activation::Relu), 1, &[]);
    let Err(e) = device(1, false).compile(&g, &[sp(1, 1, 2, 2)], Precision::F16) else {
        panic!("f16 must be rejected");
    };
    assert_eq!(e.kind(), ErrorKind::Unsupported);
}

#[test]
fn emulated_capacity_gives_recoverable_oom_and_accounting_returns_to_zero() {
    let dev =
        CpuBackend::new(CpuConfig { threads: 1, strict: false, memory_limit: Some(1_000) }).device().unwrap();
    let a = dev.allocate(800, MemoryKind::Device).unwrap();
    let e = dev.allocate(400, MemoryKind::Device).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Device(DeviceErrorKind::OutOfMemory));
    assert_eq!(dev.memory_status().allocated, 800, "a failed allocation leaves no residue");
    let b = dev.allocate(200, MemoryKind::HostStaging).unwrap();
    assert_eq!(dev.memory_status().allocated, 1_000);
    drop((a, b));
    assert_eq!(dev.memory_status().allocated, 0);
}

// ---------- strict mode ----------

#[test]
fn strict_mode_detects_missing_event_dependencies() {
    let dev = device(1, true);
    let g = single_op_graph(Op::Activation(Activation::Relu), 1, &[]);
    let exe = dev.compile(&g, &[sp(1, 1, 4, 4)], Precision::F32).unwrap();
    let x = dev.allocate(64, MemoryKind::Device).unwrap();
    let out = dev.allocate(64, MemoryKind::Device).unwrap();
    let arena = dev.allocate(256, MemoryKind::Device).unwrap();
    let bind =
        || Bindings { inputs: vec![Binding::Buffer(&x)], params: vec![], outputs: vec![&out], arena: &arena };

    let mut producer = dev.create_queue().unwrap();
    let mut consumer = dev.create_queue().unwrap();
    producer.upload(&x, &[1.0; 16]).unwrap();
    let e = consumer.execute(exe.as_ref(), &bind()).unwrap_err();
    assert!(e.message().contains("read-after-write"), "{e}");

    let ev = producer.signal();
    consumer.wait(ev).unwrap();
    consumer.execute(exe.as_ref(), &bind()).unwrap();

    // The consumer read `x`; overwriting it from the producer without
    // waiting on the consumer is a write-after-read hazard.
    let e = producer.upload(&x, &[2.0; 16]).unwrap_err();
    assert!(e.message().contains("write-after-read"), "{e}");
    let ev = consumer.signal();
    producer.wait(ev).unwrap();
    producer.upload(&x, &[2.0; 16]).unwrap();
}

#[test]
fn rejected_submissions_leave_no_hazard_record() {
    let dev = device(1, true);
    let g = single_op_graph(Op::Activation(Activation::Relu), 1, &[]);
    let exe = dev.compile(&g, &[sp(1, 1, 4, 4)], Precision::F32).unwrap();
    let x = dev.allocate(64, MemoryKind::Device).unwrap();
    let out = dev.allocate(64, MemoryKind::Device).unwrap();
    let tiny_arena = dev.allocate(4, MemoryKind::Device).unwrap();
    let mut a = dev.create_queue().unwrap();
    let mut b = dev.create_queue().unwrap();
    // Invalid submission on `a` (arena too small): rejected before recording.
    let bad = Bindings {
        inputs: vec![Binding::Buffer(&x)],
        params: vec![],
        outputs: vec![&out],
        arena: &tiny_arena,
    };
    assert_eq!(a.execute(exe.as_ref(), &bad).unwrap_err().kind(), ErrorKind::InvalidInput);
    // So `b` may write `out` without waiting on `a`.
    b.upload(&out, &[0.0; 16]).unwrap();
}

#[test]
fn non_strict_mode_does_not_track() {
    let dev = device(1, false);
    let x = dev.allocate(16, MemoryKind::Device).unwrap();
    let mut a = dev.create_queue().unwrap();
    let mut b = dev.create_queue().unwrap();
    a.upload(&x, &[1.0; 4]).unwrap();
    assert_eq!(b.download(&x).unwrap().wait().unwrap(), vec![1.0; 4]);
}

// ---------- exact tiling (end-to-end check of the locality analysis) ----------

/// Runs a small network on a whole image and on tiles, where each tile
/// covers a core plus the halo derived by `locality`, clipped at the image
/// border. The cores of the tiled results must equal the whole-image result
/// **bit for bit**.
#[test]
fn tiled_execution_is_bit_exact_with_derived_halo() {
    let dev = device(2, false);
    let mut rng = Rng::seed_from_u64(0x711e);
    let c = 3u32;
    let mut g = Graph::new(GraphRole::Main);
    let xi = g.input("x", InputKind::Spatial { channels: c, spacing_log2: 0 });
    let mut params = Vec::new();
    let mut conv =
        |g: &mut Graph, v: ValueRef, cin: u32, cout: u32, k: u32, s: u32, params: &mut Vec<Vec<f32>>| {
            let id = params.len();
            let wp = g.param(format!("w{id}"), &[cout, cin, k, k]);
            params.push(random_vec(&mut rng, (cout * cin * k * k) as usize));
            let bp = g.param(format!("b{id}"), &[cout]);
            params.push(random_vec(&mut rng, cout as usize));
            g.node(
                Op::Conv2d { out_channels: cout, kernel: k, stride: s, depthwise: false, bias: true },
                &[v, wp, bp],
            )
        };
    let a = conv(&mut g, xi, c, 8, 3, 1, &mut params);
    let a = g.node(Op::Activation(Activation::Gelu), &[a]);
    let d = conv(&mut g, a, 8, 16, 3, 2, &mut params);
    let d = g.node(Op::Activation(Activation::Silu), &[d]);
    let u = conv(&mut g, d, 16, 32, 5, 1, &mut params);
    let u = g.node(Op::PixelShuffle { factor: 2 }, &[u]);
    let m = g.node(Op::Add, &[u, a]);
    let o = conv(&mut g, m, 8, c, 3, 1, &mut params);
    g.output("y", o, OutputKind::Tensor);

    let loc = locality(&g).unwrap();
    let halo = loc.max_halo();
    let align = loc.alignment;
    assert_eq!(align, 2);
    // Hand check: 1 (conv3) + 1 (conv3 s2) + 2·2 (conv5 at spacing 2)
    // + 1 (shuffle) + 1 (final conv3) = 8.
    assert_eq!(halo, 8);

    let (h, w) = (38u32, 46u32);
    let x = random_vec(&mut rng, (c * h * w) as usize);
    let whole = run(&dev, &g, &[In::Tensor(sp(1, c, h, w), x.clone())], &params).unwrap().remove(0);

    let (core_h, core_w) = (12u32, 16u32);
    let halo_a = halo.div_ceil(align) * align;
    let mut covered = vec![false; (h * w) as usize];
    for ty in (0..h).step_by(core_h as usize) {
        for tx in (0..w).step_by(core_w as usize) {
            let (cy1, cx1) = ((ty + core_h).min(h), (tx + core_w).min(w));
            let (y0, x0) = (ty.saturating_sub(halo_a), tx.saturating_sub(halo_a));
            let (y1, x1) = ((cy1 + halo_a).min(h), (cx1 + halo_a).min(w));
            let (th, tw) = (y1 - y0, x1 - x0);
            let mut tile = Vec::with_capacity((c * th * tw) as usize);
            for ci in 0..c {
                for y in y0..y1 {
                    let row = ((ci * h + y) * w) as usize;
                    tile.extend_from_slice(&x[row + x0 as usize..row + x1 as usize]);
                }
            }
            let out = run(&dev, &g, &[In::Tensor(sp(1, c, th, tw), tile)], &params).unwrap().remove(0);
            for ci in 0..c {
                for y in ty..cy1 {
                    for xx in tx..cx1 {
                        let t = out[((ci * th + (y - y0)) * tw + (xx - x0)) as usize];
                        let wv = whole[((ci * h + y) * w + xx) as usize];
                        assert_eq!(t.to_bits(), wv.to_bits(), "channel {ci} pixel ({y}, {xx})");
                        covered[(y * w + xx) as usize] = true;
                    }
                }
            }
        }
    }
    assert!(covered.iter().all(|&v| v));

    // Control: with too small a halo, the tile interiors differ, which shows
    // that the test can detect a seam.
    let small = 2u32;
    let (y0, y1) = (12 - small, 24 + small);
    let (x0, x1) = (16 - small, 32 + small);
    let (th, tw) = (y1 - y0, x1 - x0);
    let mut tile = Vec::new();
    for ci in 0..c {
        for y in y0..y1 {
            let row = ((ci * h + y) * w) as usize;
            tile.extend_from_slice(&x[row + x0 as usize..row + x1 as usize]);
        }
    }
    let out = run(&dev, &g, &[In::Tensor(sp(1, c, th, tw), tile)], &params).unwrap().remove(0);
    let differs = (12..24).any(|y| {
        (16..32).any(|xx| out[((y - y0) * tw + (xx - x0)) as usize] != whole[(y * w + xx) as usize])
    });
    assert!(differs, "an insufficient halo must be detectable");
}
