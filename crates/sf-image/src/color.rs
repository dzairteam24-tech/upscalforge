//! Colour management: transfer functions, ICC profile reading
//! (matrix/TRC profiles), our own sRGB profile, and conversion to sRGB.
//!
//! The processing policy (ADR-0005) is to work in the image's native
//! encoding and pass its profile through unchanged. The conversion here is
//! used where an output must be sRGB (e.g. the Adobe Stock export profile).

use sf_core::{Error, Result};

/// sRGB electro-optical transfer: encoded value → linear light.
pub fn srgb_to_linear(v: f32) -> f32 {
    if v <= 0.040_45 { v / 12.92 } else { ((v + 0.055) / 1.055).powf(2.4) }
}

/// Inverse sRGB transfer: linear light → encoded value.
pub fn linear_to_srgb(v: f32) -> f32 {
    if v <= 0.003_130_8 { v * 12.92 } else { 1.055 * v.powf(1.0 / 2.4) - 0.055 }
}

/// A tone reproduction curve from an ICC profile (encoded → linear).
#[derive(Debug, Clone, PartialEq)]
pub enum Curve {
    /// Identity.
    Linear,
    /// Pure power law with the given exponent.
    Gamma(f32),
    /// Sampled curve over [0, 1] (values in [0, 1]).
    Table(Vec<f32>),
    /// ICC parametric curve (function type 0–4 with parameters g, a, b, c, d, e, f).
    Parametric(u16, [f32; 7]),
}

impl Curve {
    /// Encoded → linear.
    pub fn eval(&self, x: f32) -> f32 {
        let x = x.clamp(0.0, 1.0);
        match self {
            Curve::Linear => x,
            Curve::Gamma(g) => x.powf(*g),
            Curve::Table(t) => {
                let pos = x * (t.len() - 1) as f32;
                let i = (pos.floor() as usize).min(t.len() - 2);
                let f = pos - i as f32;
                t[i] * (1.0 - f) + t[i + 1] * f
            }
            Curve::Parametric(kind, p) => {
                let [g, a, b, c, d, e, f] = *p;
                match kind {
                    0 => x.powf(g),
                    1 => {
                        if x >= -b / a {
                            (a * x + b).powf(g)
                        } else {
                            0.0
                        }
                    }
                    2 => {
                        if x >= -b / a {
                            (a * x + b).powf(g) + c
                        } else {
                            c
                        }
                    }
                    3 => {
                        if x >= d {
                            (a * x + b).powf(g)
                        } else {
                            c * x
                        }
                    }
                    _ => {
                        if x >= d {
                            (a * x + b).powf(g) + e
                        } else {
                            c * x + f
                        }
                    }
                }
            }
        }
    }

    /// Linear → encoded, by bisection on the (monotone) forward curve.
    pub fn inverse(&self, y: f32) -> f32 {
        let (mut lo, mut hi) = (0.0f32, 1.0f32);
        for _ in 0..30 {
            let mid = 0.5 * (lo + hi);
            if self.eval(mid) < y { lo = mid } else { hi = mid }
        }
        0.5 * (lo + hi)
    }
}

/// How an image's encoded values relate to light.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TransferClass {
    /// Close to the sRGB curve.
    SrgbLike,
    /// A power law with this exponent (other than sRGB-like).
    Gamma(f32),
    /// Linear light.
    Linear,
    /// Not determinable (e.g. LUT-based profile).
    Unknown,
}

/// The parts of an ICC profile ScaleForge interprets.
#[derive(Debug, Clone, PartialEq)]
pub struct IccProfile {
    /// Data colour space signature, e.g. `*b"RGB "` or `*b"GRAY"`.
    pub color_space: [u8; 4],
    /// Profile description, if readable.
    pub description: Option<String>,
    /// RGB → XYZ (D50) matrix, columns = red, green, blue colorants.
    pub matrix: Option<[[f32; 3]; 3]>,
    /// Per-channel curves (one for grey).
    pub curves: Option<Vec<Curve>>,
}

fn icc_bad(what: &str) -> Error {
    Error::invalid_input(format!("icc: {what}"))
}

fn be32(d: &[u8], p: usize) -> Result<u32> {
    d.get(p..p + 4).map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]])).ok_or_else(|| icc_bad("truncated"))
}

fn s15f16(d: &[u8], p: usize) -> Result<f32> {
    Ok(be32(d, p)? as i32 as f32 / 65_536.0)
}

