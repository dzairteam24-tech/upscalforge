//! Export profiles (ADR-0016). The Adobe Stock photo rules are data,
//! embedded from `policy/export/adobe-stock-photo.json`, so they can be
//! updated without code changes.

use sf_core::json::{self, Value};
use sf_core::{Error, Limits, Result};

/// Rules of an export profile.
#[derive(Debug, Clone, PartialEq)]
pub struct ExportRules {
    /// Profile identifier.
    pub id: String,
    /// Rule-set version.
    pub version: u64,
    /// Where the rules came from, and their reliability.
    pub source: String,
    /// Minimum output megapixels.
    pub min_megapixels: f64,
    /// Maximum output megapixels.
    pub max_megapixels: f64,
    /// Maximum file size in bytes.
    pub max_file_bytes: u64,
    /// Lowest JPEG quality used before failing.
    pub jpeg_quality_floor: u8,
    /// Highest JPEG quality tried.
    pub jpeg_quality_start: u8,
    /// Model licence scopes that may not be used.
    pub blocked_licence_scopes: Vec<String>,
}

const ADOBE_STOCK: &str = include_str!("../../../policy/export/adobe-stock-photo.json");

impl ExportRules {
    /// The built-in Adobe Stock photo rules.
    pub fn adobe_stock() -> Result<ExportRules> {
        Self::parse(ADOBE_STOCK.as_bytes())
    }

    /// Parses a rules file.
    pub fn parse(bytes: &[u8]) -> Result<ExportRules> {
        let v = json::parse(bytes, &Limits::default())?;
        let num = |k: &str| {
            v.get(k)
                .and_then(Value::as_f64)
                .ok_or_else(|| Error::invalid_input(format!("export rules: missing {k}")))
        };
        let s = |k: &str| {
            v.get(k)
                .and_then(Value::as_str)
                .map(str::to_string)
                .ok_or_else(|| Error::invalid_input(format!("export rules: missing {k}")))
        };
        let rules = ExportRules {
            id: s("profile")?,
            version: num("version")? as u64,
            source: s("source")?,
            min_megapixels: num("min_megapixels")?,
            max_megapixels: num("max_megapixels")?,
            max_file_bytes: num("max_file_bytes")? as u64,
            jpeg_quality_floor: num("jpeg_quality_floor")?.clamp(1.0, 100.0) as u8,
            jpeg_quality_start: num("jpeg_quality_start")?.clamp(1.0, 100.0) as u8,
            blocked_licence_scopes: v
                .get("blocked_licence_scopes")
                .and_then(Value::as_array)
                .map(|a| a.iter().filter_map(Value::as_str).map(str::to_string).collect())
                .unwrap_or_default(),
        };
        if rules.min_megapixels > rules.max_megapixels || rules.jpeg_quality_floor > rules.jpeg_quality_start
        {
            return Err(Error::invalid_input("export rules are inconsistent"));
        }
        Ok(rules)
    }

    /// The smallest native scale reaching the minimum megapixels, and
    /// whether a final downscale is needed to respect the maximum.
    pub fn choose_scale(&self, width: u32, height: u32) -> (u32, Option<(u32, u32)>) {
        let mp = |s: u32| f64::from(width) * f64::from(height) * f64::from(s * s) / 1e6;
        let scale = [1u32, 2, 4, 8].into_iter().find(|&s| mp(s) >= self.min_megapixels).unwrap_or(8);
        if mp(scale) > self.max_megapixels {
            let f = (self.max_megapixels / mp(scale)).sqrt();
            let (w, h) = (
                (f64::from(width * scale) * f).floor() as u32,
                (f64::from(height * scale) * f).floor() as u32,
            );
            (scale, Some((w, h)))
        } else {
            (scale, None)
        }
    }
}

/// Outcome of a compliance check.
#[derive(Debug, Clone, PartialEq)]
pub struct Compliance {
    /// Profile identifier and version.
    pub profile: String,
    /// `pass`, `pass-with-warnings` or `fail`.
    pub verdict: &'static str,
    /// Individual rule results: (rule, ok, detail).
    pub rules: Vec<(String, bool, String)>,
    /// Warnings (do not fail the check).
    pub warnings: Vec<String>,
    /// AI-use disclosure to support the user's own labelling decision.
    pub ai_disclosure: String,
}

impl Compliance {
    /// Builds the verdict from rules and warnings.
    pub fn finish(
        profile: String,
        rules: Vec<(String, bool, String)>,
        warnings: Vec<String>,
        ai_disclosure: String,
    ) -> Compliance {
        let verdict = if rules.iter().any(|r| !r.1) {
            "fail"
        } else if warnings.is_empty() {
            "pass"
        } else {
            "pass-with-warnings"
        };
        Compliance { profile, verdict, rules, warnings, ai_disclosure }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn built_in_rules_parse_and_choose_scales() {
        let r = ExportRules::adobe_stock().unwrap();
        assert_eq!(r.id, "adobe-stock-photo");
        assert!(r.blocked_licence_scopes.contains(&"non-commercial".to_string()));
        // 1000×800 = 0.8 MP → ×4 gives 12.8 MP (×2 gives only 3.2 MP).
        assert_eq!(r.choose_scale(1000, 800), (4, None));
        // Already 6 MP → no enlargement.
        assert_eq!(r.choose_scale(3000, 2000), (1, None));
        // 3000×2000 at ×... a tiny 700×500 image ×8 = 22.4 MP.
        assert_eq!(r.choose_scale(700, 500).0, 4);
        // 12000×9000 = 108 MP → must be reduced to ≤ 100 MP.
        let (s, down) = r.choose_scale(12_000, 9_000);
        assert_eq!(s, 1);
        let (w, h) = down.unwrap();
        assert!(f64::from(w) * f64::from(h) / 1e6 <= 100.0);
    }

    #[test]
    fn verdicts() {
        let ok =
            Compliance::finish("p".into(), vec![("a".into(), true, String::new())], vec![], String::new());
        assert_eq!(ok.verdict, "pass");
        let warn = Compliance::finish(
            "p".into(),
            vec![("a".into(), true, String::new())],
            vec!["w".into()],
            String::new(),
        );
        assert_eq!(warn.verdict, "pass-with-warnings");
        let bad =
            Compliance::finish("p".into(), vec![("a".into(), false, String::new())], vec![], String::new());
        assert_eq!(bad.verdict, "fail");
    }
}
