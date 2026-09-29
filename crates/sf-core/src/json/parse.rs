//! Strict recursive-descent JSON parser.

use std::collections::HashSet;

use super::value::{Number, Object, Value};
use crate::error::{Error, Result};
use crate::limits::Limits;

/// Parses a complete JSON document from bytes, enforcing
/// [`Limits::max_json_bytes`] and [`Limits::max_json_depth`].
pub fn parse(input: &[u8], limits: &Limits) -> Result<Value> {
    if input.len() > limits.max_json_bytes {
        return Err(Error::limit_exceeded(format!(
            "json: document of {} bytes exceeds the limit {}",
            input.len(),
            limits.max_json_bytes
        )));
    }
    if input.starts_with(&[0xEF, 0xBB, 0xBF]) {
        return Err(Error::invalid_input("json: byte-order mark is not allowed"));
    }
    if let Err(e) = std::str::from_utf8(input) {
        return Err(Error::invalid_input(format!("json: invalid UTF-8 at byte {}", e.valid_up_to())));
    }
    let max_depth = limits.max_json_depth.min(crate::limits::JSON_DEPTH_CEILING);
    let mut p = Parser { bytes: input, pos: 0, depth: 0, max_depth };
    p.skip_ws();
    let value = p.value()?;
    p.skip_ws();
    if p.pos != p.bytes.len() {
        return Err(p.error("unexpected data after the document"));
    }
    Ok(value)
}

struct Parser<'a> {
    bytes: &'a [u8],
    pos: usize,
    depth: u32,
    max_depth: u32,
}

