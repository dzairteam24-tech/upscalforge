//! A restricted interpreter for the subset of the Python pickle format that
//! PyTorch uses for weight files.
//!
//! **Security.** Ordinary unpickling can run arbitrary code. This
//! interpreter executes nothing. It recognises only a small whitelist of
//! global names:
//!
//! - `collections.OrderedDict`
//! - `torch._utils._rebuild_tensor_v2`
//! - `torch._utils._rebuild_parameter`
//! - `torch.*Storage` storage types
//!
//! It builds plain data from them. Any other global, and any opcode outside
//! the supported set, is an error.

use std::collections::HashMap;

use sf_core::{Error, Result};

/// Storage element types.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StorageType {
    /// 32-bit float.
    F32,
    /// 16-bit float.
    F16,
    /// bfloat16.
    Bf16,
    /// 64-bit float.
    F64,
}

impl StorageType {
    /// Bytes per element.
    pub fn size(self) -> usize {
        match self {
            StorageType::F32 => 4,
            StorageType::F16 | StorageType::Bf16 => 2,
            StorageType::F64 => 8,
        }
    }
}

/// A tensor reference into a storage.
#[derive(Debug, Clone, PartialEq)]
pub struct TensorRef {
    /// Storage key (archive member name under `data/`).
    pub key: String,
    /// Element type.
    pub dtype: StorageType,
    /// Offset in elements.
    pub offset: usize,
    /// Dimensions.
    pub size: Vec<usize>,
    /// Strides in elements.
    pub stride: Vec<usize>,
}

/// A decoded pickle value.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    /// `None`
    None,
    /// Boolean.
    Bool(bool),
    /// Integer.
    Int(i64),
    /// Float.
    Float(f64),
    /// String.
    Str(String),
    /// Tuple.
    Tuple(Vec<Value>),
    /// List.
    List(Vec<Value>),
    /// Dictionary (insertion order kept).
    Dict(Vec<(Value, Value)>),
    /// A tensor.
    Tensor(TensorRef),
    /// A storage from a persistent id.
    Storage(StorageType, String),
    /// A whitelisted callable or type.
    Global(Global),
    /// Stack marker.
    Mark,
}

/// Whitelisted globals.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Global {
    /// `collections.OrderedDict`
    OrderedDict,
    /// `torch._utils._rebuild_tensor_v2`
    RebuildTensor,
    /// `torch._utils._rebuild_parameter`
    RebuildParameter,
    /// A storage type.
    Storage(StorageType),
}

fn bad(what: impl std::fmt::Display) -> Error {
    Error::invalid_input(format!("pickle: {what}"))
}

fn resolve(module: &str, name: &str) -> Result<Global> {
    Ok(match (module, name) {
        ("collections", "OrderedDict") => Global::OrderedDict,
        ("torch._utils", "_rebuild_tensor_v2") => Global::RebuildTensor,
        ("torch._utils", "_rebuild_parameter") => Global::RebuildParameter,
        ("torch", "FloatStorage") => Global::Storage(StorageType::F32),
        ("torch", "HalfStorage") => Global::Storage(StorageType::F16),
        ("torch", "BFloat16Storage") => Global::Storage(StorageType::Bf16),
        ("torch", "DoubleStorage") => Global::Storage(StorageType::F64),
        _ => {
            return Err(Error::unsupported(format!(
                "pickle: refusing global {module}.{name} (not on the weights-only whitelist)"
            )));
        }
    })
}

fn usize_of(v: &Value) -> Result<usize> {
    match v {
        Value::Int(i) if *i >= 0 => Ok(*i as usize),
        _ => Err(bad("expected a non-negative integer")),
    }
}

fn tuple_of(v: &Value) -> Result<&[Value]> {
    match v {
        Value::Tuple(t) => Ok(t),
        _ => Err(bad("expected a tuple")),
    }
}

