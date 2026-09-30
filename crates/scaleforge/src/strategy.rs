//! The strategy engine: turns analysis results and user controls into a
//! processing plan, recording **why** every parameter has its value
//! (ADR-0013).
//!
//! Thresholds belong to policy version 1. They are provisional starting
//! points, to be calibrated on evaluation data and replaced by measured
//! values; each decision names the rule that produced it.

use sf_analysis::AnalysisReport;

use crate::runtime::ModelInfo;

/// Version of the decision rules.
pub const POLICY_VERSION: &str = "policy/1 (provisional thresholds)";

/// Reconstruction philosophy (ADR-0014).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Mode {
    /// Only what the source supports: classical restoration, strict
    /// consistency, no generative model.
    Faithful,
    /// Controlled reconstruction: half-strength model contribution (when a
    /// model is given), strict consistency.
    Balanced,
    /// Stronger learned reconstruction with a user strength in `[0, 1]`;
    /// consistency limited to colour and large structure.
    Reconstruction {
        /// Model contribution strength.
        strength: f32,
    },
}

impl Mode {
    /// Stable name.
    pub fn name(&self) -> &'static str {
        match self {
            Mode::Faithful => "faithful",
            Mode::Balanced => "balanced",
            Mode::Reconstruction { .. } => "reconstruction",
        }
    }
}

/// User controls. `None` means "decide automatically".
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Controls {
    /// Denoise strength multiplier (0 disables).
    pub denoise: Option<f32>,
    /// Deblocking on/off.
    pub deblock: Option<bool>,
    /// Sharpening amount 0–1.
    pub sharpen: Option<f32>,
    /// Automatic white balance, exposure and contrast correction.
    pub auto_tone: bool,
}

/// Where a decision came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    /// Set by the user.
    User,
    /// Chosen by a policy rule from analysis evidence.
    Auto,
    /// Fixed by an export profile.
    Profile,
    /// A documented default.
    Default,
}

impl Source {
    /// Stable name.
    pub fn name(self) -> &'static str {
        match self {
            Source::User => "user",
            Source::Auto => "auto",
            Source::Profile => "profile",
            Source::Default => "default",
        }
    }
}

/// One explained decision.
#[derive(Debug, Clone, PartialEq)]
pub struct Decision {
    /// Parameter name.
    pub parameter: &'static str,
    /// Chosen value, as text.
    pub value: String,
    /// Origin.
    pub source: Source,
    /// Rule identifier.
    pub rule: &'static str,
    /// Evidence used.
    pub evidence: String,
}

/// How the enlargement is produced.
#[derive(Debug, Clone, PartialEq)]
pub enum UpscalePath {
    /// Classical Lanczos with anti-ringing, by the given factor.
    Classical(u32),
    /// Model at its native scale, blended with the classical result by
    /// `weight`, then resampled by `post` (e.g. 0.5 for a ×4 model used for
    /// ×2, 2.0 for ×8 from a ×4 model).
    Model {
        /// Contribution of the model output (0–1).
        weight: f32,
        /// Classical resampling factor applied after the model.
        post: f32,
    },
}

/// The processing plan.
#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    /// Overall scale factor.
    pub scale: u32,
    /// Noise sigma (0–1 units) and strength for classical denoising, if any.
    pub denoise: Option<(f32, f32)>,
    /// Deblocking step (0–1 units), if any.
    pub deblock: Option<f32>,
    /// Upscaling path.
    pub upscale: UpscalePath,
    /// Consistency correction weight (0 disables).
    pub consistency: f32,
    /// Sharpening amount (0 disables).
    pub sharpen: f32,
    /// Tone correction, if any.
    pub tone: Option<sf_classic::Tone>,
    /// Explanations.
    pub decisions: Vec<Decision>,
}

