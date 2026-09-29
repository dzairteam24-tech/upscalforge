//! Format detection and dispatch to our codecs.

use sf_core::{Error, Limits, Result};

use crate::image::{FileFormat, Image};

/// Identifies a format from its leading bytes.
pub fn detect(data: &[u8]) -> Option<FileFormat> {
    if data.starts_with(&crate::png::SIGNATURE) {
        Some(FileFormat::Png)
    } else if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some(FileFormat::Jpeg)
    } else if data.starts_with(b"II*\0")
        || data.starts_with(b"MM\0*")
        || data.starts_with(b"II+\0")
        || data.starts_with(b"MM\0+")
    {
        Some(FileFormat::Tiff)
    } else {
        None
    }
}

/// Decodes any supported format, detected from content (never from the
/// file name).
pub fn decode_any(data: &[u8], limits: &Limits) -> Result<Image> {
    match detect(data) {
        Some(FileFormat::Png) => crate::png::decode(data, limits),
        Some(FileFormat::Jpeg) => crate::jpeg::decode(data, limits),
        Some(other) => Err(Error::unsupported(format!("{other:?} decoding is not available yet"))),
        None => Err(Error::unsupported("unrecognised image format (supported: PNG, JPEG, TIFF)")),
    }
}