impl IccProfile {
    /// Parses the header, tag table and matrix/TRC tags of a profile.
    pub fn parse(d: &[u8]) -> Result<IccProfile> {
        if d.len() < 132 || &d[36..40] != b"acsp" {
            return Err(icc_bad("not an ICC profile"));
        }
        let color_space: [u8; 4] = d[16..20].try_into().expect("4 bytes");
        let count = be32(d, 128)? as usize;
        if count > 1_000 {
            return Err(icc_bad("implausible tag count"));
        }
        let mut tags: Vec<([u8; 4], usize, usize)> = Vec::with_capacity(count);
        for i in 0..count {
            let e = 132 + i * 12;
            let sig: [u8; 4] =
                d.get(e..e + 4).ok_or_else(|| icc_bad("truncated tag table"))?.try_into().expect("4 bytes");
            let (off, size) = (be32(d, e + 4)? as usize, be32(d, e + 8)? as usize);
            if off.checked_add(size).is_none_or(|end| end > d.len()) {
                return Err(icc_bad("tag outside the profile"));
            }
            tags.push((sig, off, size));
        }
        let tag = |sig: &[u8; 4]| tags.iter().find(|t| &t.0 == sig).map(|t| &d[t.1..t.1 + t.2]);
        let xyz = |sig: &[u8; 4]| -> Option<[f32; 3]> {
            let t = tag(sig)?;
            if t.len() < 20 || &t[0..4] != b"XYZ " {
                return None;
            }
            Some([s15f16(t, 8).ok()?, s15f16(t, 12).ok()?, s15f16(t, 16).ok()?])
        };
        let matrix = match (xyz(b"rXYZ"), xyz(b"gXYZ"), xyz(b"bXYZ")) {
            (Some(r), Some(g), Some(b)) => Some([[r[0], g[0], b[0]], [r[1], g[1], b[1]], [r[2], g[2], b[2]]]),
            _ => None,
        };
        let curve_sigs: &[&[u8; 4]] =
            if &color_space == b"GRAY" { &[b"kTRC"] } else { &[b"rTRC", b"gTRC", b"bTRC"] };
        let curves: Option<Vec<Curve>> = curve_sigs.iter().map(|s| tag(s).and_then(parse_curve)).collect();
        let description = tag(b"desc").and_then(parse_description);
        Ok(IccProfile { color_space, description, matrix, curves })
    }

    /// Classifies the transfer function (using the green/grey curve).
    pub fn transfer(&self) -> TransferClass {
        let Some(curves) = &self.curves else { return TransferClass::Unknown };
        let c = &curves[curves.len().min(2) - 1];
        let samples = [0.02f32, 0.1, 0.25, 0.5, 0.75, 0.9];
        let close = |f: &dyn Fn(f32) -> f32| samples.iter().all(|&x| (c.eval(x) - f(x)).abs() < 0.004);
        if close(&|x| x) {
            TransferClass::Linear
        } else if close(&srgb_to_linear) {
            TransferClass::SrgbLike
        } else if let Curve::Gamma(g) = c {
            TransferClass::Gamma(*g)
        } else {
            // Fit a power law through mid-grey and accept it if it matches.
            let g = c.eval(0.5).max(1e-6).ln() / 0.5f32.ln();
            if close(&|x| x.powf(g)) { TransferClass::Gamma(g) } else { TransferClass::Unknown }
        }
    }
}

fn parse_curve(t: &[u8]) -> Option<Curve> {
    match t.get(0..4)? {
        b"curv" => {
            let n = be32(t, 8).ok()? as usize;
            match n {
                0 => Some(Curve::Linear),
                1 => Some(Curve::Gamma(f32::from(u16::from_be_bytes([*t.get(12)?, *t.get(13)?])) / 256.0)),
                _ if n <= 65_536 => {
                    let v: Option<Vec<f32>> = (0..n)
                        .map(|i| {
                            t.get(12 + 2 * i..14 + 2 * i)
                                .map(|b| f32::from(u16::from_be_bytes([b[0], b[1]])) / 65_535.0)
                        })
                        .collect();
                    v.map(Curve::Table)
                }
                _ => None,
            }
        }
        b"para" => {
            let kind = u16::from_be_bytes([*t.get(8)?, *t.get(9)?]);
            let n = match kind {
                0 => 1,
                1 => 3,
                2 => 4,
                3 => 5,
                4 => 7,
                _ => return None,
            };
            let mut p = [0f32; 7];
            for (i, v) in p.iter_mut().enumerate().take(n) {
                *v = s15f16(t, 12 + 4 * i).ok()?;
            }
            Some(Curve::Parametric(kind, p))
        }
        _ => None,
    }
}

