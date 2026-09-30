//! Element types for pixels and tensors.

use std::fmt;

/// Scalar element type.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DType {
    /// Unsigned 8-bit integer.
    U8,
    /// Unsigned 16-bit integer.
    U16,
    /// IEEE 754 half precision.
    F16,
    /// IEEE 754 single precision.
    F32,
    /// IEEE 754 double precision (CPU gradient checks only).
    F64,
}

impl DType {
    /// Size of one element in bytes.
    pub fn size_bytes(self) -> u32 {
        match self {
            DType::U8 => 1,
            DType::U16 | DType::F16 => 2,
            DType::F32 => 4,
            DType::F64 => 8,
        }
    }

    /// True for floating-point types.
    pub fn is_float(self) -> bool {
        matches!(self, DType::F16 | DType::F32 | DType::F64)
    }

    /// Stable lowercase name used in files and reports.
    pub fn name(self) -> &'static str {
        match self {
            DType::U8 => "u8",
            DType::U16 => "u16",
            DType::F16 => "f16",
            DType::F32 => "f32",
            DType::F64 => "f64",
        }
    }

    /// Parses a name produced by [`DType::name`].
    pub fn from_name(name: &str) -> Option<DType> {
        [DType::U8, DType::U16, DType::F16, DType::F32, DType::F64].into_iter().find(|d| d.name() == name)
    }
}

impl fmt::Display for DType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_round_trip() {
        for d in [DType::U8, DType::U16, DType::F16, DType::F32, DType::F64] {
            assert_eq!(DType::from_name(d.name()), Some(d));
        }
        assert_eq!(DType::from_name("f8"), None);
        assert_eq!(DType::F16.size_bytes(), 2);
        assert!(!DType::U16.is_float());
    }
}
