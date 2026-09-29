//! Tests for validation, shape inference, locality and memory planning.

use sf_core::{ErrorKind, Rng};

use crate::*;

fn img(c: u32) -> InputKind {
    InputKind::Spatial { channels: c, spacing_log2: 0 }
}

fn sp(n: u32, c: u32, h: u32, w: u32) -> Shape {
    Shape::Spatial { n, c, h, w }
}

/// Adds a conv node with fresh parameters.
fn conv(g: &mut Graph, x: ValueRef, cin: u32, cout: u32, k: u32, stride: u32) -> ValueRef {
    let id = g.params.len();
    let w = g.param(format!("w{id}"), &[cout, cin, k, k]);
    let b = g.param(format!("b{id}"), &[cout]);
    g.node(Op::Conv2d { out_channels: cout, kernel: k, stride, depthwise: false, bias: true }, &[x, w, b])
}

fn kind_of(r: sf_core::Result<impl std::fmt::Debug>) -> ErrorKind {
    r.expect_err("expected an error").kind()
}

// ---------- validation ----------

#[test]
fn rejects_bad_references_and_arity() {
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    g.node(Op::Add, &[x, ValueRef::Node(5)]);
    g.output("y", ValueRef::Node(0), OutputKind::Tensor);
    assert_eq!(kind_of(validate(&g)), ErrorKind::ModelInvalid, "forward reference");

    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    let y = g.node(Op::Add, &[x]);
    g.output("y", y, OutputKind::Tensor);
    assert_eq!(kind_of(validate(&g)), ErrorKind::ModelInvalid, "arity");

    let mut g = Graph::new(GraphRole::Main);
    g.input("x", img(3));
    assert_eq!(kind_of(validate(&g)), ErrorKind::ModelInvalid, "no outputs");
}

#[test]
fn rejects_parameters_in_the_wrong_slots() {
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    let w = g.param("w", &[3, 3, 3, 3]);
    // Weight given as data operand, data given as weight.
    let y =
        g.node(Op::Conv2d { out_channels: 3, kernel: 3, stride: 1, depthwise: false, bias: false }, &[w, x]);
    g.output("y", y, OutputKind::Tensor);
    assert_eq!(kind_of(validate(&g)), ErrorKind::ModelInvalid);
}

#[test]
fn rejects_duplicate_names_and_empty_dims() {
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    g.input("x", img(1));
    g.output("y", x, OutputKind::Tensor);
    assert_eq!(kind_of(validate(&g)), ErrorKind::ModelInvalid);

    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    g.param("p", &[3, 0]);
    g.output("y", x, OutputKind::Tensor);
    assert_eq!(kind_of(validate(&g)), ErrorKind::ModelInvalid);
}

#[test]
fn main_role_forbids_reductions_on_tensor_paths_only() {
    let build = |role, kind| {
        let mut g = Graph::new(role);
        let x = g.input("x", img(4));
        let m = g.node(Op::GlobalMean, &[x]);
        let one = g.param("one", &[4]);
        let y = g.node(Op::AffineChannel, &[x, m, one]);
        g.output("y", y, kind);
        g
    };
    assert_eq!(kind_of(validate(&build(GraphRole::Main, OutputKind::Tensor))), ErrorKind::ModelInvalid);
    validate(&build(GraphRole::Main, OutputKind::Statistics)).unwrap();
    validate(&build(GraphRole::Context, OutputKind::Tensor)).unwrap();
}

// ---------- shape inference ----------

#[test]
fn infers_convolution_and_resampling_shapes() {
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    let a = conv(&mut g, x, 3, 16, 3, 2);
    let b = g.node(Op::PixelUnshuffle2, &[a]);
    let c = conv(&mut g, b, 64, 12, 1, 1);
    let d = g.node(Op::PixelShuffle2, &[c]);
    let e = g.node(Op::UpsampleNearest2, &[d]);
    g.output("y", e, OutputKind::Tensor);
    let s = infer_shapes(&g, &[sp(2, 3, 32, 48)]).unwrap();
    assert_eq!(
        s.nodes,
        vec![sp(2, 16, 16, 24), sp(2, 64, 8, 12), sp(2, 12, 8, 12), sp(2, 3, 16, 24), sp(2, 3, 32, 48)]
    );
}

#[test]
fn shape_errors() {
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    let y = conv(&mut g, x, 3, 8, 3, 2);
    g.output("y", y, OutputKind::Tensor);
    assert_eq!(kind_of(infer_shapes(&g, &[sp(1, 3, 7, 8)])), ErrorKind::ModelInvalid, "odd size, stride 2");
    assert_eq!(kind_of(infer_shapes(&g, &[sp(1, 4, 8, 8)])), ErrorKind::InvalidInput, "channel mismatch");
    assert_eq!(kind_of(infer_shapes(&g, &[])), ErrorKind::InvalidInput, "missing input");

    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    let y = conv(&mut g, x, 4, 8, 3, 1); // weight declares 4 input channels
    g.output("y", y, OutputKind::Tensor);
    assert_eq!(kind_of(infer_shapes(&g, &[sp(1, 3, 8, 8)])), ErrorKind::ModelInvalid, "weight dims");
}