fn parse_description(t: &[u8]) -> Option<String> {
    match t.get(0..4)? {
        b"desc" => {
            let n = be32(t, 8).ok()? as usize;
            let s = t.get(12..12 + n)?;
            Some(String::from_utf8_lossy(s).trim_end_matches('\0').to_string())
        }
        b"mluc" => {
            let count = be32(t, 8).ok()? as usize;
            if count == 0 {
                return None;
            }
            let (len, off) = (be32(t, 20).ok()? as usize, be32(t, 24).ok()? as usize);
            let units: Vec<u16> = t
                .get(off..off + len)?
                .chunks(2)
                .map(|b| u16::from_be_bytes([b[0], *b.get(1).unwrap_or(&0)]))
                .collect();
            Some(String::from_utf16_lossy(&units))
        }
        _ => None,
    }
}

// ------------------------------------------------------------ colour math

type M3 = [[f64; 3]; 3];

fn mul(a: &M3, b: &M3) -> M3 {
    let mut r = [[0.0; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            r[i][j] = (0..3).map(|k| a[i][k] * b[k][j]).sum();
        }
    }
    r
}

fn apply(m: &M3, v: [f64; 3]) -> [f64; 3] {
    [0, 1, 2].map(|i| m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2])
}

/// Inverse of a 3×3 matrix (by cofactors).
pub(crate) fn invert(m: &M3) -> Option<M3> {
    let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
        - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
        + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
    if det.abs() < 1e-12 {
        return None;
    }
    let c = |r0: usize, c0: usize, r1: usize, c1: usize| m[r0][c0] * m[r1][c1] - m[r0][c1] * m[r1][c0];
    Some([
        [c(1, 1, 2, 2) / det, -c(0, 1, 2, 2) / det, c(0, 1, 1, 2) / det],
        [-c(1, 0, 2, 2) / det, c(0, 0, 2, 2) / det, -c(0, 0, 1, 2) / det],
        [c(1, 0, 2, 1) / det, -c(0, 0, 2, 1) / det, c(0, 0, 1, 1) / det],
    ])
}

/// D50 white point of the ICC profile connection space.
pub const D50: [f64; 3] = [0.9642, 1.0, 0.8249];

fn xy_to_xyz(x: f64, y: f64) -> [f64; 3] {
    [x / y, 1.0, (1.0 - x - y) / y]
}

/// RGB → XYZ matrix from primaries and white chromaticities.
fn rgb_to_xyz(prim: [(f64, f64); 3], white: (f64, f64)) -> M3 {
    let (r, g, b) =
        (xy_to_xyz(prim[0].0, prim[0].1), xy_to_xyz(prim[1].0, prim[1].1), xy_to_xyz(prim[2].0, prim[2].1));
    let p = [[r[0], g[0], b[0]], [r[1], g[1], b[1]], [r[2], g[2], b[2]]];
    let s = apply(&invert(&p).expect("primaries are independent"), xy_to_xyz(white.0, white.1));
    [0, 1, 2].map(|i| [p[i][0] * s[0], p[i][1] * s[1], p[i][2] * s[2]])
}

/// Bradford chromatic adaptation from one white to another.
fn bradford(from: [f64; 3], to: [f64; 3]) -> M3 {
    const B: M3 = [[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367], [0.0389, -0.0685, 1.0296]];
    let (s, d) = (apply(&B, from), apply(&B, to));
    let scale = [[d[0] / s[0], 0.0, 0.0], [0.0, d[1] / s[1], 0.0], [0.0, 0.0, d[2] / s[2]]];
    mul(&invert(&B).expect("Bradford matrix is invertible"), &mul(&scale, &B))
}

/// sRGB linear RGB → XYZ relative to D50 (ICC connection space).
pub fn srgb_to_xyz_d50() -> [[f64; 3]; 3] {
    let m = rgb_to_xyz([(0.64, 0.33), (0.30, 0.60), (0.15, 0.06)], (0.3127, 0.3290));
    mul(&bradford(xy_to_xyz(0.3127, 0.3290), D50), &m)
}

/// A converter from a matrix/TRC profile's encoding to sRGB encoding.
pub struct ToSrgb {
    curves: Vec<Curve>,
    matrix: M3,
}

impl ToSrgb {
    /// Builds a converter, or explains why the profile cannot be converted
    /// exactly.
    pub fn new(profile: &IccProfile) -> Result<ToSrgb> {
        if &profile.color_space != b"RGB " {
            return Err(Error::unsupported("colour conversion to sRGB supports RGB profiles only"));
        }
        let (Some(m), Some(curves)) = (&profile.matrix, &profile.curves) else {
            return Err(Error::unsupported(
                "the embedded profile is LUT-based; exact conversion to sRGB is not supported",
            ));
        };
        let src: M3 = m.map(|r| r.map(f64::from));
        let to_srgb = invert(&srgb_to_xyz_d50()).expect("sRGB matrix is invertible");
        Ok(ToSrgb { curves: curves.clone(), matrix: mul(&to_srgb, &src) })
    }