/// Builds a plan.
pub fn plan(
    a: &AnalysisReport,
    mode: Mode,
    scale: u32,
    controls: &Controls,
    model: Option<&ModelInfo>,
) -> Plan {
    let mut d: Vec<Decision> = Vec::new();
    let mut log = |parameter, value: String, source, rule, evidence: String| {
        d.push(Decision { parameter, value, source, rule, evidence });
    };
    log("policy", POLICY_VERSION.into(), Source::Default, "policy-version", String::new());
    log("mode", mode.name().into(), Source::User, "user-mode", String::new());

    // Model use.
    let use_model = match (mode, model) {
        (_, None) => None,
        (Mode::Faithful, Some(m)) => {
            log(
                "model",
                "not used".into(),
                Source::Auto,
                "faithful-excludes-generative",
                format!("Faithful mode does not use generative models ({} is {})", m.name, m.provenance),
            );
            None
        }
        (Mode::Balanced, Some(m)) => Some((m, 0.5f32)),
        (Mode::Reconstruction { strength }, Some(m)) => Some((m, strength.clamp(0.0, 1.0))),
    };
    let upscale = match use_model {
        Some((m, weight)) => {
            let post = scale as f32 / m.scale as f32;
            log(
                "upscale",
                format!("model {} (x{}) weight {weight:.2}, then x{post}", m.name, m.scale),
                if matches!(mode, Mode::Reconstruction { .. }) { Source::User } else { Source::Auto },
                if matches!(mode, Mode::Balanced) {
                    "balanced-half-strength"
                } else {
                    "reconstruction-user-strength"
                },
                format!("requested x{scale}"),
            );
            UpscalePath::Model { weight, post }
        }
        None => {
            log(
                "upscale",
                format!("classical x{scale}"),
                Source::Auto,
                "classical-path",
                "no model in use".into(),
            );
            UpscalePath::Classical(scale)
        }
    };
    let model_path = matches!(upscale, UpscalePath::Model { .. });

    // Denoising: classical path only; learned models handle noise themselves.
    let sigma = a.noise_sigma.value;
    let denoise = match controls.denoise {
        Some(s) if s <= 0.0 => {
            log("denoise", "off".into(), Source::User, "user-disabled", String::new());
            None
        }
        _ if model_path && controls.denoise.is_none() => {
            log("denoise", "off".into(), Source::Auto, "model-handles-noise", format!("sigma {sigma:.2}"));
            None
        }
        user => {
            let mode_strength = match mode {
                Mode::Faithful => 0.8,
                Mode::Balanced => 1.0,
                Mode::Reconstruction { .. } => 1.1,
            };
            let strength = mode_strength * user.unwrap_or(1.0);
            if sigma >= 1.0 || user.is_some() {
                log(
                    "denoise",
                    format!("sigma {:.2}/255, strength {strength:.2}", sigma),
                    if user.is_some() { Source::User } else { Source::Auto },
                    "noise-above-1-level",
                    format!("estimated noise sigma {sigma:.2} ({})", a.noise_sigma.estimator),
                );
                Some(((sigma.max(0.5) / 255.0) as f32, strength))
            } else {
                log(
                    "denoise",
                    "off".into(),
                    Source::Auto,
                    "noise-below-1-level",
                    format!("sigma {sigma:.2}"),
                );
                None
            }
        }
    };

    // Deblocking.
    let jpeg_q = a.jpeg_quality.as_ref().map(|m| m.value);
    let blocky = a.blockiness.value;
    let deblock = match controls.deblock {
        Some(false) => {
            log("deblock", "off".into(), Source::User, "user-disabled", String::new());
            None
        }
        _ if model_path && controls.deblock.is_none() => {
            log(
                "deblock",
                "off".into(),
                Source::Auto,
                "model-handles-compression",
                format!("blockiness {blocky:.2}"),
            );
            None
        }
        user => {
            let evidence = jpeg_q.is_some_and(|q| q <= 90.0) || blocky >= 1.25;
            if evidence || user == Some(true) {
                // Step ~ quantisation of low frequencies: stronger at low quality.
                let q = jpeg_q.unwrap_or(75.0);
                let step = ((100.0 - q).max(5.0) / 100.0 * 0.12) as f32;
                log(
                    "deblock",
                    format!("step {step:.3}"),
                    if user.is_some() { Source::User } else { Source::Auto },
                    "jpeg-evidence",
                    format!(
                        "JPEG quality {}, blockiness {blocky:.2}",
                        jpeg_q.map_or("unknown".to_string(), |q| format!("{q:.0}"))
                    ),
                );
                Some(step)
            } else {
                log(
                    "deblock",
                    "off".into(),
                    Source::Auto,
                    "no-compression-evidence",
                    format!("blockiness {blocky:.2}"),
                );
                None
            }
        }
    };

    // Consistency with the source (ADR-0014).
    let consistency = match mode {
        Mode::Faithful | Mode::Balanced => 1.0,
        Mode::Reconstruction { .. } => 0.5,
    };
    log("consistency", format!("{consistency}"), Source::Auto, "mode-consistency", mode.name().into());

    // Sharpening.
    let sharpen = match controls.sharpen {
        Some(s) => {
            log("sharpen", format!("{s:.2}"), Source::User, "user-set", String::new());
            s.clamp(0.0, 1.0)
        }
        None => {
            let (v, rule) = match (mode, model_path) {
                (_, true) => (0.0, "model-output-not-sharpened"),
                (Mode::Faithful, _) => (0.0, "faithful-no-sharpening"),
                (Mode::Balanced, _) if scale > 1 => (0.35, "balanced-classical-upscale"),
                (Mode::Reconstruction { strength }, _) if scale > 1 => {
                    (0.6 * strength, "reconstruction-classical-upscale")
                }
                _ => (0.0, "no-enlargement"),
            };
            log("sharpen", format!("{v:.2}"), Source::Auto, rule, String::new());
            v
        }
    };

    // Tone.
    let tone = if controls.auto_tone {
        let mut t = sf_classic::Tone::default();
        let mut evidence = Vec::new();
        if let Some((rg, bg)) = a.color_balance {
            // Correct 70 % of the measured grey-world deviation.
            t.white_balance = ((1.0 / rg).powf(0.7) as f32, (1.0 / bg).powf(0.7) as f32);
            evidence.push(format!("grey-world R/G {rg:.3} B/G {bg:.3}"));
        }
        if a.exposure.p99 < 180.0 && a.exposure.clipped_bright < 0.001 {
            let gain = (235.0 / a.exposure.p99.max(1.0)).min(2.0);
            // Encoded-value ratio → linear-light gain (sRGB-like curve ≈ 2.2).
            t.exposure = gain.powf(2.2).min(4.0) as f32;
            evidence.push(format!("p99 {:.0}", a.exposure.p99));
        }
        if a.contrast < 0.12 {
            t.contrast = 0.3;
            evidence.push(format!("RMS contrast {:.3}", a.contrast));
        }
        log("tone", format!("{t:?}"), Source::User, "auto-tone-requested", evidence.join(", "));
        Some(t)
    } else {
        log("tone", "off".into(), Source::Default, "tone-off-unless-requested", String::new());
        None
    };

    Plan { scale, denoise, deblock, upscale, consistency, sharpen, tone, decisions: d }
}
