//! A strict, limit-aware JSON reader and writer (RFC 8259).
//!
//! Used for model and checkpoint headers, dataset manifests, reports and
//! the tuning cache. Model headers may come from untrusted files, so the
//! parser is strict:
//!
//! - input must be valid UTF-8 without a byte-order mark;
//! - no comments, trailing commas, `NaN`/`Infinity`, or leading zeros;
//! - lone UTF-16 surrogates in `\u` escapes are rejected;
//! - **duplicate object keys are rejected** (they are a classic source of
//!   parser-disagreement attacks);
//! - document size and nesting depth are bounded by [`crate::Limits`].
//!
//! Integers keep full 64-bit precision; numbers with a fraction or exponent
//! are `f64`.

mod parse;
mod value;
mod write;

pub use parse::parse;
pub use value::{Number, Object, Value};
pub use write::{to_string, to_string_pretty};

#[cfg(test)]
mod tests;
