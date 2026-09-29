//! JSON tests. Cases are derived from the RFC 8259 grammar and from the
//! strictness rules documented in the module.

use super::*;
use crate::{ErrorKind, Limits, Rng};

fn ok(text: &str) -> Value {
    parse(text.as_bytes(), &Limits::default()).unwrap_or_else(|e| panic!("{text:?} should parse: {e}"))
}

fn err(text: &[u8]) -> ErrorKind {
    match parse(text, &Limits::default()) {
        Ok(v) => panic!("{:?} should fail, parsed {v:?}", String::from_utf8_lossy(text)),
        Err(e) => e.kind(),
    }
}

#[test]
fn scalars() {
    assert_eq!(ok("null"), Value::Null);
    assert_eq!(ok(" true "), Value::Bool(true));
    assert_eq!(ok("false"), Value::Bool(false));
    assert_eq!(ok("0").as_u64(), Some(0));
    assert_eq!(ok("-0").as_u64(), Some(0), "-0 is the integer zero");
    assert_eq!(ok("18446744073709551615").as_u64(), Some(u64::MAX));
    assert_eq!(ok("-9223372036854775808").as_i64(), Some(i64::MIN));
    assert_eq!(ok("1.5").as_f64(), Some(1.5));
    assert_eq!(ok("-2.5e-3").as_f64(), Some(-0.0025));
    assert_eq!(ok("1E2").as_f64(), Some(100.0));
    assert_eq!(ok("\"a\\u00e9\\n\"").as_str(), Some("aé\n"));
}

#[test]
fn integers_beyond_64_bits_become_floats() {
    let v = ok("18446744073709551616");
    assert_eq!(v.as_u64(), None);
    assert_eq!(v.as_f64(), Some(18446744073709551616.0));
    let v = ok("-9223372036854775809");
    assert_eq!(v.as_i64(), None);
    assert!(v.as_f64().unwrap() < -9.2e18);
}

#[test]
fn surrogate_pairs() {
    assert_eq!(ok("\"\\ud83d\\ude00\"").as_str(), Some("\u{1F600}"));
    assert_eq!(err(b"\"\\ud83d\""), ErrorKind::InvalidInput);
    assert_eq!(err(b"\"\\ude00\""), ErrorKind::InvalidInput);
    assert_eq!(err(b"\"\\ud83d\\u0041\""), ErrorKind::InvalidInput);
}

