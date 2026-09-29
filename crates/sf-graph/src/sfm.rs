//! The ScaleForge model file format (`.sfm`, ADR-0002).
//!
//! ```text
//! "SFMODEL\0" | format version (u32 LE) | header length (u64 LE) | header (JSON)
//! | zero padding to a 64-byte boundary | tensor blob
//! ```
//!
//! The header holds free-form `metadata`, the `graph` (operators and
//! references, see [`crate::Graph`]) and a `tensors` directory giving each
//! parameter's dtype, blob offset, length and SHA-256, plus a SHA-256 of
//! the whole blob. A model is **pure data**: nothing in it is executed.
//!
//! Before any allocation proportional to declared sizes, loading checks:
//! the magic and version, header size and JSON limits, the graph structure
//! (via [`crate::validate`]), and that every tensor is declared once, has
//! the parameter's exact size, lies inside the blob, is aligned, does not
//! overlap another tensor, and matches its hash.

use sf_core::json::{self, Number, Object, Value};
use sf_core::sha256::sha256_hex;
use sf_core::{Error, Limits, Result};

use crate::graph::{
    Graph, GraphRole, InputDecl, InputKind, Node, OutputDecl, OutputKind, ParamDecl, ValueRef, validate,
};
use crate::op::{Activation, OPSET_VERSION, Op};

/// File magic.
pub const MAGIC: &[u8; 8] = b"SFMODEL\0";
/// Container version written by this implementation.
pub const FORMAT_VERSION: u32 = 1;
const ALIGN: usize = 64;

/// A model: metadata, graph and one weight tensor per parameter.
#[derive(Debug, Clone, PartialEq)]
pub struct ModelFile {
    /// Free-form metadata (name, version, provenance, licence, …).
    pub metadata: Object,
    /// The computation graph.
    pub graph: Graph,
    /// Weights in parameter order, row-major `f32`.
    pub weights: Vec<Vec<f32>>,
}

fn invalid(msg: impl std::fmt::Display) -> Error {
    Error::model_invalid(format!("sfm: {msg}"))
}

// ------------------------------------------------------------- serialise

fn vref(r: ValueRef) -> Value {
    Value::from(match r {
        ValueRef::Input(i) => format!("i{i}"),
        ValueRef::Param(i) => format!("p{i}"),
        ValueRef::Node(i) => format!("n{i}"),
    })
}

fn float(v: f32) -> Value {
    Value::Number(Number::from_f64(f64::from(v)).unwrap_or_else(|| Number::from_u64(0)))
}

fn op_to_json(op: &Op) -> (String, Object) {
    let mut a = Object::new();
    match op {
        Op::Conv2d { out_channels, kernel, stride, depthwise, bias } => {
            a.insert("out_channels", *out_channels);
            a.insert("kernel", *kernel);
            a.insert("stride", *stride);
            a.insert("depthwise", *depthwise);
            a.insert("bias", *bias);
        }
        Op::PixelShuffle { factor } | Op::PixelUnshuffle { factor } => a.insert("factor", *factor),
        Op::Activation(act) => {
            let (name, slope) = match act {
                Activation::Relu => ("relu", None),
                Activation::LeakyRelu(s) => ("leaky_relu", Some(*s)),
                Activation::Gelu => ("gelu", None),
                Activation::Silu => ("silu", None),
                Activation::Sigmoid => ("sigmoid", None),
            };
            a.insert("function", name);
            if let Some(s) = slope {
                a.insert("slope", float(s));
            }
        }
        Op::Clamp { lo, hi } => {
            a.insert("lo", float(*lo));
            a.insert("hi", float(*hi));
        }
        Op::ScaleConst { factor } => a.insert("factor", float(*factor)),
        Op::SliceChannels { start, len } => {
            a.insert("start", *start);
            a.insert("len", *len);
        }
        Op::Crop { top, left, bottom, right } => {
            a.insert("top", *top);
            a.insert("left", *left);
            a.insert("bottom", *bottom);
            a.insert("right", *right);
        }
        Op::Linear { out_features, bias } => {
            a.insert("out_features", *out_features);
            a.insert("bias", *bias);
        }
        _ => {}
    }
    (op.name().to_string(), a)
}

