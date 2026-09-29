//! Tiling tests: plan invariants and bit-exact tiled execution.

use std::sync::Arc;

use sf_compute::cpu::{CpuBackend, CpuConfig};
use sf_compute::{Device, MemoryKind};
use sf_core::{CancelToken, DeviceErrorKind, ErrorKind, NoProgress, Rng, Size};
use sf_graph::{Activation, Graph, GraphRole, InputKind, Op, OutputKind, ValueRef, locality};

use super::*;
use crate::vram::VramManager;

fn check_plan(p: &TilePlan, geom: TileGeometry) {
    let a = geom.alignment.max(1);
    let (w, h) = (p.image.width, p.image.height);
    assert_eq!(w % a, 0);
    assert_eq!(h % a, 0);
    let mut owner = vec![0u8; (w * h) as usize];
    for t in &p.tiles {
        let (c, win) = (t.core, t.window);
        assert_eq!(win.size(), p.window, "uniform windows");
        assert!(win.x() % a == 0 && win.y() % a == 0, "aligned origins");
        assert!(win.right() <= w && win.bottom() <= h, "window inside image");
        assert!(win.contains(c), "window contains core");
        assert!(c.x() - win.x() >= p.halo || win.x() == 0, "left context {t:?}");
        assert!(c.y() - win.y() >= p.halo || win.y() == 0, "top context {t:?}");
        assert!(win.right() - c.right() >= p.halo || win.right() == w, "right context {t:?}");
        assert!(win.bottom() - c.bottom() >= p.halo || win.bottom() == h, "bottom context {t:?}");
        for y in c.y()..c.bottom() {
            for x in c.x()..c.right() {
                owner[(y * w + x) as usize] += 1;
            }
        }
    }
    assert!(owner.iter().all(|&n| n == 1), "cores partition the image exactly");
}

#[test]
fn property_plans_satisfy_invariants() {
    let mut rng = Rng::seed_from_u64(0x7_11e5);
    for _ in 0..600 {
        let img = Size::new(1 + rng.below(300) as u32, 1 + rng.below(300) as u32);
        let core = Size::new(1 + rng.below(128) as u32, 1 + rng.below(128) as u32);
        let geom = TileGeometry {
            halo: rng.below(24) as u32,
            alignment: [1, 2, 4, 8][rng.below(4) as usize],
            scale: 1,
        };
        let mode =
            if rng.below(2) == 0 { TileMode::Exact } else { TileMode::Blended { halo: rng.below(8) as u32 } };
        let p = plan(img, core, geom, mode).unwrap();
        check_plan(&p, geom);
        let first = p.tiles[0].core;
        assert_eq!((first.x(), first.y()), (0, 0));
    }
}

#[test]
fn reflection_padding() {
    let p = Planar { channels: 1, width: 3, height: 2, data: vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0] };
    let q = p.pad_reflect(Size::new(5, 3));
    assert_eq!(q.data, vec![1.0, 2.0, 3.0, 2.0, 1.0, 4.0, 5.0, 6.0, 5.0, 4.0, 1.0, 2.0, 3.0, 2.0, 1.0]);
}

struct Model {
    graph: Graph,
    params: Vec<Vec<f32>>,
}

/// A small network with strided, shuffled and (optionally) upscaling paths.
fn model(rng: &mut Rng, upscale: bool) -> Model {
    let mut g = Graph::new(GraphRole::Main);
    let mut params = Vec::new();
    let x = g.input("x", InputKind::Spatial { channels: 3, spacing_log2: 0 });
    let mut conv =
        |g: &mut Graph, v: ValueRef, cin: u32, cout: u32, k: u32, s: u32, params: &mut Vec<Vec<f32>>| {
            let id = params.len();
            let w = g.param(format!("w{id}"), &[cout, cin, k, k]);
            params.push((0..cout * cin * k * k).map(|_| rng.range_f64(-0.3, 0.3) as f32).collect());
            let b = g.param(format!("b{id}"), &[cout]);
            params.push((0..cout).map(|_| rng.range_f64(-0.1, 0.1) as f32).collect());
            g.node(
                Op::Conv2d { out_channels: cout, kernel: k, stride: s, depthwise: false, bias: true },
                &[v, w, b],
            )
        };
    let a = conv(&mut g, x, 3, 8, 3, 1, &mut params);
    let a = g.node(Op::Activation(Activation::LeakyRelu(0.2)), &[a]);
    let d = conv(&mut g, a, 8, 16, 3, 2, &mut params);
    let d = conv(&mut g, d, 16, 32, 3, 1, &mut params);
    let u = g.node(Op::PixelShuffle { factor: 2 }, &[d]);
    let m = g.node(Op::Add, &[u, a]);
    let out = if upscale {
        let up = g.node(Op::UpsampleNearest2, &[m]);
        conv(&mut g, up, 8, 3, 3, 1, &mut params)
    } else {
        conv(&mut g, m, 8, 3, 3, 1, &mut params)
    };
    g.output("y", out, OutputKind::Tensor);
    Model { graph: g, params }
}

