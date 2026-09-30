//! Import tests. No third-party weight file is available in this
//! environment, so `.pth` inputs are produced by a test writer that follows
//! the format's documented structure. Validation against real published
//! files is still pending (see CHANGELOG).

use std::sync::Arc;

use sf_compute::cpu::{CpuBackend, CpuConfig};
use sf_compute::{Binding, Bindings, Device, MemoryKind, Precision};
use sf_core::{ErrorKind, Limits, Rng};
use sf_graph::{Shape, sfm};

use crate::torch::{StateDict, Tensor, f16_to_f32, test_writer};
use crate::*;

fn t(dims: &[usize], f: impl FnMut(usize) -> f32) -> Tensor {
    let n: usize = dims.iter().product();
    Tensor { dims: dims.to_vec(), data: (0..n).map(f).collect() }
}

#[test]
fn half_precision_conversion() {
    assert_eq!(f16_to_f32(0x3C00), 1.0);
    assert_eq!(f16_to_f32(0xC000), -2.0);
    assert_eq!(f16_to_f32(0x7BFF), 65_504.0);
    assert_eq!(f16_to_f32(0x0001), 2f32.powi(-24));
    assert_eq!(f16_to_f32(0x0200), 2f32.powi(-15));
    assert!(f16_to_f32(0x7C00).is_infinite());
    assert!((f16_to_f32(0x3555) - 1.0 / 3.0).abs() < 1e-3);
}

#[test]
fn pickle_whitelist_blocks_code_execution_globals() {
    // A stream that would call os.system in a normal unpickler.
    let evil = b"\x80\x02cos\nsystem\nX\x02\x00\x00\x00ls\x85R.";
    let e = pickle::load(evil).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Unsupported);
    assert!(e.message().contains("os.system"), "{e}");
    let e = pickle::load(b"\x80\x02cbuiltins\neval\n.").unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Unsupported);
    // Unsupported opcode (INST) and truncation.
    assert_eq!(pickle::load(b"\x80\x02ios\nsystem\n.").unwrap_err().kind(), ErrorKind::Unsupported);
    assert!(pickle::load(b"\x80\x02}").is_err());
}

fn random_sd(rng: &mut Rng) -> StateDict {
    let mut sd = StateDict::new();
    sd.insert("a.weight".into(), t(&[4, 3, 3, 3], |_| rng.range_f64(-1.0, 1.0) as f32));
    sd.insert("a.bias".into(), t(&[4], |i| i as f32));
    sd.insert("big".into(), t(&[300], |i| i as f32 * 0.5));
    sd
}

#[test]
fn pth_round_trip_with_and_without_wrapper() {
    let mut rng = Rng::seed_from_u64(0x9_7a);
    let sd = random_sd(&mut rng);
    for wrap in [false, true] {
        let bytes = test_writer::write(&sd, wrap);
        let back = torch::load(&bytes, &Limits::default()).unwrap();
        assert_eq!(back, sd, "wrap={wrap}");
    }
}

#[test]
fn pth_rejects_legacy_and_garbage() {
    assert_eq!(
        torch::load(b"\x80\x02}q\x00.", &Limits::default()).unwrap_err().kind(),
        ErrorKind::Unsupported
    );
    let mut rng = Rng::seed_from_u64(0x9_7b);
    let base = test_writer::write(&random_sd(&mut rng), true);
    for _ in 0..3_000 {
        let mut d = base.clone();
        for _ in 0..=rng.below(3) {
            let at = rng.below(d.len() as u64) as usize;
            d[at] = rng.next_u64() as u8;
        }
        let _ = torch::load(&d, &Limits::default());
    }
}

/// Runs a single-output graph on the CPU backend.
fn run(model: &sfm::ModelFile, input: &[f32], shape: Shape) -> Vec<f32> {
    let dev: Arc<dyn Device> =
        CpuBackend::new(CpuConfig { threads: 2, strict: false, memory_limit: None }).device().unwrap();
    let exe = dev.compile(&model.graph, &[shape], Precision::F32).unwrap();
    let mut q = dev.create_queue().unwrap();
    let up = |q: &mut Box<dyn sf_compute::Queue>, d: &[f32]| {
        let b = dev.allocate(d.len() as u64 * 4, MemoryKind::Device).unwrap();
        q.upload(&b, d).unwrap();
        b
    };
    let x = up(&mut q, input);
    let params: Vec<_> = model.weights.iter().map(|w| up(&mut q, w)).collect();
    let out_shape = sf_graph::infer_shapes(&model.graph, &[shape])
        .unwrap()
        .value(&model.graph, model.graph.outputs[0].value)
        .unwrap();
    let out = dev.allocate(out_shape.elements() * 4, MemoryKind::Device).unwrap();
    let arena = dev.allocate(exe.memory().arena_bytes.max(4), MemoryKind::Device).unwrap();
    let b = Bindings {
        inputs: vec![Binding::Buffer(&x)],
        params: params.iter().collect(),
        outputs: vec![&out],
        arena: &arena,
    };
    q.execute(exe.as_ref(), &b).unwrap();
    q.download(&out).unwrap().wait().unwrap()
}