fn graph_to_json(g: &Graph) -> Value {
    let mut o = Object::new();
    o.insert(
        "role",
        match g.role {
            GraphRole::Main => "main",
            GraphRole::Context => "context",
        },
    );
    o.insert(
        "inputs",
        g.inputs
            .iter()
            .map(|d| {
                let mut e = Object::new();
                e.insert("name", d.name.as_str());
                match d.kind {
                    InputKind::Spatial { channels, spacing_log2 } => {
                        e.insert("kind", "spatial");
                        e.insert("channels", channels);
                        e.insert("spacing_log2", i64::from(spacing_log2));
                    }
                    InputKind::Vector { channels } => {
                        e.insert("kind", "vector");
                        e.insert("channels", channels);
                    }
                    InputKind::Scalar => e.insert("kind", "scalar"),
                }
                Value::from(e)
            })
            .collect::<Vec<_>>(),
    );
    o.insert(
        "params",
        g.params
            .iter()
            .map(|p| {
                let mut e = Object::new();
                e.insert("name", p.name.as_str());
                e.insert("dims", p.dims.iter().map(|&d| Value::from(d)).collect::<Vec<_>>());
                Value::from(e)
            })
            .collect::<Vec<_>>(),
    );
    o.insert(
        "nodes",
        g.nodes
            .iter()
            .map(|n| {
                let (name, attrs) = op_to_json(&n.op);
                let mut e = Object::new();
                e.insert("op", name);
                if !attrs.is_empty() {
                    e.insert("attrs", attrs);
                }
                e.insert("inputs", n.inputs.iter().map(|&r| vref(r)).collect::<Vec<_>>());
                Value::from(e)
            })
            .collect::<Vec<_>>(),
    );
    o.insert(
        "outputs",
        g.outputs
            .iter()
            .map(|d| {
                let mut e = Object::new();
                e.insert("name", d.name.as_str());
                e.insert("value", vref(d.value));
                e.insert(
                    "kind",
                    match d.kind {
                        OutputKind::Tensor => "tensor",
                        OutputKind::Statistics => "statistics",
                    },
                );
                Value::from(e)
            })
            .collect::<Vec<_>>(),
    );
    Value::from(o)
}

/// Serialises a model to `.sfm` bytes. The graph is validated first.
pub fn write(model: &ModelFile) -> Result<Vec<u8>> {
    validate(&model.graph)?;
    if model.weights.len() != model.graph.params.len() {
        return Err(invalid("one weight tensor per parameter is required"));
    }
    let mut blob: Vec<u8> = Vec::new();
    let mut tensors = Vec::new();
    for (p, w) in model.graph.params.iter().zip(&model.weights) {
        if w.len() as u64 != p.elements() {
            return Err(invalid(format!("tensor {:?} has {} values, dims {:?}", p.name, w.len(), p.dims)));
        }
        while blob.len() % ALIGN != 0 {
            blob.push(0);
        }
        let offset = blob.len();
        let bytes: Vec<u8> = w.iter().flat_map(|v| v.to_le_bytes()).collect();
        let mut e = Object::new();
        e.insert("param", p.name.as_str());
        e.insert("dtype", "f32");
        e.insert("offset", offset as u64);
        e.insert("length", bytes.len() as u64);
        e.insert("sha256", sha256_hex(&bytes));
        tensors.push(Value::from(e));
        blob.extend(bytes);
    }
    let mut header = Object::new();
    header.insert("format", "scaleforge-model");
    header.insert("opset", OPSET_VERSION);
    header.insert("metadata", model.metadata.clone());
    header.insert("graph", graph_to_json(&model.graph));
    header.insert("tensors", tensors);
    header.insert("data_sha256", sha256_hex(&blob));
    let text = json::to_string(&Value::from(header))?;
    let mut out = MAGIC.to_vec();
    out.extend(FORMAT_VERSION.to_le_bytes());
    out.extend((text.len() as u64).to_le_bytes());
    out.extend(text.as_bytes());
    while out.len() % ALIGN != 0 {
        out.push(0);
    }
    out.extend(blob);
    Ok(out)
}