fn call(g: Global, args: Vec<Value>) -> Result<Value> {
    match g {
        Global::OrderedDict => {
            if args.is_empty() {
                Ok(Value::Dict(Vec::new()))
            } else {
                Err(bad("OrderedDict with arguments"))
            }
        }
        Global::RebuildTensor => {
            if args.len() < 4 {
                return Err(bad("_rebuild_tensor_v2 needs storage, offset, size and stride"));
            }
            let Value::Storage(dtype, key) = &args[0] else { return Err(bad("tensor without storage")) };
            let size: Vec<usize> = tuple_of(&args[2])?.iter().map(usize_of).collect::<Result<_>>()?;
            let stride: Vec<usize> = tuple_of(&args[3])?.iter().map(usize_of).collect::<Result<_>>()?;
            if size.len() != stride.len() || size.len() > 8 {
                return Err(bad("size and stride disagree"));
            }
            Ok(Value::Tensor(TensorRef {
                key: key.clone(),
                dtype: *dtype,
                offset: usize_of(&args[1])?,
                size,
                stride,
            }))
        }
        Global::RebuildParameter => match args.into_iter().next() {
            Some(t @ Value::Tensor(_)) => Ok(t),
            _ => Err(bad("_rebuild_parameter without a tensor")),
        },
        Global::Storage(_) => Err(bad("storage types are not callable")),
    }
}

/// Maximum operations interpreted, against pathological inputs.
const MAX_OPS: usize = 50_000_000;

