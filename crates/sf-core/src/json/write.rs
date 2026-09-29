//! JSON serialisation.

use std::fmt::Write as _;

use super::value::{Number, Value};
use crate::error::{Error, Result};

/// Serialises compactly. Fails only for non-finite floats, which the
/// [`Number`] constructors already exclude, so in practice it succeeds.
pub fn to_string(value: &Value) -> Result<String> {
    let mut out = String::new();
    write_value(&mut out, value, None, 0)?;
    Ok(out)
}

/// Serialises with two-space indentation and a trailing newline.
pub fn to_string_pretty(value: &Value) -> Result<String> {
    let mut out = String::new();
    write_value(&mut out, value, Some(2), 0)?;
    out.push('\n');
    Ok(out)
}

fn newline(out: &mut String, indent: Option<usize>, level: usize) {
    if let Some(step) = indent {
        out.push('\n');
        out.extend(std::iter::repeat_n(' ', step * level));
    }
}

fn write_value(out: &mut String, value: &Value, indent: Option<usize>, level: usize) -> Result<()> {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => write_number(out, *n)?,
        Value::String(s) => write_string(out, s),
        Value::Array(items) => {
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                newline(out, indent, level + 1);
                write_value(out, item, indent, level + 1)?;
            }
            if !items.is_empty() {
                newline(out, indent, level);
            }
            out.push(']');
        }
        Value::Object(object) => {
            out.push('{');
            for (i, (key, item)) in object.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                newline(out, indent, level + 1);
                write_string(out, key);
                out.push(':');
                if indent.is_some() {
                    out.push(' ');
                }
                write_value(out, item, indent, level + 1)?;
            }
            if !object.is_empty() {
                newline(out, indent, level);
            }
            out.push('}');
        }
    }
    Ok(())
}

fn write_number(out: &mut String, n: Number) -> Result<()> {
    if let Some(f) = n.repr_float() {
        if !f.is_finite() {
            return Err(Error::invalid_input("json: cannot serialise a non-finite number"));
        }
        // `{:?}` prints the shortest representation that round-trips, and
        // always includes a '.' or an exponent, so the value re-parses as a
        // float rather than an integer.
        let _ = write!(out, "{f:?}");
    } else if let Some(u) = n.as_u64() {
        let _ = write!(out, "{u}");
    } else if let Some(i) = n.as_i64() {
        let _ = write!(out, "{i}");
    } else {
        return Err(Error::internal("json: number has no representation"));
    }
    Ok(())
}

fn write_string(out: &mut String, s: &str) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0C}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}