// ----------------------------------------------------------------- parse

fn field<'a>(o: &'a Value, key: &str) -> Result<&'a Value> {
    o.get(key).ok_or_else(|| invalid(format!("missing field {key:?}")))
}

fn u32_field(o: &Value, key: &str) -> Result<u32> {
    field(o, key)?
        .as_u64()
        .and_then(|v| u32::try_from(v).ok())
        .ok_or_else(|| invalid(format!("{key:?} must be a u32")))
}

fn f32_field(o: &Value, key: &str) -> Result<f32> {
    let v = field(o, key)?.as_f64().ok_or_else(|| invalid(format!("{key:?} must be a number")))?;
    let f = v as f32;
    if f.is_finite() { Ok(f) } else { Err(invalid(format!("{key:?} is out of range"))) }
}

fn bool_field(o: &Value, key: &str) -> Result<bool> {
    field(o, key)?.as_bool().ok_or_else(|| invalid(format!("{key:?} must be a boolean")))
}

fn str_field<'a>(o: &'a Value, key: &str) -> Result<&'a str> {
    field(o, key)?.as_str().ok_or_else(|| invalid(format!("{key:?} must be a string")))
}

fn array<'a>(o: &'a Value, key: &str) -> Result<&'a [Value]> {
    field(o, key)?.as_array().ok_or_else(|| invalid(format!("{key:?} must be an array")))
}

fn parse_ref(v: &Value) -> Result<ValueRef> {
    let s = v.as_str().ok_or_else(|| invalid("a value reference must be a string"))?;
    let (kind, num) = s.split_at(1.min(s.len()));
    let i: u32 = num.parse().map_err(|_| invalid(format!("bad value reference {s:?}")))?;
    match kind {
        "i" => Ok(ValueRef::Input(i)),
        "p" => Ok(ValueRef::Param(i)),
        "n" => Ok(ValueRef::Node(i)),
        _ => Err(invalid(format!("bad value reference {s:?}"))),
    }
}

fn parse_op(name: &str, a: &Value) -> Result<Op> {
    Ok(match name {
        "conv2d" => Op::Conv2d {
            out_channels: u32_field(a, "out_channels")?,
            kernel: u32_field(a, "kernel")?,
            stride: u32_field(a, "stride")?,
            depthwise: bool_field(a, "depthwise")?,
            bias: bool_field(a, "bias")?,
        },
        "avg_pool2" => Op::AvgPool2,
        "upsample_nearest2" => Op::UpsampleNearest2,
        "pixel_shuffle" => Op::PixelShuffle { factor: u32_field(a, "factor")? },
        "pixel_unshuffle" => Op::PixelUnshuffle { factor: u32_field(a, "factor")? },
        "add" => Op::Add,
        "sub" => Op::Sub,
        "mul" => Op::Mul,
        "affine_channel" => Op::AffineChannel,
        "activation" => Op::Activation(match str_field(a, "function")? {
            "relu" => Activation::Relu,
            "leaky_relu" => Activation::LeakyRelu(f32_field(a, "slope")?),
            "gelu" => Activation::Gelu,
            "silu" => Activation::Silu,
            "sigmoid" => Activation::Sigmoid,
            other => return Err(invalid(format!("unknown activation {other:?}"))),
        }),
        "prelu" => Op::PRelu,
        "clamp" => Op::Clamp { lo: f32_field(a, "lo")?, hi: f32_field(a, "hi")? },
        "scale_scalar" => Op::ScaleScalar,
        "scale_const" => Op::ScaleConst { factor: f32_field(a, "factor")? },
        "concat" => Op::Concat,
        "slice_channels" => Op::SliceChannels { start: u32_field(a, "start")?, len: u32_field(a, "len")? },
        "crop" => Op::Crop {
            top: u32_field(a, "top")?,
            left: u32_field(a, "left")?,
            bottom: u32_field(a, "bottom")?,
            right: u32_field(a, "right")?,
        },
        "global_mean" => Op::GlobalMean,
        "linear" => Op::Linear { out_features: u32_field(a, "out_features")?, bias: bool_field(a, "bias")? },
        other => return Err(invalid(format!("operator {other:?} is not in operator set {OPSET_VERSION}"))),
    })
}

