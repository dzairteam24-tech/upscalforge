//! A small, strict command-line parser: `command [positional…] [--flag
//! [value]]…`. Unknown flags are errors, never silently ignored.

use std::collections::HashMap;

use sf_core::{Error, Result};

/// Parsed arguments.
#[derive(Debug, Default)]
pub struct Args {
    /// Positional arguments after the command.
    pub positional: Vec<String>,
    values: HashMap<String, String>,
    switches: Vec<String>,
}

/// Flag specification: name and whether it takes a value.
pub type Spec = &'static [(&'static str, bool)];

impl Args {
    /// Parses `raw` (without the program name and command) against `spec`.
    pub fn parse(raw: &[String], spec: Spec) -> Result<Args> {
        let mut a = Args::default();
        let mut i = 0;
        while i < raw.len() {
            let arg = &raw[i];
            let name = if arg == "-o" { Some("output") } else { arg.strip_prefix("--") };
            match name {
                Some(n) if !n.is_empty() => {
                    let (key, inline) = match n.split_once('=') {
                        Some((k, v)) => (k, Some(v.to_string())),
                        None => (n, None),
                    };
                    let takes = spec.iter().find(|(k, _)| *k == key).map(|(_, v)| *v).ok_or_else(|| {
                        let known: Vec<String> = spec.iter().map(|(k, _)| format!("--{k}")).collect();
                        Error::invalid_input(format!("unknown option --{key} (known: {})", known.join(", ")))
                    })?;
                    if takes {
                        let v = match inline {
                            Some(v) => v,
                            None => {
                                i += 1;
                                raw.get(i)
                                    .cloned()
                                    .ok_or_else(|| Error::invalid_input(format!("--{key} needs a value")))?
                            }
                        };
                        a.values.insert(key.to_string(), v);
                    } else {
                        if inline.is_some() {
                            return Err(Error::invalid_input(format!("--{key} takes no value")));
                        }
                        a.switches.push(key.to_string());
                    }
                }
                _ => a.positional.push(arg.clone()),
            }
            i += 1;
        }
        Ok(a)
    }

    /// A flag's value.
    pub fn value(&self, key: &str) -> Option<&str> {
        self.values.get(key).map(String::as_str)
    }

    /// A flag's value parsed as a number.
    pub fn number<T: std::str::FromStr>(&self, key: &str) -> Result<Option<T>> {
        self.value(key)
            .map(|v| {
                v.parse::<T>()
                    .map_err(|_| Error::invalid_input(format!("--{key}: {v:?} is not a valid number")))
            })
            .transpose()
    }

    /// True if a switch was given.
    pub fn has(&self, key: &str) -> bool {
        self.switches.iter().any(|s| s == key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SPEC: Spec = &[("output", true), ("scale", true), ("overwrite", false)];

    fn v(s: &[&str]) -> Vec<String> {
        s.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn parses_values_switches_and_positionals() {
        let a = Args::parse(&v(&["in.png", "-o", "out.png", "--scale=4", "--overwrite"]), SPEC).unwrap();
        assert_eq!(a.positional, vec!["in.png"]);
        assert_eq!(a.value("output"), Some("out.png"));
        assert_eq!(a.number::<u32>("scale").unwrap(), Some(4));
        assert!(a.has("overwrite"));
    }

    #[test]
    fn rejects_unknown_and_malformed_flags() {
        assert!(Args::parse(&v(&["--nope"]), SPEC).unwrap_err().message().contains("unknown option --nope"));
        assert!(Args::parse(&v(&["--scale"]), SPEC).is_err());
        assert!(Args::parse(&v(&["--overwrite=yes"]), SPEC).is_err());
        let a = Args::parse(&v(&["--scale", "x"]), SPEC).unwrap();
        assert!(a.number::<u32>("scale").is_err());
    }
}