fn manager(capacity: Option<u64>) -> VramManager {
    let dev: Arc<dyn Device> =
        CpuBackend::new(CpuConfig { threads: 2, strict: true, memory_limit: capacity }).device().unwrap();
    VramManager::new(dev, None, 0)
}

fn upload_params(
    vram: &VramManager,
    params: &[Vec<f32>],
) -> (Vec<crate::vram::TrackedBuffer>, sf_compute::Event) {
    let mut q = vram.device().create_queue().unwrap();
    let bufs = params
        .iter()
        .map(|p| {
            let b = vram.allocate(Pool::Weights, p.len() as u64 * 4).unwrap();
            q.upload(b.buffer(), p).unwrap();
            b
        })
        .collect();
    (bufs, q.signal())
}

fn image(rng: &mut Rng, w: usize, h: usize) -> Planar {
    Planar { channels: 3, width: w, height: h, data: (0..3 * w * h).map(|_| rng.next_f64() as f32).collect() }
}

#[test]
fn exact_tiling_is_bit_identical_to_a_whole_image_run() {
    let mut rng = Rng::seed_from_u64(0x7_11e6);
    for upscale in [false, true] {
        let m = model(&mut rng, upscale);
        let loc = locality(&m.graph).unwrap();
        let geom = TileGeometry {
            halo: loc.max_halo(),
            alignment: loc.alignment,
            scale: if upscale { 2 } else { 1 },
        };
        let vram = manager(None);
        let (weights, ready) = upload_params(&vram, &m.params);
        let refs: Vec<&Buffer> = weights.iter().map(|b| b.buffer()).collect();
        let img = image(&mut rng, 70, 53);
        let canon = canonical_size(Size::new(70, 53), geom.alignment).unwrap();
        let input = img.pad_reflect(canon);
        let whole = plan(canon, canon, geom, TileMode::Exact).unwrap();
        assert_eq!(whole.tiles.len(), 1);
        let reference = run_tiled(
            &vram,
            &m.graph,
            &refs,
            &[ready],
            &[],
            &input,
            &whole,
            &CancelToken::new(),
            &NoProgress,
        )
        .unwrap();
        for core in [Size::new(16, 16), Size::new(24, 10), Size::new(40, 32)] {
            let p = plan(canon, core, geom, TileMode::Exact).unwrap();
            assert!(p.tiles.len() > 1);
            let tiled = run_tiled(
                &vram,
                &m.graph,
                &refs,
                &[ready],
                &[],
                &input,
                &p,
                &CancelToken::new(),
                &NoProgress,
            )
            .unwrap();
            let same = tiled.data.iter().zip(&reference.data).all(|(a, b)| a.to_bits() == b.to_bits());
            assert!(same, "upscale={upscale} core={core:?}");
        }
        drop(weights);
        assert_eq!(vram.usage().total(), 0);
    }
}

#[test]
fn blended_tiling_deviation_is_measurable_and_small() {
    let mut rng = Rng::seed_from_u64(0x7_11e7);
    let m = model(&mut rng, false);
    let loc = locality(&m.graph).unwrap();
    let geom = TileGeometry { halo: loc.max_halo(), alignment: loc.alignment, scale: 1 };
    let vram = manager(None);
    let (weights, ready) = upload_params(&vram, &m.params);
    let refs: Vec<&Buffer> = weights.iter().map(|b| b.buffer()).collect();
    let canon = canonical_size(Size::new(64, 64), geom.alignment).unwrap();
    let input = image(&mut rng, 64, 64);
    let whole = run_tiled(
        &vram,
        &m.graph,
        &refs,
        &[ready],
        &[],
        &input,
        &plan(canon, canon, geom, TileMode::Exact).unwrap(),
        &CancelToken::new(),
        &NoProgress,
    )
    .unwrap();
    let p = plan(canon, Size::new(16, 16), geom, TileMode::Blended { halo: 2 }).unwrap();
    let blended =
        run_tiled(&vram, &m.graph, &refs, &[ready], &[], &input, &p, &CancelToken::new(), &NoProgress)
            .unwrap();
    let max_dev = blended.data.iter().zip(&whole.data).map(|(a, b)| (a - b).abs()).fold(0f32, f32::max);
    let range = whole.data.iter().fold(0f32, |m, v| m.max(v.abs()));
    assert!(max_dev > 0.0, "a halo below the receptive radius is not exact");
    assert!(max_dev < 0.5 * range, "deviation {max_dev} vs range {range}");
}