fn graph_from_json(v: &Value, limits: &Limits) -> Result<Graph> {
    let role = match str_field(v, "role")? {
        "main" => GraphRole::Main,
        "context" => GraphRole::Context,
        other => return Err(invalid(format!("unknown graph role {other:?}"))),
    };
    let mut g = Graph::new(role);
    for d in array(v, "inputs")? {
        let kind = match str_field(d, "kind")? {
            "spatial" => InputKind::Spatial {
                channels: u32_field(d, "channels")?,
                spacing_log2: field(d, "spacing_log2")?
                    .as_i64()
                    .and_then(|x| i32::try_from(x).ok())
                    .filter(|x| (-8..=8).contains(x))
                    .ok_or_else(|| invalid("spacing_log2 out of range"))?,
            },
            "vector" => InputKind::Vector { channels: u32_field(d, "channels")? },
            "scalar" => InputKind::Scalar,
            other => return Err(invalid(format!("unknown input kind {other:?}"))),
        };
        g.inputs.push(InputDecl { name: str_field(d, "name")?.to_string(), kind });
    }
    let params = array(v, "params")?;
    if params.len() > limits.max_tensor_count as usize {
        return Err(Error::limit_exceeded(format!("sfm: {} parameters exceed the limit", params.len())));
    }
    for d in params {
        let dims: Vec<u32> = array(d, "dims")?
            .iter()
            .map(|x| x.as_u64().and_then(|v| u32::try_from(v).ok()).ok_or_else(|| invalid("bad dimension")))
            .collect::<Result<_>>()?;
        if dims.len() > 8 {
            return Err(invalid("too many dimensions"));
        }
        let p = ParamDecl { name: str_field(d, "name")?.to_string(), dims };
        let bytes = p.elements().checked_mul(4).ok_or_else(|| invalid("tensor size overflow"))?;
        if bytes > limits.max_tensor_bytes {
            return Err(Error::limit_exceeded(format!("sfm: tensor {:?} is {bytes} bytes", p.name)));
        }
        g.params.push(p);
    }
    for n in array(v, "nodes")? {
        let empty = Value::Object(Object::new());
        let op = parse_op(str_field(n, "op")?, n.get("attrs").unwrap_or(&empty))?;
        let inputs = array(n, "inputs")?.iter().map(parse_ref).collect::<Result<_>>()?;
        g.nodes.push(Node { op, inputs });
    }
    for d in array(v, "outputs")? {
        let kind = match str_field(d, "kind")? {
            "tensor" => OutputKind::Tensor,
            "statistics" => OutputKind::Statistics,
            other => return Err(invalid(format!("unknown output kind {other:?}"))),
        };
        g.outputs.push(OutputDecl {
            name: str_field(d, "name")?.to_string(),
            value: parse_ref(field(d, "value")?)?,
            kind,
        });
    }
    validate(&g)?;
    Ok(g)
}