    /// Converts one encoded RGB triple (0–1). Out-of-gamut values are clipped.
    pub fn convert(&self, rgb: [f32; 3]) -> [f32; 3] {
        let lin = [0, 1, 2].map(|i| f64::from(self.curves[i].eval(rgb[i])));
        apply(&self.matrix, lin).map(|v| linear_to_srgb(v.clamp(0.0, 1.0) as f32))
    }
}

/// Our own sRGB ICC profile (version 2.1, matrix/TRC, 1024-entry curves),
/// generated from the published sRGB parameters.
pub fn srgb_profile() -> Vec<u8> {
    fn xyz_tag(v: [f64; 3]) -> Vec<u8> {
        let mut t = b"XYZ \0\0\0\0".to_vec();
        for c in v {
            t.extend(((c * 65_536.0).round() as i32).to_be_bytes());
        }
        t
    }
    let curve = {
        let mut t = b"curv\0\0\0\0".to_vec();
        t.extend(1024u32.to_be_bytes());
        for i in 0..1024 {
            let v = srgb_to_linear(i as f32 / 1023.0);
            t.extend(((v * 65_535.0).round() as u16).to_be_bytes());
        }
        t
    };
    let desc = {
        let text = b"ScaleForge sRGB\0";
        let mut t = b"desc\0\0\0\0".to_vec();
        t.extend((text.len() as u32).to_be_bytes());
        t.extend(text);
        t.extend([0u8; 4 + 4]); // Unicode language code and count
        t.extend([0u8; 2 + 1 + 67]); // ScriptCode code, count, data
        t
    };
    let cprt = b"text\0\0\0\0No copyright, use freely\0".to_vec();
    let m = srgb_to_xyz_d50();
    let tags: Vec<(&[u8; 4], Vec<u8>)> = vec![
        (b"desc", desc),
        (b"cprt", cprt),
        (b"wtpt", xyz_tag(D50)),
        (b"rXYZ", xyz_tag([m[0][0], m[1][0], m[2][0]])),
        (b"gXYZ", xyz_tag([m[0][1], m[1][1], m[2][1]])),
        (b"bXYZ", xyz_tag([m[0][2], m[1][2], m[2][2]])),
        (b"rTRC", curve.clone()),
        (b"gTRC", curve.clone()),
        (b"bTRC", curve),
    ];
    let table_len = 4 + 12 * tags.len();
    let mut body = Vec::new();
    let mut entries = Vec::new();
    let mut shared_curve: Option<(u32, u32)> = None;
    for (sig, data) in &tags {
        let is_curve = &sig[1..] == b"TRC";
        if is_curve && let Some((off, len)) = shared_curve {
            entries.push((**sig, off, len));
            continue;
        }
        while body.len() % 4 != 0 {
            body.push(0);
        }
        let off = (128 + table_len + body.len()) as u32;
        body.extend(data);
        entries.push((**sig, off, data.len() as u32));
        if is_curve {
            shared_curve = Some((off, data.len() as u32));
        }
    }
    while body.len() % 4 != 0 {
        body.push(0);
    }
    let size = (128 + table_len + body.len()) as u32;
    let mut out = Vec::with_capacity(size as usize);
    out.extend(size.to_be_bytes());
    out.extend([0u8; 4]); // preferred CMM
    out.extend(0x0210_0000u32.to_be_bytes()); // version 2.1
    out.extend(b"mntrRGB XYZ ");
    out.extend([0u8; 12]); // date and time (not recorded)
    out.extend(b"acsp");
    out.extend([0u8; 4 + 4 + 4 + 4 + 8 + 4]); // platform, flags, manufacturer, model, attributes, intent
    for c in D50 {
        out.extend(((c * 65_536.0).round() as i32).to_be_bytes());
    }
    out.extend(b"SFRG"); // creator
    out.extend([0u8; 16 + 28]); // profile id and reserved
    out.extend((tags.len() as u32).to_be_bytes());
    for (sig, off, len) in entries {
        out.extend(sig);
        out.extend(off.to_be_bytes());
        out.extend(len.to_be_bytes());
    }
    out.extend(body);
    debug_assert_eq!(out.len(), size as usize);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn srgb_transfer_round_trips_and_hits_known_points() {
        for i in 0..=255 {
            let v = i as f32 / 255.0;
            assert!((linear_to_srgb(srgb_to_linear(v)) - v).abs() < 1e-5);
        }
        assert!((srgb_to_linear(0.5) - 0.214_04).abs() < 1e-4);
        assert_eq!(srgb_to_linear(0.0), 0.0);
        assert!((srgb_to_linear(1.0) - 1.0).abs() < 1e-6);
    }

    #[test]
    fn srgb_matrix_maps_white_to_d50_and_green_luminance() {
        let m = srgb_to_xyz_d50();
        let white = apply(&m, [1.0, 1.0, 1.0]);
        for (a, b) in white.iter().zip(D50) {
            assert!((a - b).abs() < 1e-4, "{white:?}");
        }
        // Luminance weights of sRGB primaries (Y row) sum to one.
        assert!((m[1][0] + m[1][1] + m[1][2] - 1.0).abs() < 1e-9);
        assert!(m[1][1] > 0.7 && m[1][1] < 0.72, "green carries ~71% of luminance: {}", m[1][1]);
    }

    #[test]
    fn our_srgb_profile_parses_classifies_and_converts_as_identity() {
        let p = IccProfile::parse(&srgb_profile()).unwrap();
        assert_eq!(&p.color_space, b"RGB ");
        assert_eq!(p.description.as_deref(), Some("ScaleForge sRGB"));
        assert_eq!(p.transfer(), TransferClass::SrgbLike);
        let conv = ToSrgb::new(&p).unwrap();
        for rgb in [[0.2f32, 0.5, 0.8], [1.0, 1.0, 1.0], [0.0, 0.0, 0.0], [0.9, 0.1, 0.4]] {
            let out = conv.convert(rgb);
            for (a, b) in out.iter().zip(rgb) {
                assert!((a - b).abs() < 2.0 / 255.0, "{rgb:?} -> {out:?}");
            }
        }
    }

    #[test]
    fn wide_gamut_conversion_moves_saturated_colours_inside_srgb() {
        // A Display-P3-like profile: P3 primaries, sRGB curve.
        let m = rgb_to_xyz([(0.680, 0.320), (0.265, 0.690), (0.150, 0.060)], (0.3127, 0.3290));
        let m = mul(&bradford(xy_to_xyz(0.3127, 0.3290), D50), &m).map(|r| r.map(|v| v as f32));
        let srgb_curve = IccProfile::parse(&srgb_profile()).unwrap().curves.unwrap();
        let p3 = IccProfile {
            color_space: *b"RGB ",
            description: None,
            matrix: Some(m),
            curves: Some(srgb_curve),
        };
        let conv = ToSrgb::new(&p3).unwrap();
        // P3 white stays white; pure P3 red is out of sRGB gamut and clips.
        let w = conv.convert([1.0, 1.0, 1.0]);
        assert!(w.iter().all(|&v| (v - 1.0).abs() < 2e-3), "{w:?}");
        let r = conv.convert([1.0, 0.0, 0.0]);
        assert!(r[0] > 0.99 && r[1] < 0.05 && r[2] < 0.05, "{r:?}");
        // A mid P3 grey is neutral in sRGB.
        let g = conv.convert([0.5, 0.5, 0.5]);
        assert!((g[0] - g[1]).abs() < 2e-3 && (g[1] - g[2]).abs() < 2e-3);
    }

    #[test]
    fn curves_evaluate_and_invert() {
        let curves = [
            Curve::Gamma(2.2),
            Curve::Table((0..256).map(|i| (i as f32 / 255.0).powf(1.8)).collect()),
            Curve::Parametric(3, [2.4, 1.0 / 1.055, 0.055 / 1.055, 1.0 / 12.92, 0.040_45, 0.0, 0.0]),
        ];
        for c in &curves {
            for i in 1..20 {
                let x = i as f32 / 20.0;
                assert!((c.inverse(c.eval(x)) - x).abs() < 1e-3, "{c:?} at {x}");
            }
        }
        // The parametric type-3 curve above is the sRGB curve.
        assert!((curves[2].eval(0.5) - srgb_to_linear(0.5)).abs() < 1e-4);
    }

    #[test]
    fn malformed_profiles_are_rejected() {
        assert!(IccProfile::parse(b"short").is_err());
        let mut p = srgb_profile();
        p[128..132].copy_from_slice(&50u32.to_be_bytes()); // tag count beyond the table
        assert!(IccProfile::parse(&p).is_err());
        let mut p = srgb_profile();
        let bad_off = (p.len() as u32 + 10).to_be_bytes();
        p[136..140].copy_from_slice(&bad_off);
        assert!(IccProfile::parse(&p).is_err());
    }
}