#[test]
fn out_of_memory_is_reported_and_smaller_tiles_succeed() {
    let mut rng = Rng::seed_from_u64(0x7_11e8);
    let m = model(&mut rng, false);
    let loc = locality(&m.graph).unwrap();
    let geom = TileGeometry { halo: loc.max_halo(), alignment: loc.alignment, scale: 1 };
    let params_bytes: u64 = m.params.iter().map(|p| p.len() as u64 * 4).sum();
    // Capacity for weights plus a modest tile, not for a whole-image window.
    let vram = manager(Some(params_bytes + 600_000));
    let (weights, ready) = upload_params(&vram, &m.params);
    let refs: Vec<&Buffer> = weights.iter().map(|b| b.buffer()).collect();
    let canon = canonical_size(Size::new(160, 160), geom.alignment).unwrap();
    let input = image(&mut rng, 160, 160);
    let big = plan(canon, canon, geom, TileMode::Exact).unwrap();
    let e = run_tiled(&vram, &m.graph, &refs, &[ready], &[], &input, &big, &CancelToken::new(), &NoProgress)
        .unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Device(DeviceErrorKind::OutOfMemory));
    assert_eq!(vram.usage().total(), params_bytes, "failed attempt released everything but weights");
    let small = plan(canon, Size::new(32, 32), geom, TileMode::Exact).unwrap();
    run_tiled(&vram, &m.graph, &refs, &[ready], &[], &input, &small, &CancelToken::new(), &NoProgress)
        .unwrap();
}

#[test]
fn missing_upload_dependency_is_caught_by_strict_mode() {
    let mut rng = Rng::seed_from_u64(0x7_11e9);
    let m = model(&mut rng, false);
    let loc = locality(&m.graph).unwrap();
    let geom = TileGeometry { halo: loc.max_halo(), alignment: loc.alignment, scale: 1 };
    let vram = manager(None);
    let (weights, _ready) = upload_params(&vram, &m.params);
    let refs: Vec<&Buffer> = weights.iter().map(|b| b.buffer()).collect();
    let input = image(&mut rng, 32, 32);
    let p = plan(Size::new(32, 32), Size::new(16, 16), geom, TileMode::Exact).unwrap();
    // Not waiting on the upload event is a data race on a real GPU.
    let e = run_tiled(&vram, &m.graph, &refs, &[], &[], &input, &p, &CancelToken::new(), &NoProgress)
        .unwrap_err();
    assert!(e.message().contains("read-after-write"), "{e}");
}

#[test]
fn cancellation_and_scalar_inputs() {
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", InputKind::Spatial { channels: 3, spacing_log2: 0 });
    let s = g.input("strength", InputKind::Scalar);
    let y = g.node(Op::ScaleScalar, &[x, s]);
    g.output("y", y, OutputKind::Tensor);
    let vram = manager(None);
    let geom = TileGeometry { halo: 0, alignment: 1, scale: 1 };
    let mut rng = Rng::seed_from_u64(1);
    let input = image(&mut rng, 20, 12);
    let p = plan(Size::new(20, 12), Size::new(8, 8), geom, TileMode::Exact).unwrap();
    let out = run_tiled(
        &vram,
        &g,
        &[],
        &[],
        &[ExtraInput::Scalar(0.5)],
        &input,
        &p,
        &CancelToken::new(),
        &NoProgress,
    )
    .unwrap();
    assert!(out.data.iter().zip(&input.data).all(|(o, i)| (o - 0.5 * i).abs() < 1e-7));
    let cancel = CancelToken::new();
    cancel.cancel();
    let e = run_tiled(&vram, &g, &[], &[], &[ExtraInput::Scalar(0.5)], &input, &p, &cancel, &NoProgress)
        .unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Cancelled);
    let _ = MemoryKind::Device;
}
