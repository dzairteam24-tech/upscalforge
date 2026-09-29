//! Reading PyTorch weight files (`.pth`, the zip-based format) into named
//! `f32` tensors, through the restricted interpreter in [`crate::pickle`].

use std::collections::BTreeMap;

use sf_core::{Error, Limits, Result};

use crate::pickle::{self, StorageType, TensorRef, Value};
use crate::zip;

/// A dense tensor.
#[derive(Debug, Clone, PartialEq)]
pub struct Tensor {
    /// Dimensions.
    pub dims: Vec<usize>,
    /// Row-major values.
    pub data: Vec<f32>,
}

/// Named tensors, sorted by name.
pub type StateDict = BTreeMap<String, Tensor>;

/// IEEE 754 half precision → f32.
pub fn f16_to_f32(h: u16) -> f32 {
    let sign = u32::from(h >> 15) << 31;
    let exp = u32::from((h >> 10) & 0x1F);
    let mant = u32::from(h & 0x3FF);
    let bits = match (exp, mant) {
        (0, 0) => sign,
        (0, m) => {
            // Subnormal: normalise.
            let shift = m.leading_zeros() - 21;
            sign | ((113 - shift) << 23) | (((m << shift) & 0x3FF) << 13)
        }
        (31, 0) => sign | 0x7F80_0000,
        (31, m) => sign | 0x7F80_0000 | (m << 13),
        (e, m) => sign | ((e + 112) << 23) | (m << 13),
    };
    f32::from_bits(bits)
}

fn materialise(
    d: &[u8],
    members: &[zip::Entry],
    prefix: &str,
    t: &TensorRef,
    limits: &Limits,
) -> Result<Tensor> {
    let name = format!("{prefix}data/{}", t.key);
    let entry = members
        .iter()
        .find(|e| e.name == name)
        .ok_or_else(|| Error::invalid_input(format!("pth: missing storage {name}")))?;
    let raw = zip::extract(d, entry, limits.max_tensor_bytes as usize)?;
    let n = t.dtype.size();
    let count = raw.len() / n;
    let value = |i: usize| -> f32 {
        let b = &raw[i * n..(i + 1) * n];
        match t.dtype {
            StorageType::F32 => f32::from_le_bytes([b[0], b[1], b[2], b[3]]),
            StorageType::F16 => f16_to_f32(u16::from_le_bytes([b[0], b[1]])),
            StorageType::Bf16 => f32::from_bits(u32::from(u16::from_le_bytes([b[0], b[1]])) << 16),
            StorageType::F64 => f64::from_le_bytes(b.try_into().expect("8 bytes")) as f32,
        }
    };
    let total: usize = t.size.iter().product();
    if total as u64 * 4 > limits.max_tensor_bytes {
        return Err(Error::limit_exceeded("pth: tensor exceeds the size limit"));
    }
    let mut data = Vec::with_capacity(total);
    let mut index = vec![0usize; t.size.len()];
    for _ in 0..total {
        let at = t.offset + index.iter().zip(&t.stride).map(|(i, s)| i * s).sum::<usize>();
        if at >= count {
            return Err(Error::invalid_input("pth: tensor view reaches outside its storage"));
        }
        data.push(value(at));
        for k in (0..index.len()).rev() {
            index[k] += 1;
            if index[k] < t.size[k] {
                break;
            }
            index[k] = 0;
        }
    }
    Ok(Tensor { dims: t.size.clone(), data })
}

