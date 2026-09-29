//! The JSON document model.

/// A JSON number. Integers are stored exactly; other numbers as `f64`.
#[derive(Debug, Clone, Copy)]
pub struct Number(Repr);

#[derive(Debug, Clone, Copy)]
enum Repr {
    /// Non-negative integer.
    Pos(u64),
    /// Negative integer (always < 0).
    Neg(i64),
    /// Non-integer or out-of-range number; always finite.
    Float(f64),
}

impl Number {
    /// An exact unsigned integer.
    pub fn from_u64(v: u64) -> Number {
        Number(Repr::Pos(v))
    }

    /// An exact signed integer.
    pub fn from_i64(v: i64) -> Number {
        if v >= 0 { Number(Repr::Pos(v as u64)) } else { Number(Repr::Neg(v)) }
    }

    /// A floating-point number, or `None` if it is not finite (JSON has no
    /// representation for NaN or infinities).
    pub fn from_f64(v: f64) -> Option<Number> {
        v.is_finite().then_some(Number(Repr::Float(v)))
    }

    /// The value as `u64`, if it is a non-negative integer.
    pub fn as_u64(self) -> Option<u64> {
        match self.0 {
            Repr::Pos(v) => Some(v),
            _ => None,
        }
    }

    /// The value as `i64`, if it is an integer in range.
    pub fn as_i64(self) -> Option<i64> {
        match self.0 {
            Repr::Pos(v) => i64::try_from(v).ok(),
            Repr::Neg(v) => Some(v),
            Repr::Float(_) => None,
        }
    }

    /// The value as `f64` (integers are converted, possibly rounding).
    pub fn as_f64(self) -> f64 {
        match self.0 {
            Repr::Pos(v) => v as f64,
            Repr::Neg(v) => v as f64,
            Repr::Float(v) => v,
        }
    }

    /// True if the number is stored as an exact integer.
    pub fn is_integer(self) -> bool {
        !matches!(self.0, Repr::Float(_))
    }

    pub(super) fn repr_float(self) -> Option<f64> {
        match self.0 {
            Repr::Float(v) => Some(v),
            _ => None,
        }
    }
}

impl PartialEq for Number {
    fn eq(&self, other: &Self) -> bool {
        match (self.0, other.0) {
            (Repr::Pos(a), Repr::Pos(b)) => a == b,
            (Repr::Neg(a), Repr::Neg(b)) => a == b,
            (Repr::Float(a), Repr::Float(b)) => a == b,
            _ => false,
        }
    }
}

/// A JSON object: key–value pairs with unique keys, in insertion order.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Object {
    entries: Vec<(String, Value)>,
}

impl Object {
    /// An empty object.
    pub fn new() -> Object {
        Object::default()
    }

    /// Looks up a key.
    pub fn get(&self, key: &str) -> Option<&Value> {
        self.entries.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    /// Inserts or replaces a key, keeping the original position on replace.
    pub fn insert(&mut self, key: impl Into<String>, value: impl Into<Value>) {
        let key = key.into();
        let value = value.into();
        match self.entries.iter_mut().find(|(k, _)| *k == key) {
            Some(slot) => slot.1 = value,
            None => self.entries.push((key, value)),
        }
    }

    /// Iterates over entries in order.
    pub fn iter(&self) -> impl Iterator<Item = (&str, &Value)> {
        self.entries.iter().map(|(k, v)| (k.as_str(), v))
    }

    /// Number of entries.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// True if there are no entries.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Appends an entry whose key is known to be unique (parser use).
    pub(super) fn push_unique(&mut self, key: String, value: Value) {
        self.entries.push((key, value));
    }
}

/// A JSON value.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    /// `null`
    Null,
    /// `true` / `false`
    Bool(bool),
    /// A number.
    Number(Number),
    /// A string.
    String(String),
    /// An array.
    Array(Vec<Value>),
    /// An object.
    Object(Object),
}

impl Value {
    /// Member lookup on objects; `None` for other types or missing keys.
    pub fn get(&self, key: &str) -> Option<&Value> {
        self.as_object()?.get(key)
    }

    /// The boolean, if this is one.
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    /// The number as `u64`, if it is a non-negative integer.
    pub fn as_u64(&self) -> Option<u64> {
        match self {
            Value::Number(n) => n.as_u64(),
            _ => None,
        }
    }

    /// The number as `i64`, if it is an integer in range.
    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Value::Number(n) => n.as_i64(),
            _ => None,
        }
    }

    /// The number as `f64`, if this is a number.
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Number(n) => Some(n.as_f64()),
            _ => None,
        }
    }

    /// The string, if this is one.
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::String(s) => Some(s),
            _ => None,
        }
    }

    /// The elements, if this is an array.
    pub fn as_array(&self) -> Option<&[Value]> {
        match self {
            Value::Array(a) => Some(a),
            _ => None,
        }
    }

    /// The object, if this is one.
    pub fn as_object(&self) -> Option<&Object> {
        match self {
            Value::Object(o) => Some(o),
            _ => None,
        }
    }

    /// True for `null`.
    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }
}

impl From<bool> for Value {
    fn from(v: bool) -> Self {
        Value::Bool(v)
    }
}

impl From<u64> for Value {
    fn from(v: u64) -> Self {
        Value::Number(Number::from_u64(v))
    }
}

impl From<u32> for Value {
    fn from(v: u32) -> Self {
        Value::Number(Number::from_u64(u64::from(v)))
    }
}

impl From<i64> for Value {
    fn from(v: i64) -> Self {
        Value::Number(Number::from_i64(v))
    }
}

impl From<Number> for Value {
    fn from(v: Number) -> Self {
        Value::Number(v)
    }
}

impl From<&str> for Value {
    fn from(v: &str) -> Self {
        Value::String(v.to_owned())
    }
}

impl From<String> for Value {
    fn from(v: String) -> Self {
        Value::String(v)
    }
}

impl From<Vec<Value>> for Value {
    fn from(v: Vec<Value>) -> Self {
        Value::Array(v)
    }
}

impl From<Object> for Value {
    fn from(v: Object) -> Self {
        Value::Object(v)
    }
}
