//! JPEG codec (our own implementation).

mod dct;
mod decode;
mod encode;

pub use decode::decode;
pub use encode::{EncodeOptions, Subsampling, encode};

#[cfg(test)]
mod tests;