/// Loads a `.pth` file. If the top level is a dictionary holding a state
/// dictionary under `params_ema` or `params` (a common convention), that
/// inner dictionary is used.
pub fn load(d: &[u8], limits: &Limits) -> Result<StateDict> {
    if !d.starts_with(b"PK") {
        return Err(Error::unsupported(
            "pth: only the zip-based PyTorch format is supported (legacy format files are not)",
        ));
    }
    let members = zip::entries(d)?;
    let pkl = members
        .iter()
        .find(|e| e.name.ends_with("data.pkl"))
        .ok_or_else(|| Error::invalid_input("pth: no data.pkl in the archive"))?;
    let prefix = pkl.name.trim_end_matches("data.pkl").to_string();
    if let Some(bo) = members.iter().find(|e| e.name == format!("{prefix}byteorder")) {
        let v = zip::extract(d, bo, 16)?;
        if v.as_ref() != b"little" {
            return Err(Error::unsupported("pth: big-endian storages are not supported"));
        }
    }
    let root = pickle::load(&zip::extract(d, pkl, limits.max_json_bytes.max(1 << 24))?)?;
    let top = match root {
        Value::Dict(d) => d,
        _ => return Err(Error::invalid_input("pth: top level is not a dictionary")),
    };
    let find = |key: &str| {
        top.iter().find_map(|(k, v)| match (k, v) {
            (Value::Str(s), Value::Dict(inner)) if s == key => Some(inner.clone()),
            _ => None,
        })
    };
    let dict = find("params_ema").or_else(|| find("params")).unwrap_or(top.clone());
    let mut out = StateDict::new();
    for (k, v) in dict {
        if let (Value::Str(name), Value::Tensor(t)) = (k, v) {
            if out.len() >= limits.max_tensor_count as usize {
                return Err(Error::limit_exceeded("pth: too many tensors"));
            }
            let t = materialise(d, &members, &prefix, &t, limits)?;
            out.insert(name, t);
        }
    }
    if out.is_empty() {
        return Err(Error::invalid_input("pth: no tensors found"));
    }
    Ok(out)
}

#[cfg(test)]
pub(crate) mod test_writer {
    //! Builds `.pth`-structured archives (zip + protocol-2 pickle) for tests,
    //! following the format's documented structure.

    use super::StateDict;

    fn unicode(out: &mut Vec<u8>, s: &str) {
        out.push(b'X');
        out.extend((s.len() as u32).to_le_bytes());
        out.extend(s.as_bytes());
    }

    fn int(out: &mut Vec<u8>, v: usize) {
        if v < 256 {
            out.extend([b'K', v as u8]);
        } else {
            out.push(b'J');
            out.extend((v as i32).to_le_bytes());
        }
    }

    /// `wrap`: store the state dict under "params_ema" like some trainers.
    pub fn write(sd: &StateDict, wrap: bool) -> Vec<u8> {
        let mut p = vec![0x80, 2];
        if wrap {
            p.push(b'}');
            unicode(&mut p, "params_ema");
        }
        p.extend(b"ccollections\nOrderedDict\n)R");
        p.push(b'(');
        let mut storages: Vec<(String, Vec<u8>)> = Vec::new();
        for (i, (name, t)) in sd.iter().enumerate() {
            unicode(&mut p, name);
            p.extend(b"ctorch._utils\n_rebuild_tensor_v2\n(");
            // Persistent id tuple: ('storage', FloatStorage, key, 'cpu', numel)
            p.push(b'(');
            unicode(&mut p, "storage");
            p.extend(b"ctorch\nFloatStorage\n");
            unicode(&mut p, &i.to_string());
            unicode(&mut p, "cpu");
            int(&mut p, t.data.len());
            p.extend(b"tQ");
            int(&mut p, 0);
            p.push(b'(');
            for &d in &t.dims {
                int(&mut p, d);
            }
            p.push(b't');
            p.push(b'(');
            let mut stride = 1;
            let mut strides = vec![0; t.dims.len()];
            for k in (0..t.dims.len()).rev() {
                strides[k] = stride;
                stride *= t.dims[k];
            }
            for s in strides {
                int(&mut p, s);
            }
            p.push(b't');
            p.push(0x89); // requires_grad = False
            p.extend(b"ccollections\nOrderedDict\n)R");
            p.extend(b"tR");
            storages.push((i.to_string(), t.data.iter().flat_map(|v| v.to_le_bytes()).collect()));
        }
        p.push(b'u');
        // OrderedDict state (the `_metadata` attribute) via BUILD.
        p.extend(b"}b");
        if wrap {
            p.push(b's');
        }
        p.push(b'.');
        let mut members: Vec<(String, Vec<u8>)> =
            vec![("archive/data.pkl".into(), p), ("archive/byteorder".into(), b"little".to_vec())];
        for (k, bytes) in storages {
            members.push((format!("archive/data/{k}"), bytes));
        }
        let refs: Vec<(&str, &[u8])> = members.iter().map(|(n, d)| (n.as_str(), d.as_slice())).collect();
        crate::zip::test_writer::write(&refs)
    }
}
