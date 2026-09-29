//! Resource limits enforced by every parser and allocator.
//!
//! Limits are a defence against malformed or malicious input (decompression
//! bombs, huge declared sizes, deeply nested headers). They are *sanity*
//! bounds. Memory *budgets* (how much a job may actually use) are enforced
//! separately by the engine's memory managers.
//!
//! The default values are provisional starting points. They are chosen to
//! admit every legitimate workload in the requirements (e.g. 25.6-gigapixel
//! streamed outputs) while rejecting absurd declarations.

use crate::error::{Error, Result};

/// Upper bound accepted for [`Limits::max_json_depth`], protecting the
/// recursive JSON parser's stack.
pub const JSON_DEPTH_CEILING: u32 = 512;

/// Resource limits. Construct with [`Limits::default`] and adjust fields,
/// then call [`Limits::validate`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Limits {
    /// Maximum width or height of any image, in pixels.
    pub max_image_dimension: u32,
    /// Maximum pixel count of any image (input or output).
    pub max_image_pixels: u64,
    /// Maximum bytes a decoder may allocate to hold one fully decoded image.
    pub max_decoded_bytes: u64,
    /// Maximum size of an embedded ICC profile (0 rejects every profile).
    pub max_icc_bytes: u32,
    /// Maximum total size of retained metadata per image (0 retains none).
    pub max_metadata_bytes: u32,
    /// Maximum size of a JSON document (model headers, manifests, reports).
    pub max_json_bytes: usize,
    /// Maximum nesting depth of a JSON document.
    pub max_json_depth: u32,
    /// Maximum number of tensors in a model or checkpoint.
    pub max_tensor_count: u32,
    /// Maximum size of a single tensor.
    pub max_tensor_bytes: u64,
    /// Maximum size of a model or checkpoint file.
    pub max_model_bytes: u64,
}

impl Default for Limits {
    fn default() -> Self {
        Limits {
            max_image_dimension: 1 << 20, // 1,048,576 px per side
            max_image_pixels: 1 << 36,    // ~68.7 gigapixels
            max_decoded_bytes: 8 << 30,   // 8 GiB for one in-memory decode
            max_icc_bytes: 4 << 20,       // 4 MiB
            max_metadata_bytes: 16 << 20, // 16 MiB
            max_json_bytes: 16 << 20,     // 16 MiB
            max_json_depth: 64,
            max_tensor_count: 100_000,
            max_tensor_bytes: 4 << 30, // 4 GiB
            max_model_bytes: 16 << 30, // 16 GiB
        }
    }
}

impl Limits {
    /// Checks that the limits themselves are usable.
    pub fn validate(&self) -> Result<()> {
        let nonzero = [
            ("max_image_dimension", u64::from(self.max_image_dimension)),
            ("max_image_pixels", self.max_image_pixels),
            ("max_decoded_bytes", self.max_decoded_bytes),
            ("max_json_bytes", self.max_json_bytes as u64),
            ("max_json_depth", u64::from(self.max_json_depth)),
            ("max_tensor_count", u64::from(self.max_tensor_count)),
            ("max_tensor_bytes", self.max_tensor_bytes),
            ("max_model_bytes", self.max_model_bytes),
        ];
        for (name, value) in nonzero {
            if value == 0 {
                return Err(Error::invalid_input(format!("limit {name} must be greater than zero")));
            }
        }
        if self.max_json_depth > JSON_DEPTH_CEILING {
            return Err(Error::invalid_input(format!(
                "limit max_json_depth {} exceeds the supported ceiling {JSON_DEPTH_CEILING}",
                self.max_json_depth
            )));
        }
        Ok(())
    }

    /// Checks image dimensions and returns the pixel count.
    pub fn check_image(&self, width: u32, height: u32) -> Result<u64> {
        if width == 0 || height == 0 {
            return Err(Error::invalid_input(format!("image dimensions {width}x{height} are empty")));
        }
        if width > self.max_image_dimension || height > self.max_image_dimension {
            return Err(Error::limit_exceeded(format!(
                "image dimensions {width}x{height} exceed the per-side limit {}",
                self.max_image_dimension
            )));
        }
        let pixels = u64::from(width) * u64::from(height);
        if pixels > self.max_image_pixels {
            return Err(Error::limit_exceeded(format!(
                "image of {pixels} pixels exceeds the limit {}",
                self.max_image_pixels
            )));
        }
        Ok(pixels)
    }

    /// Checks that fully decoding an image into memory stays within
    /// [`Limits::max_decoded_bytes`], and returns the byte count.
    pub fn check_decoded_bytes(&self, width: u32, height: u32, bytes_per_pixel: u32) -> Result<u64> {
        let pixels = self.check_image(width, height)?;
        let bytes = pixels
            .checked_mul(u64::from(bytes_per_pixel))
            .ok_or_else(|| Error::limit_exceeded("decoded image size overflows 64 bits"))?;
        if bytes > self.max_decoded_bytes {
            return Err(Error::limit_exceeded(format!(
                "decoding needs {bytes} bytes, above the limit {}",
                self.max_decoded_bytes
            )));
        }
        Ok(bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ErrorKind;

    #[test]
    fn defaults_are_valid() {
        Limits::default().validate().unwrap();
    }

    #[test]
    fn zero_limit_is_rejected() {
        let l = Limits { max_json_depth: 0, ..Limits::default() };
        assert_eq!(l.validate().unwrap_err().kind(), ErrorKind::InvalidInput);
    }

    #[test]
    fn depth_above_ceiling_is_rejected() {
        let l = Limits { max_json_depth: JSON_DEPTH_CEILING + 1, ..Limits::default() };
        assert!(l.validate().is_err());
    }

    #[test]
    fn image_checks() {
        let l = Limits { max_image_dimension: 100, max_image_pixels: 5_000, ..Limits::default() };
        assert_eq!(l.check_image(50, 100).unwrap(), 5_000);
        assert_eq!(l.check_image(0, 10).unwrap_err().kind(), ErrorKind::InvalidInput);
        assert_eq!(l.check_image(101, 1).unwrap_err().kind(), ErrorKind::LimitExceeded);
        assert_eq!(l.check_image(100, 51).unwrap_err().kind(), ErrorKind::LimitExceeded);
    }

    #[test]
    fn decoded_bytes_check() {
        let l = Limits { max_decoded_bytes: 1_000, ..Limits::default() };
        assert_eq!(l.check_decoded_bytes(10, 10, 4).unwrap(), 400);
        assert_eq!(l.check_decoded_bytes(20, 20, 4).unwrap_err().kind(), ErrorKind::LimitExceeded);
    }

    #[test]
    fn decoded_bytes_overflow_is_an_error_not_a_panic() {
        let l = Limits {
            max_image_dimension: u32::MAX,
            max_image_pixels: u64::MAX,
            max_decoded_bytes: u64::MAX,
            ..Limits::default()
        };
        let e = l.check_decoded_bytes(u32::MAX, u32::MAX, u32::MAX).unwrap_err();
        assert_eq!(e.kind(), ErrorKind::LimitExceeded);
    }
}