/// Parses and fully validates `.sfm` bytes.
pub fn read(bytes: &[u8], limits: &Limits) -> Result<ModelFile> {
    if bytes.len() as u64 > limits.max_model_bytes {
        return Err(Error::limit_exceeded("sfm: model file exceeds the size limit"));
    }
    if bytes.get(..8) != Some(&MAGIC[..]) {
        return Err(invalid("not a ScaleForge model (bad magic)"));
    }
    let version = u32::from_le_bytes(
        bytes.get(8..12).ok_or_else(|| invalid("truncated"))?.try_into().expect("4 bytes"),
    );
    if version != FORMAT_VERSION {
        return Err(Error::unsupported(format!("sfm: format version {version} is not supported")));
    }
    let header_len = u64::from_le_bytes(
        bytes.get(12..20).ok_or_else(|| invalid("truncated"))?.try_into().expect("8 bytes"),
    );
    if header_len > limits.max_json_bytes as u64 {
        return Err(Error::limit_exceeded("sfm: header exceeds the JSON size limit"));
    }
    let header_end = 20 + header_len as usize;
    let header = json::parse(bytes.get(20..header_end).ok_or_else(|| invalid("truncated header"))?, limits)?;
    if header.get("format").and_then(Value::as_str) != Some("scaleforge-model") {
        return Err(invalid("header is not a ScaleForge model header"));
    }
    let opset = u32_field(&header, "opset")?;
    if opset != OPSET_VERSION {
        return Err(Error::unsupported(format!(
            "sfm: operator set {opset} is not supported (this build: {OPSET_VERSION})"
        )));
    }
    let metadata =
        field(&header, "metadata")?.as_object().ok_or_else(|| invalid("metadata must be an object"))?.clone();
    let graph = graph_from_json(field(&header, "graph")?, limits)?;
    let blob_start = header_end.div_ceil(ALIGN) * ALIGN;
    let blob = bytes.get(blob_start..).unwrap_or(&[]);
    if str_field(&header, "data_sha256")? != sha256_hex(blob) {
        return Err(invalid("tensor data hash mismatch (file is corrupt)"));
    }
    let entries = array(&header, "tensors")?;
    if entries.len() != graph.params.len() {
        return Err(invalid(format!("{} tensors for {} parameters", entries.len(), graph.params.len())));
    }
    let mut ranges: Vec<(usize, usize)> = Vec::with_capacity(entries.len());
    let mut weights = vec![Vec::new(); graph.params.len()];
    let mut seen = vec![false; graph.params.len()];
    for e in entries {
        let name = str_field(e, "param")?;
        let idx = graph
            .params
            .iter()
            .position(|p| p.name == name)
            .ok_or_else(|| invalid(format!("tensor for unknown parameter {name:?}")))?;
        if std::mem::replace(&mut seen[idx], true) {
            return Err(invalid(format!("parameter {name:?} has two tensors")));
        }
        if str_field(e, "dtype")? != "f32" {
            return Err(Error::unsupported(format!("sfm: tensor {name:?} dtype is not f32")));
        }
        let off = field(e, "offset")?.as_u64().ok_or_else(|| invalid("bad offset"))? as usize;
        let len = field(e, "length")?.as_u64().ok_or_else(|| invalid("bad length"))? as usize;
        if len as u64 != graph.params[idx].elements() * 4 {
            return Err(invalid(format!("tensor {name:?} length {len} does not match its dimensions")));
        }
        if off % ALIGN != 0 || off.checked_add(len).is_none_or(|end| end > blob.len()) {
            return Err(invalid(format!("tensor {name:?} is misaligned or outside the data")));
        }
        ranges.push((off, off + len));
        let data = &blob[off..off + len];
        if str_field(e, "sha256")? != sha256_hex(data) {
            return Err(invalid(format!("tensor {name:?} hash mismatch")));
        }
        weights[idx] = data.chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])).collect();
        if weights[idx].iter().any(|v| !v.is_finite()) {
            return Err(invalid(format!("tensor {name:?} contains non-finite values")));
        }
    }
    ranges.sort_unstable();
    if ranges.windows(2).any(|w| w[1].0 < w[0].1) {
        return Err(invalid("tensors overlap"));
    }
    Ok(ModelFile { metadata, graph, weights })
}

#[cfg(test)]
mod tests {
    use super::*;
    use sf_core::ErrorKind;

