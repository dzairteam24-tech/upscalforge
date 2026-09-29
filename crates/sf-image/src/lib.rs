//! The ScaleForge image engine: pixel buffers and our own codecs.

pub mod checksum;
pub mod codec;
pub mod exif;
pub mod image;
pub mod png;
pub mod zlib;

pub use codec::{decode_any, detect};
pub use image::{FileFormat, Image, ImageBuffer, ImageMeta, JpegInfo, SampleFormat, Samples};