#[test]
fn infers_channel_vector_and_crop_ops() {
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(4));
    let cond = g.input("cond", InputKind::Vector { channels: 4 });
    let s = g.input("s", InputKind::Scalar);
    let shift = g.param("shift", &[4]);
    let a = g.node(Op::AffineChannel, &[x, cond, shift]);
    let dw = g.param("dw", &[4, 1, 3, 3]);
    let b =
        g.node(Op::Conv2d { out_channels: 4, kernel: 3, stride: 1, depthwise: true, bias: false }, &[a, dw]);
    let cat = g.node(Op::Concat, &[a, b, x]);
    let sl = g.node(Op::SliceChannels { start: 2, len: 6 }, &[cat]);
    let sc = g.node(Op::ScaleScalar, &[sl, s]);
    let cr = g.node(Op::Crop { top: 1, left: 2, bottom: 3, right: 0 }, &[sc]);
    g.output("y", cr, OutputKind::Tensor);
    let shapes = infer_shapes(&g, &[sp(2, 4, 10, 10), Shape::Vector { n: 2, c: 4 }, Shape::Scalar]).unwrap();
    assert_eq!(shapes.nodes[2], sp(2, 12, 10, 10));
    assert_eq!(shapes.nodes[5], sp(2, 6, 6, 8));
    // A vector batch of 3 does not broadcast to a batch of 2; the operator
    // that detects it is named in the error.
    let bad = infer_shapes(&g, &[sp(2, 4, 10, 10), Shape::Vector { n: 3, c: 4 }, Shape::Scalar]);
    let e = bad.unwrap_err();
    assert_eq!(e.kind(), ErrorKind::ModelInvalid);
    assert!(e.message().contains("affine_channel"), "{e}");
}

#[test]
fn context_graph_with_linear_head() {
    let mut g = Graph::new(GraphRole::Context);
    let x = g.input("patches", img(3));
    let f = conv(&mut g, x, 3, 8, 3, 2);
    let m = g.node(Op::GlobalMean, &[f]);
    let w = g.param("fc_w", &[5, 8]);
    let b = g.param("fc_b", &[5]);
    let d = g.node(Op::Linear { out_features: 5, bias: true }, &[m, w, b]);
    g.output("descriptor", d, OutputKind::Tensor);
    let s = infer_shapes(&g, &[sp(4, 3, 64, 64)]).unwrap();
    assert_eq!(s.nodes[2], Shape::Vector { n: 4, c: 5 });
}

// ---------- locality (expected values derived by hand in the comments) ----------

#[test]
fn locality_of_stacked_convolutions() {
    // conv3 → conv3: each adds k/2 = 1 at spacing 1 → radius 2.
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    let a = conv(&mut g, x, 3, 8, 3, 1);
    let b = conv(&mut g, a, 8, 3, 3, 1);
    g.output("y", b, OutputKind::Tensor);
    let l = locality(&g).unwrap();
    assert_eq!(l.outputs, vec![Some(OutputLocality { spacing_log2: 0, radius: 2.0 })]);
    assert_eq!((l.alignment, l.max_halo()), (1, 2));
}

#[test]
fn locality_through_strided_and_shuffled_paths() {
    // conv3 s2: r = 0 + 1·1 = 1, spacing 2.
    // conv3 at spacing 2: r = 1 + 1·2 = 3.
    // pixel shuffle: r = 3 + 2/2 = 4, spacing back to 1. Alignment 2.
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    let a = conv(&mut g, x, 3, 8, 3, 2);
    let b = conv(&mut g, a, 8, 12, 3, 1);
    let c = g.node(Op::PixelShuffle2, &[b]);
    g.output("y", c, OutputKind::Tensor);
    let l = locality(&g).unwrap();
    assert_eq!(l.outputs[0], Some(OutputLocality { spacing_log2: 0, radius: 4.0 }));
    assert_eq!(l.alignment, 2);
}

#[test]
fn locality_of_a_4x_upscaler() {
    // conv3: 1 · upsample: 1 + 1/2 = 1.5 (spacing 1/2) · conv3: 1.5 + 0.5 = 2
    // · upsample: 2 + 0.25 = 2.25 (spacing 1/4) · conv3: 2.25 + 0.25 = 2.5.
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    let a = conv(&mut g, x, 3, 8, 3, 1);
    let b = g.node(Op::UpsampleNearest2, &[a]);
    let c = conv(&mut g, b, 8, 8, 3, 1);
    let d = g.node(Op::UpsampleNearest2, &[c]);
    let e = conv(&mut g, d, 8, 3, 3, 1);
    g.output("y", e, OutputKind::Tensor);
    let l = locality(&g).unwrap();
    assert_eq!(l.outputs[0], Some(OutputLocality { spacing_log2: -2, radius: 2.5 }));
    assert_eq!((l.alignment, l.max_halo()), (1, 3));
}