#[test]
fn containers_and_access() {
    let v = ok(r#"{"name":"sf-base","scales":[1,2,4,8],"meta":{"fp16":true}}"#);
    assert_eq!(v.get("name").and_then(Value::as_str), Some("sf-base"));
    let scales: Vec<u64> =
        v.get("scales").unwrap().as_array().unwrap().iter().filter_map(Value::as_u64).collect();
    assert_eq!(scales, [1, 2, 4, 8]);
    assert_eq!(v.get("meta").and_then(|m| m.get("fp16")).and_then(Value::as_bool), Some(true));
    assert_eq!(v.get("missing"), None);
    assert_eq!(ok("[]"), Value::Array(vec![]));
    assert_eq!(ok("{ }"), Value::Object(Object::new()));
}

#[test]
fn rejected_syntax() {
    let cases: &[&[u8]] = &[
        b"",
        b"   ",
        b"nul",
        b"True",
        b"[1,]",
        b"{\"a\":1,}",
        b"[1 2]",
        b"{\"a\" 1}",
        b"{a:1}",
        b"'x'",
        b"01",
        b"-",
        b"1.",
        b".5",
        b"1e",
        b"+1",
        b"NaN",
        b"Infinity",
        b"[1] x",
        b"\"tab\there\"",
        b"\"\\x\"",
        b"\"\\u12\"",
        b"\"unterminated",
        b"// comment\n1",
        b"[",
        b"{\"a\":",
    ];
    for c in cases {
        assert_eq!(err(c), ErrorKind::InvalidInput, "{:?}", String::from_utf8_lossy(c));
    }
}

#[test]
fn rejects_out_of_range_float() {
    assert_eq!(err(b"1e400"), ErrorKind::InvalidInput);
}

#[test]
fn rejects_invalid_utf8_and_bom() {
    assert_eq!(err(b"\"\xff\""), ErrorKind::InvalidInput);
    assert_eq!(err(b"\xEF\xBB\xBFnull"), ErrorKind::InvalidInput);
}

#[test]
fn rejects_duplicate_keys() {
    assert_eq!(err(br#"{"a":1,"b":2,"a":3}"#), ErrorKind::InvalidInput);
    // Keys equal only after escape decoding are duplicates too.
    assert_eq!(err(br#"{"a":1,"\u0061":2}"#), ErrorKind::InvalidInput);
}

#[test]
fn enforces_size_and_depth_limits() {
    let limits = Limits { max_json_bytes: 8, max_json_depth: 3, ..Limits::default() };
    assert_eq!(parse(b"[1,2,3,4,5]", &limits).unwrap_err().kind(), ErrorKind::LimitExceeded);
    assert!(parse(b"[[[1]]]", &limits).is_ok());
    assert_eq!(parse(b"[[[[1]]]]", &limits).unwrap_err().kind(), ErrorKind::LimitExceeded);
}

#[test]
fn deep_nesting_at_the_ceiling_does_not_overflow_the_stack() {
    let limits = Limits { max_json_depth: crate::limits::JSON_DEPTH_CEILING, ..Limits::default() };
    let depth = crate::limits::JSON_DEPTH_CEILING as usize;
    let doc = format!("{}{}", "[".repeat(depth), "]".repeat(depth));
    assert!(parse(doc.as_bytes(), &limits).is_ok());
    let too_deep = format!("[{doc}]");
    assert_eq!(parse(too_deep.as_bytes(), &limits).unwrap_err().kind(), ErrorKind::LimitExceeded);
}

#[test]
fn writer_output() {
    let mut o = Object::new();
    o.insert("name", "q\"uote\\");
    o.insert("n", Value::Number(Number::from_i64(-3)));
    o.insert("f", Value::Number(Number::from_f64(0.5).unwrap()));
    o.insert("ctl", "\u{1}");
    o.insert("list", vec![Value::Null, Value::Bool(true)]);
    o.insert("n", 7u64); // replace keeps position
    let v = Value::Object(o);
    assert_eq!(
        to_string(&v).unwrap(),
        r#"{"name":"q\"uote\\","n":7,"f":0.5,"ctl":"\u0001","list":[null,true]}"#
    );
    let pretty = to_string_pretty(&v).unwrap();
    assert!(pretty.contains("\n  \"list\": [\n    null,\n    true\n  ]\n"), "{pretty}");
    assert_eq!(parse(pretty.as_bytes(), &Limits::default()).unwrap(), v);
    assert!(Number::from_f64(f64::NAN).is_none());
    assert!(Number::from_f64(f64::INFINITY).is_none());
}

#[test]
fn floats_stay_floats_through_a_round_trip() {
    for f in [2.0, 0.1, 1e300, -1e-7, 5e-324, 123456789.125] {
        let v = Value::Number(Number::from_f64(f).unwrap());
        let text = to_string(&v).unwrap();
        let back = parse(text.as_bytes(), &Limits::default()).unwrap();
        assert_eq!(back, v, "{f} -> {text}");
    }
}

fn random_string(rng: &mut Rng) -> String {
    const POOL: &[char] =
        &['a', 'Z', '0', ' ', '"', '\\', '/', '\n', '\u{1}', '\u{7f}', 'é', '中', '\u{1F600}'];
    (0..rng.below(8)).map(|_| POOL[rng.below(POOL.len() as u64) as usize]).collect()
}

fn random_value(rng: &mut Rng, depth: u32) -> Value {
    let kind = if depth >= 4 { rng.below(4) } else { rng.below(6) };
    match kind {
        0 => Value::Null,
        1 => Value::Bool(rng.below(2) == 1),
        2 => match rng.below(3) {
            0 => Value::from(rng.next_u64()),
            1 => Value::from(-(rng.below(1 << 62) as i64) - 1),
            _ => {
                let f = f64::from_bits(rng.next_u64());
                Value::Number(Number::from_f64(f).unwrap_or_else(|| Number::from_f64(0.25).unwrap()))
            }
        },
        3 => Value::String(random_string(rng)),
        4 => Value::Array((0..rng.below(5)).map(|_| random_value(rng, depth + 1)).collect()),
        _ => {
            let mut o = Object::new();
            for _ in 0..rng.below(5) {
                o.insert(random_string(rng), random_value(rng, depth + 1));
            }
            Value::Object(o)
        }
    }
}

/// Property: every generated document survives write → parse unchanged,
/// in both compact and pretty form.
#[test]
fn property_round_trip() {
    let mut rng = Rng::seed_from_u64(0x0150_7e57);
    for _ in 0..3_000 {
        let v = random_value(&mut rng, 0);
        for text in [to_string(&v).unwrap(), to_string_pretty(&v).unwrap()] {
            let back = parse(text.as_bytes(), &Limits::default()).unwrap_or_else(|e| panic!("{text}: {e}"));
            assert_eq!(back, v, "{text}");
        }
    }
}

/// Robustness: mutated and random inputs must produce `Ok` or `Err`,
/// never a panic. (Coverage-guided fuzzing is added with the fuzz targets.)
#[test]
fn mutated_inputs_never_panic() {
    let mut rng = Rng::seed_from_u64(0xbad_5eed);
    let seeds: Vec<Vec<u8>> =
        (0..64).map(|_| to_string(&random_value(&mut rng, 0)).unwrap().into_bytes()).collect();
    for i in 0..30_000 {
        let mut doc = seeds[i % seeds.len()].clone();
        for _ in 0..=rng.below(4) {
            let action = rng.below(3);
            if doc.is_empty() || action == 0 {
                let at = rng.below(doc.len() as u64 + 1) as usize;
                doc.insert(at, rng.next_u64() as u8);
            } else {
                let at = rng.below(doc.len() as u64) as usize;
                if action == 1 {
                    doc[at] = rng.next_u64() as u8
                } else {
                    doc.remove(at);
                }
            }
        }
        let _ = parse(&doc, &Limits::default());
    }
}