impl Parser<'_> {
    fn error(&self, what: &str) -> Error {
        Error::invalid_input(format!("json: {what} at byte {}", self.pos))
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn skip_ws(&mut self) {
        while let Some(b' ' | b'\t' | b'\n' | b'\r') = self.peek() {
            self.pos += 1;
        }
    }

    fn expect(&mut self, byte: u8) -> Result<()> {
        if self.peek() == Some(byte) {
            self.pos += 1;
            Ok(())
        } else {
            Err(self.error(&format!("expected '{}'", byte as char)))
        }
    }

    fn value(&mut self) -> Result<Value> {
        match self.peek() {
            Some(b'{') => self.object(),
            Some(b'[') => self.array(),
            Some(b'"') => Ok(Value::String(self.string()?)),
            Some(b't') => self.literal("true", Value::Bool(true)),
            Some(b'f') => self.literal("false", Value::Bool(false)),
            Some(b'n') => self.literal("null", Value::Null),
            Some(b'-' | b'0'..=b'9') => self.number(),
            Some(_) => Err(self.error("unexpected character")),
            None => Err(self.error("unexpected end of input")),
        }
    }

    fn literal(&mut self, text: &str, value: Value) -> Result<Value> {
        if self.bytes[self.pos..].starts_with(text.as_bytes()) {
            self.pos += text.len();
            Ok(value)
        } else {
            Err(self.error("invalid literal"))
        }
    }

    fn enter(&mut self) -> Result<()> {
        self.depth += 1;
        if self.depth > self.max_depth {
            return Err(Error::limit_exceeded(format!(
                "json: nesting depth exceeds the limit {} at byte {}",
                self.max_depth, self.pos
            )));
        }
        Ok(())
    }

    fn object(&mut self) -> Result<Value> {
        self.enter()?;
        self.pos += 1; // '{'
        let mut object = Object::new();
        let mut seen: HashSet<String> = HashSet::new();
        self.skip_ws();
        if self.peek() == Some(b'}') {
            self.pos += 1;
            self.depth -= 1;
            return Ok(Value::Object(object));
        }
        loop {
            self.skip_ws();
            if self.peek() != Some(b'"') {
                return Err(self.error("expected a string key"));
            }
            let key_pos = self.pos;
            let key = self.string()?;
            if !seen.insert(key.clone()) {
                return Err(Error::invalid_input(format!("json: duplicate key {key:?} at byte {key_pos}")));
            }
            self.skip_ws();
            self.expect(b':')?;
            self.skip_ws();
            let value = self.value()?;
            object.push_unique(key, value);
            self.skip_ws();
            match self.peek() {
                Some(b',') => self.pos += 1,
                Some(b'}') => {
                    self.pos += 1;
                    break;
                }
                _ => return Err(self.error("expected ',' or '}'")),
            }
        }
        self.depth -= 1;
        Ok(Value::Object(object))
    }

    fn array(&mut self) -> Result<Value> {
        self.enter()?;
        self.pos += 1; // '['
        let mut items = Vec::new();
        self.skip_ws();
        if self.peek() == Some(b']') {
            self.pos += 1;
            self.depth -= 1;
            return Ok(Value::Array(items));
        }
        loop {
            self.skip_ws();
            items.push(self.value()?);
            self.skip_ws();
            match self.peek() {
                Some(b',') => self.pos += 1,
                Some(b']') => {
                    self.pos += 1;
                    break;
                }
                _ => return Err(self.error("expected ',' or ']'")),
            }
        }
        self.depth -= 1;
        Ok(Value::Array(items))
    }

    fn hex4(&mut self) -> Result<u32> {
        let digits =
            self.bytes.get(self.pos..self.pos + 4).ok_or_else(|| self.error("truncated \\u escape"))?;
        let mut v = 0u32;
        for &d in digits {
            let nibble =
                (d as char).to_digit(16).ok_or_else(|| self.error("invalid hex digit in \\u escape"))?;
            v = (v << 4) | nibble;
        }
        self.pos += 4;
        Ok(v)
    }

    /// Parses a string starting at the opening quote.
    fn string(&mut self) -> Result<String> {
        self.pos += 1; // opening quote
        let mut out: Vec<u8> = Vec::new();
        loop {
            // Copy the run of ordinary bytes in one step. The input is known
            // to be valid UTF-8, and runs end only at ASCII bytes, so every
            // copied run is itself valid UTF-8.
            let start = self.pos;
            while let Some(b) = self.peek() {
                if b == b'"' || b == b'\\' || b < 0x20 {
                    break;
                }
                self.pos += 1;
            }
            out.extend_from_slice(&self.bytes[start..self.pos]);
            match self.peek() {
                Some(b'"') => {
                    self.pos += 1;
                    break;
                }
                Some(b'\\') => {
                    self.pos += 1;
                    let esc = self.peek().ok_or_else(|| self.error("truncated escape"))?;
                    self.pos += 1;
                    let simple = match esc {
                        b'"' => Some(b'"'),
                        b'\\' => Some(b'\\'),
                        b'/' => Some(b'/'),
                        b'b' => Some(0x08),
                        b'f' => Some(0x0C),
                        b'n' => Some(b'\n'),
                        b'r' => Some(b'\r'),
                        b't' => Some(b'\t'),
                        b'u' => None,
                        _ => {
                            self.pos -= 1;
                            return Err(self.error("invalid escape"));
                        }
                    };
                    if let Some(b) = simple {
                        out.push(b);
                        continue;
                    }
                    let first = self.hex4()?;
                    let code = match first {
                        0xD800..=0xDBFF => {
                            if !self.bytes[self.pos..].starts_with(b"\\u") {
                                return Err(self.error("unpaired high surrogate"));
                            }
                            self.pos += 2;
                            let second = self.hex4()?;
                            if !(0xDC00..=0xDFFF).contains(&second) {
                                return Err(self.error("invalid low surrogate"));
                            }
                            0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                        }
                        0xDC00..=0xDFFF => return Err(self.error("unpaired low surrogate")),
                        cp => cp,
                    };
                    let ch = char::from_u32(code).ok_or_else(|| self.error("invalid code point"))?;
                    let mut buf = [0u8; 4];
                    out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                }
                Some(_) => return Err(self.error("control character in string")),
                None => return Err(self.error("unterminated string")),
            }
        }
        String::from_utf8(out).map_err(|_| Error::internal("json: string assembly produced invalid UTF-8"))
    }

    fn digits(&mut self) -> usize {
        let start = self.pos;
        while let Some(b'0'..=b'9') = self.peek() {
            self.pos += 1;
        }
        self.pos - start
    }

    fn number(&mut self) -> Result<Value> {
        let start = self.pos;
        let negative = self.peek() == Some(b'-');
        if negative {
            self.pos += 1;
        }
        match self.peek() {
            Some(b'0') => {
                self.pos += 1;
                if let Some(b'0'..=b'9') = self.peek() {
                    return Err(self.error("leading zeros are not allowed"));
                }
            }
            Some(b'1'..=b'9') => {
                self.digits();
            }
            _ => return Err(self.error("expected a digit")),
        }
        let mut integral = true;
        if self.peek() == Some(b'.') {
            integral = false;
            self.pos += 1;
            if self.digits() == 0 {
                return Err(self.error("expected a digit after '.'"));
            }
        }
        if let Some(b'e' | b'E') = self.peek() {
            integral = false;
            self.pos += 1;
            if let Some(b'+' | b'-') = self.peek() {
                self.pos += 1;
            }
            if self.digits() == 0 {
                return Err(self.error("expected a digit in the exponent"));
            }
        }
        // The grammar above admits only ASCII, so this cannot fail.
        let text = std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|_| Error::internal("json: number text is not ASCII"))?;
        if integral {
            let exact = if negative {
                text.parse::<i64>().ok().map(Number::from_i64)
            } else {
                text.parse::<u64>().ok().map(Number::from_u64)
            };
            if let Some(n) = exact {
                return Ok(Value::Number(n));
            }
        }
        let v: f64 = text.parse().map_err(|_| self.error("unparseable number"))?;
        Number::from_f64(v).map(Value::Number).ok_or_else(|| {
            Error::invalid_input(format!(
                "json: number {text} is out of the representable range at byte {start}"
            ))
        })
    }
}