/// Interprets a pickle stream into a value.
pub fn load(data: &[u8]) -> Result<Value> {
    let mut stack: Vec<Value> = Vec::new();
    let mut memo: HashMap<u32, Value> = HashMap::new();
    let mut pos = 0usize;
    let take = |pos: &mut usize, n: usize| -> Result<&[u8]> {
        let s = data.get(*pos..*pos + n).ok_or_else(|| bad("truncated"))?;
        *pos += n;
        Ok(s)
    };
    let pop = |stack: &mut Vec<Value>| stack.pop().ok_or_else(|| bad("stack underflow"));
    let pop_mark = |stack: &mut Vec<Value>| -> Result<Vec<Value>> {
        let m = stack.iter().rposition(|v| *v == Value::Mark).ok_or_else(|| bad("missing mark"))?;
        let items = stack.split_off(m + 1);
        stack.pop();
        Ok(items)
    };
    for _ in 0..MAX_OPS {
        let op = *data.get(pos).ok_or_else(|| bad("missing STOP"))?;
        pos += 1;
        match op {
            0x80 => {
                let proto = take(&mut pos, 1)?[0];
                if proto > 5 {
                    return Err(Error::unsupported(format!("pickle: protocol {proto}")));
                }
            }
            0x95 => {
                take(&mut pos, 8)?; // FRAME length: framing is transparent here
            }
            b'.' => return pop(&mut stack),
            b'}' => stack.push(Value::Dict(Vec::new())),
            b']' => stack.push(Value::List(Vec::new())),
            b')' => stack.push(Value::Tuple(Vec::new())),
            b'(' => stack.push(Value::Mark),
            b'N' => stack.push(Value::None),
            0x88 => stack.push(Value::Bool(true)),
            0x89 => stack.push(Value::Bool(false)),
            b'K' => stack.push(Value::Int(i64::from(take(&mut pos, 1)?[0]))),
            b'M' => {
                let b = take(&mut pos, 2)?;
                stack.push(Value::Int(i64::from(u16::from_le_bytes([b[0], b[1]]))));
            }
            b'J' => {
                let b = take(&mut pos, 4)?;
                stack.push(Value::Int(i64::from(i32::from_le_bytes([b[0], b[1], b[2], b[3]]))));
            }
            0x8a => {
                let n = take(&mut pos, 1)?[0] as usize;
                let b = take(&mut pos, n)?;
                if n > 8 {
                    return Err(bad("integer too large"));
                }
                let mut v: i64 = 0;
                for (i, &x) in b.iter().enumerate() {
                    v |= i64::from(x) << (8 * i);
                }
                if n > 0 && n < 8 && b[n - 1] & 0x80 != 0 {
                    v -= 1i64 << (8 * n);
                }
                stack.push(Value::Int(v));
            }
            b'G' => {
                let b = take(&mut pos, 8)?;
                stack.push(Value::Float(f64::from_be_bytes(b.try_into().expect("8 bytes"))));
            }
            b'X' | 0x8c | b'U' => {
                let n = if op == b'X' {
                    let b = take(&mut pos, 4)?;
                    u32::from_le_bytes([b[0], b[1], b[2], b[3]]) as usize
                } else {
                    take(&mut pos, 1)?[0] as usize
                };
                let s = take(&mut pos, n)?;
                stack.push(Value::Str(
                    String::from_utf8(s.to_vec()).map_err(|_| bad("invalid UTF-8 string"))?,
                ));
            }
            b'c' => {
                let rest = &data[pos..];
                let nl1 = rest.iter().position(|&b| b == b'\n').ok_or_else(|| bad("bad GLOBAL"))?;
                let nl2 =
                    rest[nl1 + 1..].iter().position(|&b| b == b'\n').ok_or_else(|| bad("bad GLOBAL"))?;
                let module = std::str::from_utf8(&rest[..nl1]).map_err(|_| bad("bad GLOBAL"))?;
                let name =
                    std::str::from_utf8(&rest[nl1 + 1..nl1 + 1 + nl2]).map_err(|_| bad("bad GLOBAL"))?;
                pos += nl1 + nl2 + 2;
                stack.push(Value::Global(resolve(module, name)?));
            }
            0x93 => {
                let name = pop(&mut stack)?;
                let module = pop(&mut stack)?;
                match (module, name) {
                    (Value::Str(m), Value::Str(n)) => stack.push(Value::Global(resolve(&m, &n)?)),
                    _ => return Err(bad("bad STACK_GLOBAL")),
                }
            }
            b'q' | b'r' | 0x94 => {
                let idx = match op {
                    b'q' => u32::from(take(&mut pos, 1)?[0]),
                    b'r' => {
                        let b = take(&mut pos, 4)?;
                        u32::from_le_bytes([b[0], b[1], b[2], b[3]])
                    }
                    _ => memo.len() as u32,
                };
                let top = stack.last().ok_or_else(|| bad("memoize on empty stack"))?.clone();
                memo.insert(idx, top);
            }
            b'h' | b'j' => {
                let idx = if op == b'h' {
                    u32::from(take(&mut pos, 1)?[0])
                } else {
                    let b = take(&mut pos, 4)?;
                    u32::from_le_bytes([b[0], b[1], b[2], b[3]])
                };
                stack.push(memo.get(&idx).cloned().ok_or_else(|| bad("unknown memo index"))?);
            }
            b't' => {
                let items = pop_mark(&mut stack)?;
                stack.push(Value::Tuple(items));
            }
            0x85..=0x87 => {
                let n = (op - 0x84) as usize;
                if stack.len() < n {
                    return Err(bad("stack underflow"));
                }
                let items = stack.split_off(stack.len() - n);
                stack.push(Value::Tuple(items));
            }
            b'Q' => {
                let pid = pop(&mut stack)?;
                let t = tuple_of(&pid)?;
                match t {
                    [Value::Str(tag), Value::Global(Global::Storage(dt)), Value::Str(key), ..]
                        if tag == "storage" =>
                    {
                        stack.push(Value::Storage(*dt, key.clone()));
                    }
                    _ => return Err(bad("unsupported persistent id")),
                }
            }
            b'R' => {
                let args = pop(&mut stack)?;
                let callable = pop(&mut stack)?;
                let Value::Global(g) = callable else { return Err(bad("REDUCE on a non-callable")) };
                stack.push(call(g, tuple_of(&args)?.to_vec())?);
            }
            b'b' => {
                // BUILD: state for OrderedDict (_metadata) or tensors is not needed.
                pop(&mut stack)?;
                match stack.last() {
                    Some(Value::Dict(_) | Value::Tensor(_)) => {}
                    _ => return Err(bad("BUILD on an unsupported object")),
                }
            }
            b's' | b'u' => {
                let items = if op == b's' {
                    let v = pop(&mut stack)?;
                    let k = pop(&mut stack)?;
                    vec![k, v]
                } else {
                    pop_mark(&mut stack)?
                };
                if items.len() % 2 != 0 {
                    return Err(bad("odd number of dictionary items"));
                }
                let Some(Value::Dict(d)) = stack.last_mut() else { return Err(bad("SETITEM on a non-dict")) };
                let mut it = items.into_iter();
                while let (Some(k), Some(v)) = (it.next(), it.next()) {
                    d.push((k, v));
                }
            }
            b'a' | b'e' => {
                let items = if op == b'a' { vec![pop(&mut stack)?] } else { pop_mark(&mut stack)? };
                let Some(Value::List(l)) = stack.last_mut() else { return Err(bad("APPEND on a non-list")) };
                l.extend(items);
            }
            other => {
                return Err(Error::unsupported(format!("pickle: opcode 0x{other:02x} is not supported")));
            }
        }
    }
    Err(Error::limit_exceeded("pickle: operation limit exceeded"))
}
