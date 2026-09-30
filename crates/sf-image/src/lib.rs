//! The ScaleForge image engine: pixel buffers and our own codecs.

pub mod checksum;
pub mod codec;
pub mod color;
pub mod exif;
mod huffman;
pub mod image;
pub mod jpeg;
pub mod png;
pub mod resample;
pub mod tiff;
pub mod webp;
pub mod zlib;

pub use codec::{decode_any, detect};
pub use image::{FileFormat, Image, ImageBuffer, ImageMeta, JpegInfo, SampleFormat, Samples};
