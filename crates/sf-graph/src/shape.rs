//! Tensor shapes.

use std::fmt;

/// The shape of a value in a graph. Spatial tensors use NCHW order.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Shape {
    /// Batch × channels × height × width.
    Spatial {
        /// Batch size.
        n: u32,
        /// Channels.
        c: u32,
        /// Height.
        h: u32,
        /// Width.
        w: u32,
    },
    /// Batch × channels (e.g. a condition vector).
    Vector {
        /// Batch size.
        n: u32,
        /// Channels.
        c: u32,
    },
    /// A single runtime scalar (e.g. a strength).
    Scalar,
}

impl Shape {
    /// Number of elements.
    pub fn elements(self) -> u64 {
        match self {
            Shape::Spatial { n, c, h, w } => u64::from(n) * u64::from(c) * u64::from(h) * u64::from(w),
            Shape::Vector { n, c } => u64::from(n) * u64::from(c),
            Shape::Scalar => 1,
        }
    }

    /// Channels, for spatial and vector shapes.
    pub fn channels(self) -> Option<u32> {
        match self {
            Shape::Spatial { c, .. } | Shape::Vector { c, .. } => Some(c),
            Shape::Scalar => None,
        }
    }
}

impl fmt::Display for Shape {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Shape::Spatial { n, c, h, w } => write!(f, "[{n}, {c}, {h}, {w}]"),
            Shape::Vector { n, c } => write!(f, "[{n}, {c}]"),
            Shape::Scalar => f.write_str("scalar"),
        }
    }
}