#[test]
fn locality_skip_connection_takes_the_maximum() {
    // pool → upsample gives r = 0 + 2/2 = 1; adding x (r = 0) keeps 1.
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    let p = g.node(Op::AvgPool2, &[x]);
    let u = g.node(Op::UpsampleNearest2, &[p]);
    let y = g.node(Op::Add, &[u, x]);
    g.output("y", y, OutputKind::Tensor);
    let l = locality(&g).unwrap();
    assert_eq!(l.outputs[0], Some(OutputLocality { spacing_log2: 0, radius: 1.0 }));
    assert_eq!(l.alignment, 2);
}

#[test]
fn locality_rejects_mixed_spacings_and_honours_map_inputs() {
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    let p = g.node(Op::AvgPool2, &[x]);
    let y = g.node(Op::Add, &[p, x]);
    g.output("y", y, OutputKind::Tensor);
    assert_eq!(kind_of(locality(&g)), ErrorKind::ModelInvalid);

    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(3));
    g.input("m", InputKind::Spatial { channels: 1, spacing_log2: 4 });
    g.output("y", x, OutputKind::Tensor);
    assert_eq!(locality(&g).unwrap().alignment, 16, "a 1/16-resolution map forces 16-pixel alignment");
}

// ---------- memory planning ----------

#[test]
fn chain_reuses_memory() {
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("x", img(8));
    let mut v = x;
    for _ in 0..6 {
        v = conv(&mut g, v, 8, 8, 3, 1);
    }
    g.output("y", v, OutputKind::Tensor);
    let s = infer_shapes(&g, &[sp(1, 8, 16, 16)]).unwrap();
    let plan = plan_memory(&g, &s, 4);
    let tensor = 8 * 16 * 16 * 4;
    assert_eq!(plan.peak_live_bytes, 2 * tensor);
    assert_eq!(plan.arena_bytes, 2 * tensor, "a chain needs only two alternating buffers");
}

fn random_graph(rng: &mut Rng) -> Graph {
    let mut g = Graph::new(GraphRole::Main);
    let mut values = vec![g.input("x", img(4))];
    let count = 2 + rng.below(20) as usize;
    for _ in 0..count {
        let pick = |rng: &mut Rng, vals: &Vec<ValueRef>| vals[rng.below(vals.len() as u64) as usize];
        let a = pick(rng, &values);
        let v = match rng.below(4) {
            0 => conv(&mut g, a, 4, 4, 1 + 2 * rng.below(2) as u32, 1),
            1 => g.node(Op::Activation(Activation::Gelu), &[a]),
            2 => {
                let b = pick(rng, &values);
                g.node(Op::Add, &[a, b])
            }
            _ => {
                let p = g.node(Op::AvgPool2, &[a]);
                g.node(Op::UpsampleNearest2, &[p])
            }
        };
        values.push(v);
    }
    let outputs = 1 + rng.below(3);
    for k in 0..outputs {
        let v = values[1 + rng.below(values.len() as u64 - 1) as usize];
        g.output(format!("out{k}"), v, OutputKind::Tensor);
    }
    g
}

/// Property: tensors whose lifetimes overlap never share bytes, every slot
/// fits in the arena, and graph outputs stay live to the end.
#[test]
fn property_memory_plan_is_collision_free() {
    let mut rng = Rng::seed_from_u64(0x3e30_0001);
    for _ in 0..500 {
        let g = random_graph(&mut rng);
        let h = 2 * (1 + rng.below(8) as u32);
        let s = infer_shapes(&g, &[sp(1, 4, h, h + 2)]).unwrap();
        let plan = plan_memory(&g, &s, 4);
        assert!(plan.arena_bytes >= plan.peak_live_bytes);
        for (i, a) in plan.slots.iter().enumerate() {
            assert_eq!(a.offset % ARENA_ALIGNMENT, 0);
            assert!(a.offset + a.bytes <= plan.arena_bytes);
            assert!(a.bytes >= s.nodes[i].elements() * 4);
            for b in &plan.slots[i + 1..] {
                let lifetimes_overlap = a.first_use <= b.last_use && b.first_use <= a.last_use;
                let bytes_overlap = a.offset < b.offset + b.bytes && b.offset < a.offset + a.bytes;
                assert!(!(lifetimes_overlap && bytes_overlap), "{a:?} collides with {b:?}");
            }
        }
        for out in &g.outputs {
            if let ValueRef::Node(j) = out.value {
                assert_eq!(plan.slots[j as usize].last_use, g.nodes.len());
            }
        }
    }
}
