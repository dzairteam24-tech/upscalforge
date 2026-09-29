//! Upscaling factors natively supported by the engine.

use std::fmt;

use crate::error::{Error, Result};

/// A native scale factor. Larger factors are produced by composing passes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Scale {
    /// Restoration without resizing.
    X1,
    /// 2x upscaling.
    X2,
    /// 4x upscaling.
    X4,
    /// 8x upscaling.
    X8,
}

impl Scale {
    /// All native scales in increasing order.
    pub const ALL: [Scale; 4] = [Scale::X1, Scale::X2, Scale::X4, Scale::X8];

    /// The linear factor (1, 2, 4 or 8).
    pub fn factor(self) -> u32 {
        match self {
            Scale::X1 => 1,
            Scale::X2 => 2,
            Scale::X4 => 4,
            Scale::X8 => 8,
        }
    }

    /// Number of ×2 stages needed (0 to 3).
    pub fn doublings(self) -> u32 {
        self.factor().trailing_zeros()
    }

    /// Parses a linear factor.
    pub fn from_factor(factor: u32) -> Result<Scale> {
        match factor {
            1 => Ok(Scale::X1),
            2 => Ok(Scale::X2),
            4 => Ok(Scale::X4),
            8 => Ok(Scale::X8),
            other => {
                Err(Error::unsupported(format!("scale factor {other} is not native (supported: 1, 2, 4, 8)")))
            }
        }
    }
}

impl fmt::Display for Scale {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}x", self.factor())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_doublings() {
        for (s, d) in Scale::ALL.into_iter().zip(0..) {
            assert_eq!(Scale::from_factor(s.factor()).unwrap(), s);
            assert_eq!(s.doublings(), d);
        }
        assert!(Scale::from_factor(3).is_err());
        assert_eq!(Scale::X4.to_string(), "4x");
    }
}