    fn sample() -> ModelFile {
        let mut g = Graph::new(GraphRole::Main);
        let x = g.input("x", InputKind::Spatial { channels: 3, spacing_log2: 0 });
        let s = g.input("strength", InputKind::Scalar);
        let w = g.param("w", &[12, 3, 3, 3]);
        let b = g.param("b", &[12]);
        let slope = g.param("slope", &[12]);
        let c = g.node(
            Op::Conv2d { out_channels: 12, kernel: 3, stride: 1, depthwise: false, bias: true },
            &[x, w, b],
        );
        let a = g.node(Op::PRelu, &[c, slope]);
        let a = g.node(Op::Activation(Activation::LeakyRelu(0.2)), &[a]);
        let a = g.node(Op::ScaleConst { factor: 0.2 }, &[a]);
        let p = g.node(Op::PixelShuffle { factor: 2 }, &[a]);
        let u = g.node(Op::UpsampleNearest2, &[x]);
        let y = g.node(Op::Add, &[p, u]);
        let y = g.node(Op::ScaleScalar, &[y, s]);
        let y = g.node(Op::Clamp { lo: 0.0, hi: 1.0 }, &[y]);
        g.output("y", y, OutputKind::Tensor);
        let mut meta = Object::new();
        meta.insert("name", "test-model");
        meta.insert("scale", 2u64);
        ModelFile {
            metadata: meta,
            graph: g,
            weights: vec![(0..324).map(|i| i as f32 * 0.01).collect(), vec![0.5; 12], vec![0.25; 12]],
        }
    }

    #[test]
    fn round_trip() {
        let m = sample();
        let bytes = write(&m).unwrap();
        assert_eq!(&bytes[..8], MAGIC);
        let back = read(&bytes, &Limits::default()).unwrap();
        assert_eq!(back, m);
    }

    #[test]
    fn corruption_and_tampering_are_detected() {
        let bytes = write(&sample()).unwrap();
        let kind = |b: &[u8]| read(b, &Limits::default()).unwrap_err().kind();
        // Flip a weight byte: data hash mismatch.
        let mut b = bytes.clone();
        let n = b.len();
        b[n - 3] ^= 0x40;
        assert_eq!(kind(&b), ErrorKind::ModelInvalid);
        // Truncate.
        assert_eq!(kind(&bytes[..bytes.len() - 10]), ErrorKind::ModelInvalid);
        // Bad magic / unsupported version.
        let mut b = bytes.clone();
        b[0] = b'X';
        assert_eq!(kind(&b), ErrorKind::ModelInvalid);
        let mut b = bytes.clone();
        b[8] = 9;
        assert_eq!(kind(&b), ErrorKind::Unsupported);
    }

    #[test]
    fn rejects_unknown_operators_and_limits() {
        let bytes = write(&sample()).unwrap();
        // Replace an operator name with one outside the whitelist, in place
        // (same length keeps offsets valid).
        let needle = b"\"op\":\"prelu\"";
        let at = bytes.windows(needle.len()).position(|w| w == needle).unwrap();
        let mut tampered = bytes.clone();
        tampered[at..at + needle.len()].copy_from_slice(b"\"op\":\"evalx\"");
        let e = read(&tampered, &Limits::default()).unwrap_err();
        assert!(e.message().contains("not in operator set"), "{e}");
        let tiny = Limits { max_model_bytes: 100, ..Limits::default() };
        assert_eq!(read(&bytes, &tiny).unwrap_err().kind(), ErrorKind::LimitExceeded);
        let few = Limits { max_tensor_count: 2, ..Limits::default() };
        assert_eq!(read(&bytes, &few).unwrap_err().kind(), ErrorKind::LimitExceeded);
    }

    #[test]
    fn writer_rejects_mismatched_weights() {
        let mut m = sample();
        m.weights[0].pop();
        assert_eq!(write(&m).unwrap_err().kind(), ErrorKind::ModelInvalid);
    }

    #[test]
    fn mutated_files_never_panic() {
        let bytes = write(&sample()).unwrap();
        let mut rng = sf_core::Rng::seed_from_u64(0x5f3);
        for _ in 0..3_000 {
            let mut b = bytes.clone();
            for _ in 0..=rng.below(3) {
                let at = rng.below(b.len() as u64) as usize;
                b[at] = rng.next_u64() as u8;
            }
            let _ = read(&b, &Limits::default());
        }
    }
}
