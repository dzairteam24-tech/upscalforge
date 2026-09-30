//! JPEG codec (our own implementation).

mod dct;
mod decode;
mod encode;

pub use decode::decode;
pub use encode::{EncodeOptions, Subsampling, encode, estimate_quality};

#[cfg(test)]
mod tests;