fn srvgg_sd(nf: usize, scale: usize, zero_last: bool) -> StateDict {
    let mut sd = StateDict::new();
    let out = 3 * scale * scale;
    sd.insert("body.0.weight".into(), t(&[nf, 3, 3, 3], |i| (i % 7) as f32 * 0.01));
    sd.insert("body.0.bias".into(), t(&[nf], |_| 0.1));
    sd.insert("body.1.weight".into(), t(&[nf], |_| 0.25));
    sd.insert("body.2.weight".into(), t(&[nf, nf, 3, 3], |i| (i % 5) as f32 * 0.01));
    sd.insert("body.2.bias".into(), t(&[nf], |_| 0.0));
    sd.insert("body.3.weight".into(), t(&[nf], |_| 0.25));
    let last = if zero_last { 0.0 } else { 0.01 };
    sd.insert("body.4.weight".into(), t(&[out, nf, 3, 3], |_| last));
    sd.insert("body.4.bias".into(), t(&[out], |_| 0.0));
    sd
}

#[test]
fn srvgg_residual_path_is_nearest_upsampling() {
    // With a zero final convolution the network reduces to its residual:
    // the nearest-upsampled input. This checks shuffle order, the residual
    // and the scale logic end to end.
    for scale in [2usize, 4] {
        let sd = srvgg_sd(4, scale, true);
        let bytes = test_writer::write(&sd, false);
        let imp = import_pth(&bytes, "test", &Limits::default()).unwrap();
        assert_eq!((imp.architecture, imp.scale), ("srvgg", scale as u32));
        let (w, h) = (5usize, 3usize);
        let input: Vec<f32> = (0..3 * w * h).map(|i| (i as f32 * 0.37) % 1.0).collect();
        let out = run(&imp.model, &input, Shape::Spatial { n: 1, c: 3, h: h as u32, w: w as u32 });
        let (ow, oh) = (w * scale, h * scale);
        for c in 0..3 {
            for y in 0..oh {
                for x in 0..ow {
                    let want = input[(c * h + y / scale) * w + x / scale];
                    assert_eq!(out[(c * oh + y) * ow + x], want);
                }
            }
        }
    }
}

fn rrdb_sd(in_ch: usize, nf: usize, gc: usize, blocks: usize, last_bias: f32) -> StateDict {
    let mut sd = StateDict::new();
    let conv = |sd: &mut StateDict, name: &str, cin: usize, cout: usize| {
        sd.insert(format!("{name}.weight"), t(&[cout, cin, 3, 3], |i| ((i % 11) as f32 - 5.0) * 0.002));
        sd.insert(format!("{name}.bias"), t(&[cout], |_| 0.0));
    };
    conv(&mut sd, "conv_first", in_ch, nf);
    for b in 0..blocks {
        for r in 1..=3 {
            for i in 1..=5 {
                let cin = nf + (i - 1) * gc;
                let cout = if i == 5 { nf } else { gc };
                conv(&mut sd, &format!("body.{b}.rdb{r}.conv{i}"), cin, cout);
            }
        }
    }
    for n in ["conv_body", "conv_up1", "conv_up2", "conv_hr"] {
        conv(&mut sd, n, nf, nf);
    }
    sd.insert("conv_last.weight".into(), t(&[3, nf, 3, 3], |_| 0.0));
    sd.insert("conv_last.bias".into(), t(&[3], |_| last_bias));
    sd
}

#[test]
fn rrdbnet_structure_scale_detection_and_execution() {
    for (in_ch, scale) in [(3usize, 4u32), (12, 2), (48, 1)] {
        let sd = rrdb_sd(in_ch, 8, 4, 2, 0.5);
        let imp = import_pth(&test_writer::write(&sd, true), "rrdb-test", &Limits::default()).unwrap();
        assert_eq!((imp.architecture, imp.scale), ("rrdbnet", scale));
        // Every tensor of the state dict is used exactly once.
        assert_eq!(imp.model.weights.len(), sd.len());
        let loc = sf_graph::locality(&imp.model.graph).unwrap();
        assert!(loc.max_halo() > 20, "deep network: large receptive radius {}", loc.max_halo());
        let side = 8u32;
        let input: Vec<f32> = (0..3 * side * side).map(|i| (i % 17) as f32 / 17.0).collect();
        let out = run(&imp.model, &input, Shape::Spatial { n: 1, c: 3, h: side, w: side });
        assert_eq!(out.len(), (3 * side * side * scale * scale) as usize);
        // conv_last has zero weights and bias 0.5, so every output is 0.5.
        assert!(out.iter().all(|&v| (v - 0.5).abs() < 1e-6));
    }
}

#[test]
fn import_records_provenance_and_survives_sfm_round_trip() {
    let bytes = test_writer::write(&srvgg_sd(4, 4, false), false);
    let imp = import_pth(&bytes, "general-x4", &Limits::default()).unwrap();
    let m = &imp.model.metadata;
    assert_eq!(m.get("provenance").and_then(|v| v.as_str()), Some("external"));
    assert_eq!(m.get("licence_scope").and_then(|v| v.as_str()), Some("commercial"));
    assert_eq!(m.get("source_sha256").and_then(|v| v.as_str()).map(str::len), Some(64));
    let file = sfm::write(&imp.model).unwrap();
    assert_eq!(sfm::read(&file, &Limits::default()).unwrap(), imp.model);
}

#[test]
fn unknown_architectures_are_refused() {
    let mut sd = StateDict::new();
    sd.insert("layers.0.attn.qkv.weight".into(), t(&[6, 2], |_| 0.0));
    let e = import_pth(&test_writer::write(&sd, false), "x", &Limits::default()).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Unsupported);
}
