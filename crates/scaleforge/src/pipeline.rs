//! The processing pipeline and public entry points.
//!
//! Input → validation → decode → orientation → analysis → strategy →
//! restoration → enlargement (classical and/or model, tiled) → consistency
//! → sharpening/tone → quality control → export profile → encode → output.

use std::collections::HashMap;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use sf_analysis::AnalysisReport;
use sf_compute::cpu::{CpuBackend, CpuConfig};
use sf_compute::{Device, Precision};
use sf_core::{
    CancelToken, DeviceErrorKind, Error, ErrorKind, Limits, ProgressEvent, ProgressSink, Result, Size,
};
use sf_graph::Shape;
use sf_image::color::{IccProfile, ToSrgb, TransferClass, srgb_profile};
use sf_image::png::{PngSink, PngSource};
use sf_image::resample::{Filter, resize};
use sf_image::stream::{MemorySource, RowSink, RowSource, SourceInfo};
use sf_image::{FileFormat, Image, SampleFormat, jpeg, png, tiff};

use crate::export::{Compliance, ExportRules};
use crate::hostmem::HostBudget;
use crate::imageops::Pixels;
use crate::qc::{self, QcAccumulator, QcReport};
use crate::runtime::{ModelHandle, ResidentModel};
use crate::strategy::{self, Controls, Decision, Mode, Plan, Source, UpscalePath};
use crate::tiling::{self, Planar, TileGeometry, TileMode};
use crate::vram::VramManager;

/// Engine configuration.
#[derive(Debug, Clone)]
pub struct EngineConfig {
    /// Parser and allocation limits.
    pub limits: Limits,
    /// CPU worker threads.
    pub threads: usize,
    /// Host memory budget in bytes (`None`: half of physical memory).
    pub host_budget: Option<u64>,
}

impl Default for EngineConfig {
    fn default() -> Self {
        EngineConfig {
            limits: Limits::default(),
            threads: std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1),
            host_budget: None,
        }
    }
}

/// Export profiles.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportProfile {
    /// Adobe Stock photo submission rules (ADR-0016).
    AdobeStock,
}

/// A processing job.
#[derive(Debug, Clone)]
pub struct JobRequest {
    /// Input file.
    pub input: PathBuf,
    /// Output file; the format follows the extension (png, jpg/jpeg, tif/tiff).
    pub output: PathBuf,
    /// Scale 1/2/4/8; `None` = 1, or the profile's choice.
    pub scale: Option<u32>,
    /// Reconstruction mode.
    pub mode: Mode,
    /// Optional model file (`.sfm`).
    pub model: Option<PathBuf>,
    /// User controls.
    pub controls: Controls,
    /// Export profile.
    pub export: Option<ExportProfile>,
    /// Replace an existing output file.
    pub overwrite: bool,
    /// JPEG quality when not set by a profile.
    pub jpeg_quality: Option<u8>,
    /// Tile core size for model inference (`None` = choose from memory).
    pub tile: Option<u32>,
    /// Process in bands of rows even when the whole image fits in memory.
    /// Banding is chosen automatically when it does not fit.
    pub stream: bool,
    /// Input rows per band (`None` = choose from the memory budget).
    pub band_rows: Option<u32>,
}

impl JobRequest {
    /// A request with defaults: Faithful, scale 1, no model.
    pub fn new(input: impl Into<PathBuf>, output: impl Into<PathBuf>) -> JobRequest {
        JobRequest {
            input: input.into(),
            output: output.into(),
            scale: None,
            mode: Mode::Faithful,
            model: None,
            controls: Controls::default(),
            export: None,
            overwrite: false,
            jpeg_quality: None,
            tile: None,
            stream: false,
            band_rows: None,
        }
    }
}

/// Everything a job did and why.
#[derive(Debug, Clone)]
pub struct JobReport {
    /// Input path.
    pub input: PathBuf,
    /// Output path.
    pub output: PathBuf,
    /// Input size after orientation.
    pub input_size: (u32, u32),
    /// Output size.
    pub output_size: (u32, u32),
    /// Output bytes.
    pub output_bytes: u64,
    /// Analysis of the input.
    pub analysis: AnalysisReport,
    /// Decisions with provenance.
    pub decisions: Vec<Decision>,
    /// Quality control.
    pub qc: QcReport,
    /// Export compliance, when a profile was used.
    pub compliance: Option<Compliance>,
    /// Stage timings in milliseconds.
    pub timings_ms: Vec<(&'static str, f64)>,
    /// Peak tracked device memory in bytes.
    pub peak_device_bytes: u64,
    /// Model used, if any: (name, provenance, licence scope).
    pub model: Option<(String, String, String)>,
    /// Warnings.
    pub warnings: Vec<String>,
}

type CachedModel = Arc<(ModelHandle, ResidentModel)>;

/// The ScaleForge engine. Create once; run many jobs.
pub struct Engine {
    config: EngineConfig,
    vram: VramManager,
    host: HostBudget,
    models: Mutex<HashMap<PathBuf, CachedModel>>,
}

fn format_for(path: &Path) -> Result<FileFormat> {
    let ext = path.extension().and_then(|e| e.to_str()).map(str::to_ascii_lowercase).unwrap_or_default();
    match ext.as_str() {
        "png" => Ok(FileFormat::Png),
        "jpg" | "jpeg" => Ok(FileFormat::Jpeg),
        "tif" | "tiff" => Ok(FileFormat::Tiff),
        "webp" => Err(Error::unsupported("WebP output is INCOMPLETE (no own WebP encoder yet)")),
        other => Err(Error::unsupported(format!("unknown output extension {other:?} (use png, jpg or tif)"))),
    }
}

impl Engine {
    /// Creates an engine on the CPU backend. (GPU backends are INCOMPLETE:
    /// they will be selected here once validated on hardware.)
    pub fn new(config: EngineConfig) -> Result<Engine> {
        config.limits.validate()?;
        let host = match config.host_budget {
            Some(b) => HostBudget::new(b),
            None => HostBudget::from_system(0.5, 4 << 30),
        };
        let device: Arc<dyn Device> = CpuBackend::new(CpuConfig {
            threads: config.threads.max(1),
            strict: false,
            memory_limit: Some(host.limit()),
        })
        .device()?;
        let vram = VramManager::new(device, None, 0);
        Ok(Engine { config, vram, host, models: Mutex::new(HashMap::new()) })
    }

    /// Engine configuration.
    pub fn config(&self) -> &EngineConfig {
        &self.config
    }

    /// Description of the compute device in use.
    pub fn device_info(&self) -> sf_compute::DeviceInfo {
        self.vram.device().info()
    }

    /// Decodes and analyses an image without processing it.
    pub fn analyze(&self, path: &Path) -> Result<(Image, AnalysisReport)> {
        let img = self.decode(path)?;
        let report = sf_analysis::analyze(&img);
        Ok((img, report))
    }

    fn decode(&self, path: &Path) -> Result<Image> {
        let len = std::fs::metadata(path).map_err(|e| Error::from(e).context(path.display()))?.len();
        if len > self.config.limits.max_decoded_bytes {
            return Err(Error::limit_exceeded(format!("{} is larger than the decode limit", path.display())));
        }
        let data = std::fs::read(path).map_err(|e| Error::from(e).context(path.display()))?;
        sf_image::decode_any(&data, &self.config.limits).map_err(|e| e.context(path.display()))
    }

    fn model(&self, path: &Path) -> Result<CachedModel> {
        let key = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
        if let Some(m) = self.models.lock().expect("model cache").get(&key) {
            return Ok(Arc::clone(m));
        }
        let handle = ModelHandle::load(path, &self.config.limits)?;
        let resident = handle.upload(&self.vram)?;
        let m = Arc::new((handle, resident));
        self.models.lock().expect("model cache").insert(key, Arc::clone(&m));
        Ok(m)
    }

    /// Runs one job.
    pub fn run(
        &self,
        req: &JobRequest,
        progress: &dyn ProgressSink,
        cancel: &CancelToken,
    ) -> Result<JobReport> {
        let started = Instant::now();
        let mut timings: Vec<(&'static str, f64)> = Vec::new();
        let mut stage = |name: &'static str, t: &mut Instant| {
            timings.push((name, t.elapsed().as_secs_f64() * 1e3));
            *t = Instant::now();
        };
        let mut t = Instant::now();
        let mut warnings: Vec<String> = Vec::new();

        // Validation of the request and output policy.
        let out_format = format_for(&req.output)?;
        if req.export == Some(ExportProfile::AdobeStock) && out_format != FileFormat::Jpeg {
            return Err(Error::invalid_input("the Adobe Stock profile requires a .jpg output"));
        }
        if !req.overwrite && req.output.exists() {
            return Err(Error::invalid_input(format!(
                "{} exists (use overwrite to replace it)",
                req.output.display()
            )));
        }
        if req.input.canonicalize().ok() == req.output.canonicalize().ok() && req.output.exists() {
            return Err(Error::invalid_input("input and output are the same file"));
        }
        let rules = match req.export {
            Some(ExportProfile::AdobeStock) => Some(ExportRules::adobe_stock()?),
            None => None,
        };

        // Decode (or open for band-by-band reading) and analyse.
        let mut input = self.open_input(&req.input)?;
        let (analysis, info, region_note) = match &mut input {
            Input::Decoded(image) => {
                let info = oriented_info(image);
                stage("decode", &mut t);
                cancel.check()?;
                (sf_analysis::analyze(image), info, None)
            }
            Input::Bands(src) => {
                let (region, note) = analysis_region(src.as_mut())?;
                stage("decode", &mut t);
                cancel.check()?;
                (sf_analysis::analyze(&region), src.info().clone(), Some(note))
            }
        };
        let source_format = info.sample;
        let (w, h) = (info.width as usize, info.height as usize);
        let channels = info.channels as usize;
        stage("analysis", &mut t);
        progress.report(&ProgressEvent { stage: "analysis", completed: 1, total: 1 });

        // Model and licence gate.
        let model = match &req.model {
            Some(p) => Some(self.model(p)?),
            None => None,
        };
        if let (Some(r), Some(m)) = (&rules, &model)
            && r.blocked_licence_scopes.contains(&m.0.info.licence_scope)
        {
            return Err(Error::invalid_input(format!(
                "model {} is licensed for {} use only and cannot be used for {} exports",
                m.0.info.name, m.0.info.licence_scope, r.id
            )));
        }

        // Scale.
        let mut profile_decisions = Vec::new();
        let (scale, final_size) = match (req.scale, &rules) {
            (Some(s), _) => (s, None),
            (None, Some(r)) => {
                let (s, down) = r.choose_scale(w as u32, h as u32);
                let best = (w * h) as f64 * f64::from(s * s) / 1e6;
                if best < r.min_megapixels {
                    return Err(Error::invalid_input(format!(
                        "{w}x{h} is too small for {}: even x{s} gives {best:.2} MP, below the {} MP minimum",
                        r.id, r.min_megapixels
                    )));
                }
                profile_decisions.push(Decision {
                    parameter: "scale",
                    value: format!("x{s}"),
                    source: Source::Profile,
                    rule: "profile-min-megapixels",
                    evidence: format!("{w}x{h} input, minimum {} MP", r.min_megapixels),
                });
                (s, down)
            }
            (None, None) => (1, None),
        };
        if ![1, 2, 4, 8].contains(&scale) {
            return Err(Error::unsupported(format!("scale {scale} (supported: 1, 2, 4, 8)")));
        }
        let (out_w, out_h) = (w * scale as usize, h * scale as usize);

        let mut plan =
            strategy::plan(&analysis, req.mode, scale, &req.controls, model.as_ref().map(|m| &m.0.info));
        plan.decisions.extend(profile_decisions);
        if let Some(note) = &region_note {
            plan.decisions.push(Decision {
                parameter: "analysis",
                value: note.clone(),
                source: Source::Auto,
                rule: "image-larger-than-memory",
                evidence: format!("{w}x{h} input"),
            });
        }
        stage("strategy", &mut t);

        // Whole image in memory, or band by band.
        let working = (out_w * out_h * channels) as u64 * 4 * 4 + (w * h * channels) as u64 * 4 * 4;
        let reservation = match (&input, req.stream) {
            (Input::Decoded(_), false) => match self.host.reserve(working, "image processing") {
                Ok(r) => Some(r),
                Err(e) if e.kind() == ErrorKind::LimitExceeded => None,
                Err(e) => return Err(e),
            },
            _ => None,
        };
        let Some(_reservation) = reservation else {
            let why = if req.stream {
                "requested".to_string()
            } else {
                format!(
                    "the whole image needs {} MB, the memory budget is {} MB",
                    working >> 20,
                    self.host.limit() >> 20
                )
            };
            let blocker = if rules.is_some() {
                Some("export profiles")
            } else if !matches!(plan.upscale, UpscalePath::Classical(_)) {
                Some("AI models")
            } else if !matches!(out_format, FileFormat::Png | FileFormat::Tiff) {
                Some("this output format (use .png or .tif)")
            } else {
                None
            };
            if let Some(b) = blocker {
                return Err(Error::limit_exceeded(format!(
                    "band-by-band processing ({why}) does not support {b} yet (INCOMPLETE)"
                )));
            }
            let source: Box<dyn RowSource> = match input {
                Input::Decoded(image) => Box::new(MemorySource::new(image)),
                Input::Bands(src) => src,
            };
            return self.run_banded(
                req,
                source,
                BandJob {
                    scale,
                    plan,
                    analysis,
                    out_format,
                    why,
                    timings,
                    warnings,
                    started: t,
                    progress,
                    cancel,
                },
            );
        };
        let Input::Decoded(image) = input else { unreachable!("band sources are processed above") };
        let pixels = Pixels::from_buffer(&image.buffer).oriented(image.meta.orientation.unwrap_or(1));

        // Restoration and enlargement of colour.
        let (colour, alpha) = pixels.split_alpha();
        let mut lr = colour.clone();
        restore(&mut lr, &plan);
        stage("restore", &mut t);
        cancel.check()?;
        let classical = enlarge(&lr, scale);
        let mut tiling_note =
            "no tiling (classical processing is local and runs on the whole image)".to_string();
        let upscale_path = plan.upscale.clone();
        let mut hr = match &upscale_path {
            UpscalePath::Classical(_) => classical,
            UpscalePath::Model { weight, post } => {
                let m = model.as_ref().expect("plan uses a model");
                let (mhr, note) = self.run_model(m, &colour, req.tile, &mut plan, progress, cancel)?;
                tiling_note = note;
                let target = if (*post - 1.0).abs() < 1e-6 {
                    mhr
                } else if *post < 1.0 {
                    Pixels {
                        width: out_w,
                        height: out_h,
                        channels: mhr.channels,
                        data: resize(
                            &mhr.data,
                            mhr.width,
                            mhr.height,
                            mhr.channels,
                            out_w,
                            out_h,
                            Filter::Lanczos3,
                        ),
                    }
                } else {
                    let f = post.round() as usize;
                    Pixels {
                        width: out_w,
                        height: out_h,
                        channels: mhr.channels,
                        data: sf_classic::upscale(&mhr.data, mhr.width, mhr.height, mhr.channels, f),
                    }
                };
                let mut blended = classical;
                for (b, m) in blended.data.iter_mut().zip(&target.data) {
                    *b += weight * (m - *b);
                }
                blended
            }
        };
        stage("enlarge", &mut t);
        cancel.check()?;
        finish_colour(&lr, &mut hr, &plan);
        let qc_report = qc::check(&lr, &hr, req.mode, &tiling_note);
        if !qc_report.passed() {
            warnings.push("quality control flagged the output; see the qc section".into());
        }
        stage("postprocess", &mut t);
        // Alpha.
        let mut out = match alpha {
            Some(a) => {
                let a_hr = if scale > 1 { sf_classic::upscale(&a, w, h, 1, scale as usize) } else { a };
                hr.with_alpha(&a_hr.iter().map(|v| v.clamp(0.0, 1.0)).collect::<Vec<_>>())
            }
            None => hr.clone(),
        };

        // Export profile adjustments.
        let mut icc = image.meta.icc_profile.clone();
        if rules.is_some() {
            out = self.to_srgb_rgb(out, icc.as_deref(), &mut plan.decisions)?;
            icc = Some(srgb_profile());
            if let Some((fw, fh)) = final_size {
                out = Pixels {
                    width: fw as usize,
                    height: fh as usize,
                    channels: out.channels,
                    data: resize(
                        &out.data,
                        out.width,
                        out.height,
                        out.channels,
                        fw as usize,
                        fh as usize,
                        Filter::Lanczos3,
                    ),
                };
                plan.decisions.push(Decision {
                    parameter: "final_size",
                    value: format!("{fw}x{fh}"),
                    source: Source::Profile,
                    rule: "profile-max-megapixels",
                    evidence: String::new(),
                });
            }
        }
        if out_format == FileFormat::Jpeg && out.channels % 2 == 0 {
            out = flatten_on_white(&out);
            plan.decisions.push(Decision {
                parameter: "alpha",
                value: "flattened on white".into(),
                source: Source::Default,
                rule: "jpeg-has-no-alpha",
                evidence: String::new(),
            });
        }

        // Encode.
        let (bytes, quality) = self.encode(&out, out_format, source_format, icc, req, rules.as_ref())?;
        stage("encode", &mut t);
        write_atomically(&req.output, &bytes, req.overwrite)?;
        stage("write", &mut t);

        // Compliance.
        let compliance = rules.as_ref().map(|r| {
            let mp = (out.width * out.height) as f64 / 1e6;
            let embedded_srgb = jpeg::decode(&bytes, &self.config.limits)
                .ok()
                .and_then(|i| i.meta.icc_profile)
                .and_then(|p| IccProfile::parse(&p).ok())
                .is_some_and(|p| p.transfer() == TransferClass::SrgbLike);
            let rules_out = vec![
                ("format jpeg".to_string(), true, String::new()),
                ("embedded sRGB profile".into(), embedded_srgb, String::new()),
                ("megapixels".into(), mp >= r.min_megapixels && mp <= r.max_megapixels, format!("{mp:.2} MP (allowed {}–{})", r.min_megapixels, r.max_megapixels)),
                ("file size".into(), (bytes.len() as u64) <= r.max_file_bytes, format!("{} bytes (max {})", bytes.len(), r.max_file_bytes)),
                ("jpeg quality floor".into(), quality >= r.jpeg_quality_floor, format!("quality {quality}")),
                ("quality control".into(), qc_report.passed(), "see qc".into()),
            ];
            let mut warn = Vec::new();
            if scale > 1 {
                warn.push(format!(
                    "the image was enlarged x{scale}; Adobe asks contributors not to enlarge files in a way that degrades quality, and enlarged images may be rejected"
                ));
            }
            let ai = match (&plan.upscale, &model) {
                (UpscalePath::Model { weight, .. }, Some(m)) => format!(
                    "An external AI model ({}, {}) reconstructed detail at weight {weight:.2}. If this changed, augmented or added primary subject content, Adobe requires the 'Created using generative AI tools' label. The decision is yours.",
                    m.0.info.name, m.0.info.architecture
                ),
                _ => "No generative AI model was used (classical processing only).".into(),
            };
            Compliance::finish(format!("{} v{}", r.id, r.version), rules_out, warn, ai)
        });
        let _ = started;
        Ok(JobReport {
            input: req.input.clone(),
            output: req.output.clone(),
            input_size: (w as u32, h as u32),
            output_size: (out.width as u32, out.height as u32),
            output_bytes: bytes.len() as u64,
            analysis,
            decisions: plan.decisions,
            qc: qc_report,
            compliance,
            timings_ms: timings,
            peak_device_bytes: self.vram.usage().peak_total,
            model: model.as_ref().map(|m| {
                (m.0.info.name.clone(), m.0.info.provenance.clone(), m.0.info.licence_scope.clone())
            }),
            warnings,
        })
    }

    /// Opens the input: a PNG whose decoded pixels would take more than a
    /// quarter of the memory budget is read band by band; everything else
    /// is decoded whole.
    fn open_input(&self, path: &Path) -> Result<Input> {
        let mut head = [0u8; 8];
        let is_png = std::fs::File::open(path).and_then(|mut f| f.read_exact(&mut head)).is_ok()
            && head == png::SIGNATURE;
        if is_png
            && let Ok(src) = PngSource::open(path, &self.config.limits)
            && src.info().decoded_bytes() > self.host.limit() / 4
            && src.info().meta.orientation.unwrap_or(1) <= 1
        {
            return Ok(Input::Bands(Box::new(src)));
        }
        Ok(Input::Decoded(self.decode(path)?))
    }

    /// Processes an image band by band (ARCHITECTURE §8.1): each band of
    /// input rows is processed with margins of `BAND_MARGIN` rows, which
    /// every classical stage needs less than, and only its own rows are
    /// written. The output is therefore the same as whole-image processing
    /// (checked by tests), while memory holds one band.
    fn run_banded(
        &self,
        req: &JobRequest,
        mut src: Box<dyn RowSource>,
        job: BandJob<'_>,
    ) -> Result<JobReport> {
        let BandJob {
            scale,
            mut plan,
            analysis,
            out_format,
            why,
            mut timings,
            mut warnings,
            started,
            progress,
            cancel,
        } = job;
        let mut t = started;
        let mut stage = |name: &'static str, t: &mut Instant| {
            timings.push((name, t.elapsed().as_secs_f64() * 1e3));
            *t = Instant::now();
        };
        let info = src.info().clone();
        let (w, h, c, s) = (info.width, info.height, info.channels as usize, scale as usize);
        let (ow, oh) = (w as usize * s, h as usize * s);
        // Memory per input row: about 6 input-sized f32 copies (window,
        // crop, restoration temporaries) and 5 enlarged ones (enlargement,
        // consistency, sharpening, output conversion).
        let lr_row = u64::from(w) * c as u64 * 4;
        let (lr_cost, hr_cost) = (6 * lr_row, 5 * lr_row * (s * s) as u64);
        let margins = 2 * u64::from(BAND_MARGIN) * lr_cost + 2 * u64::from(ENLARGE_MARGIN) * hr_cost;
        let fixed = src.resident_bytes() + margins;
        let band = match req.band_rows {
            Some(b) => b.max(8) / 8 * 8,
            None => {
                let available = self.host.limit().saturating_sub(self.host.used()) / 5 * 4;
                let fit = available.saturating_sub(fixed) / (lr_cost + hr_cost).max(1);
                (fit.min(2048) as u32) / 8 * 8
            }
        };
        if band < 8 {
            return Err(Error::limit_exceeded(format!(
                "a {w} px wide image does not fit the memory budget of {} MB even in bands of 8 rows",
                self.host.limit() >> 20
            )));
        }
        let _reservation =
            self.host.reserve(u64::from(band) * (lr_cost + hr_cost) + fixed, "band processing")?;
        plan.decisions.push(Decision {
            parameter: "processing",
            value: format!("band by band: {band} input rows per band ({BAND_MARGIN}-row restoration and {ENLARGE_MARGIN}-row enlargement margins)"),
            source: if req.stream || req.band_rows.is_some() { Source::User } else { Source::Auto },
            rule: "whole-image-exceeds-memory",
            evidence: why,
        });
        let out_sample = match (out_format, info.sample) {
            (FileFormat::Png, SampleFormat::U8) => SampleFormat::U8,
            (FileFormat::Png, _) => SampleFormat::U16,
            (_, sample) => sample,
        };
        let icc = info.meta.icc_profile.clone();
        let tmp = temp_path(&req.output)?;
        let result = (|| -> Result<QcAccumulator> {
            let file = std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&tmp)
                .map_err(|e| Error::from(e).context(tmp.display()))?;
            let out = std::io::BufWriter::with_capacity(1 << 20, file);
            let (ow32, oh32) = (ow as u32, oh as u32);
            let mut sink: Box<dyn RowSink> = match out_format {
                FileFormat::Png => Box::new(PngSink::new(
                    out,
                    ow32,
                    oh32,
                    c as u8,
                    out_sample,
                    &png::EncodeOptions { icc_profile: icc.clone(), ..png::EncodeOptions::default() },
                )?),
                _ => Box::new(tiff::TiffSink::new(
                    out,
                    ow32,
                    oh32,
                    c as u8,
                    out_sample,
                    &tiff::EncodeOptions { icc_profile: icc.clone(), ..tiff::EncodeOptions::default() },
                )?),
            };
            let row_len = w as usize * c;
            let mut window: Vec<f32> = Vec::new();
            let (mut win_y0, mut win_rows) = (0u32, 0u32);
            let mut qc_acc = QcAccumulator::default();
            let total = u64::from(h.div_ceil(band));
            for (k, y0) in (0..h).step_by(band as usize).enumerate() {
                cancel.check()?;
                let y1 = (y0 + band).min(h);
                // Margins are multiples of 8, so every band starts on the
                // 8-pixel JPEG grid, as deblocking requires.
                let (a, b) = (y0.saturating_sub(BAND_MARGIN), (y1 + BAND_MARGIN).min(h));
                if a > win_y0 {
                    window.drain(..(a - win_y0) as usize * row_len);
                    win_rows -= a - win_y0;
                    win_y0 = a;
                }
                while win_y0 + win_rows < b {
                    let rows = src.read_rows(b - win_y0 - win_rows)?;
                    win_rows += rows.height();
                    window.extend(rows.to_f32());
                }
                let crop = Pixels {
                    width: w as usize,
                    height: (b - a) as usize,
                    channels: c,
                    data: window[..(b - a) as usize * row_len].to_vec(),
                };
                let (colour, alpha) = crop.split_alpha();
                let mut restored = colour;
                restore(&mut restored, &plan);
                // Only the band and a narrower margin are enlarged.
                let (ea, eb) = (y0.saturating_sub(ENLARGE_MARGIN), (y1 + ENLARGE_MARGIN).min(h));
                let rows_of = |p: &[f32], ch: usize| {
                    p[(ea - a) as usize * w as usize * ch..(eb - a) as usize * w as usize * ch].to_vec()
                };
                let lr = Pixels {
                    width: w as usize,
                    height: (eb - ea) as usize,
                    channels: restored.channels,
                    data: rows_of(&restored.data, restored.channels),
                };
                let alpha = alpha.map(|al| rows_of(&al, 1));
                let mut hr = enlarge(&lr, scale);
                finish_colour(&lr, &mut hr, &plan);
                let core = (y0 - ea) as usize..(y1 - ea) as usize;
                qc_acc.add(&lr, &hr, core.clone());
                let hr_rows = core.start * s * ow * hr.channels..core.end * s * ow * hr.channels;
                let hr_core = Pixels {
                    width: ow,
                    height: core.len() * s,
                    channels: hr.channels,
                    data: hr.data[hr_rows].to_vec(),
                };
                let band_out = match alpha {
                    Some(al) => {
                        let a_hr = if s > 1 {
                            sf_classic::upscale(&al, w as usize, (eb - ea) as usize, 1, s)
                        } else {
                            al
                        };
                        let a_core: Vec<f32> = a_hr[core.start * s * ow..core.end * s * ow]
                            .iter()
                            .map(|v| v.clamp(0.0, 1.0))
                            .collect();
                        hr_core.with_alpha(&a_core)
                    }
                    None => hr_core,
                };
                sink.write_rows(&band_out.to_buffer(out_sample)?)?;
                progress.report(&ProgressEvent { stage: "bands", completed: k as u64 + 1, total });
            }
            sink.finish()?;
            Ok(qc_acc)
        })();
        let qc_acc = match result {
            Ok(q) => q,
            Err(e) => {
                let _ = std::fs::remove_file(&tmp);
                return Err(e);
            }
        };
        stage("process", &mut t);
        commit(&tmp, &req.output, req.overwrite)?;
        stage("write", &mut t);
        let qc_report = qc_acc.report(
            req.mode,
            &format!(
                "banded processing ({band} rows per band): every stage is local and the margins exceed its reach, so the output equals whole-image processing"
            ),
        );
        if !qc_report.passed() {
            warnings.push("quality control flagged the output; see the qc section".into());
        }
        Ok(JobReport {
            input: req.input.clone(),
            output: req.output.clone(),
            input_size: (w, h),
            output_size: (ow as u32, oh as u32),
            output_bytes: std::fs::metadata(&req.output).map(|m| m.len()).unwrap_or(0),
            analysis,
            decisions: plan.decisions,
            qc: qc_report,
            compliance: None,
            timings_ms: timings,
            peak_device_bytes: self.vram.usage().peak_total,
            model: None,
            warnings,
        })
    }
    /// Runs a model over the colour image, tiled, with out-of-memory
    /// recovery. Returns the model output and a tiling note.
    fn run_model(
        &self,
        m: &CachedModel,
        colour: &Pixels,
        tile: Option<u32>,
        plan: &mut Plan,
        progress: &dyn ProgressSink,
        cancel: &CancelToken,
    ) -> Result<(Pixels, String)> {
        let (handle, resident) = (&m.0, &m.1);
        let graph = &handle.file.graph;
        let model_channels = match graph.inputs.first().map(|i| i.kind) {
            Some(sf_graph::InputKind::Spatial { channels, .. }) => channels as usize,
            _ => return Err(Error::model_invalid("the model's first input is not an image")),
        };
        // Grey images are replicated to RGB for RGB models.
        let rgb = if colour.channels == 1 && model_channels == 3 {
            Pixels {
                width: colour.width,
                height: colour.height,
                channels: 3,
                data: colour.data.iter().flat_map(|&v| [v, v, v]).collect(),
            }
        } else if colour.channels == model_channels {
            colour.clone()
        } else {
            return Err(Error::unsupported(format!(
                "model expects {model_channels} channels, image has {}",
                colour.channels
            )));
        };
        let radius = handle.locality.max_halo();
        let (mode, note) = if radius <= 64 {
            (
                TileMode::Exact,
                format!("exact tiling (halo {radius} px = receptive radius): seam-free by construction"),
            )
        } else {
            (
                TileMode::Blended { halo: 16 },
                format!(
                    "bounded-error tiling (halo 16 px < receptive radius {radius} px, cross-faded); deviation from a whole-image run was not measured for this model"
                ),
            )
        };
        let geom =
            TileGeometry { halo: radius, alignment: handle.locality.alignment, scale: handle.info.scale };
        let size = Size::new(rgb.width as u32, rgb.height as u32);
        let canon = tiling::canonical_size(size, geom.alignment)?;
        let planar = Planar { channels: 3, width: rgb.width, height: rgb.height, data: rgb.to_planar() };
        let input = planar.pad_reflect(canon);
        let candidates: Vec<u32> = match tile {
            Some(t) => vec![t.max(16)],
            None => vec![512, 384, 256, 192, 128, 96, 64, 48, 32],
        };
        let mut last_err = None;
        for core in candidates {
            let p = tiling::plan(canon, Size::new(core, core), geom, mode)?;
            let shape = Shape::Spatial { n: 1, c: 3, h: p.window.height, w: p.window.width };
            let need = self.vram.device().memory_requirement(graph, &[shape], Precision::F32)?;
            let io = (u64::from(p.window.width) * u64::from(p.window.height) * 3 * 4)
                * (1 + u64::from(geom.scale).pow(2));
            // Leave room for the host-side images: at most a quarter of the budget.
            if tile.is_none() && need.arena_bytes + io > self.host.limit() / 4 {
                continue;
            }
            match tiling::run_tiled(
                &self.vram,
                graph,
                &resident.buffers(),
                &[resident.ready()],
                &[],
                &input,
                &p,
                cancel,
                progress,
            ) {
                Ok(out) => {
                    plan.decisions.push(Decision {
                        parameter: "tile",
                        value: format!(
                            "{core} px core, {} px window, {} tiles",
                            p.window.width,
                            p.tiles.len()
                        ),
                        source: if tile.is_some() { Source::User } else { Source::Auto },
                        rule: "largest-tile-within-memory-plan",
                        evidence: format!("activation arena {} MB", need.arena_bytes >> 20),
                    });
                    let s = geom.scale as usize;
                    let (ow, oh) = (rgb.width * s, rgb.height * s);
                    let cropped =
                        Planar { channels: 3, width: out.width, height: out.height, data: out.data }
                            .crop(sf_core::Rect::new(0, 0, ow as u32, oh as u32).expect("inside"));
                    let mut px = Pixels::from_planar(&cropped.data, ow, oh, 3);
                    if colour.channels == 1 {
                        px = Pixels {
                            width: ow,
                            height: oh,
                            channels: 1,
                            data: px.data.chunks(3).map(|c| (c[0] + c[1] + c[2]) / 3.0).collect(),
                        };
                    }
                    return Ok((px, note));
                }
                Err(e) if e.kind() == ErrorKind::Device(DeviceErrorKind::OutOfMemory) => {
                    last_err = Some(e);
                    continue;
                }
                Err(e) => return Err(e),
            }
        }
        Err(last_err.unwrap_or_else(|| Error::limit_exceeded("no tile size fits the memory budget")))
    }

    fn to_srgb_rgb(&self, p: Pixels, icc: Option<&[u8]>, decisions: &mut Vec<Decision>) -> Result<Pixels> {
        let (colour, alpha) = p.split_alpha();
        let mut rgb = if colour.channels == 1 {
            decisions.push(Decision {
                parameter: "channels",
                value: "grey expanded to RGB".into(),
                source: Source::Profile,
                rule: "profile-srgb-rgb",
                evidence: String::new(),
            });
            Pixels {
                width: colour.width,
                height: colour.height,
                channels: 3,
                data: colour.data.iter().flat_map(|&v| [v, v, v]).collect(),
            }
        } else {
            colour
        };
        if let Some(bytes) = icc {
            let profile = IccProfile::parse(bytes)?;
            let identity = profile.transfer() == TransferClass::SrgbLike
                && ToSrgb::new(&profile).is_ok_and(|c| {
                    [[1.0f32, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
                        .iter()
                        .all(|&v| c.convert(v).iter().zip(v).all(|(a, b)| (a - b).abs() < 0.01))
                });
            if !identity {
                let conv = ToSrgb::new(&profile)
                    .map_err(|e| e.context("converting to sRGB for the export profile"))?;
                for px in rgb.data.chunks_mut(3) {
                    let o = conv.convert([px[0], px[1], px[2]]);
                    px.copy_from_slice(&o);
                }
                decisions.push(Decision {
                    parameter: "colour",
                    value: "converted to sRGB".into(),
                    source: Source::Profile,
                    rule: "profile-srgb",
                    evidence: format!("embedded profile {:?}", profile.description),
                });
            }
        }
        Ok(match alpha {
            Some(a) => rgb.with_alpha(&a),
            None => rgb,
        })
    }

    fn encode(
        &self,
        out: &Pixels,
        format: FileFormat,
        source: SampleFormat,
        icc: Option<Vec<u8>>,
        req: &JobRequest,
        rules: Option<&ExportRules>,
    ) -> Result<(Vec<u8>, u8)> {
        match format {
            FileFormat::WebP => {
                Err(Error::unsupported("WebP output is INCOMPLETE (no own WebP encoder yet)"))
            }
            FileFormat::Png => {
                let fmt = if source == SampleFormat::U8 { SampleFormat::U8 } else { SampleFormat::U16 };
                let buf = out.to_buffer(fmt)?;
                Ok((
                    png::encode(
                        &buf,
                        &png::EncodeOptions { icc_profile: icc, ..png::EncodeOptions::default() },
                    )?,
                    100,
                ))
            }
            FileFormat::Tiff => {
                let buf = out.to_buffer(source)?;
                Ok((
                    tiff::encode(
                        &buf,
                        &tiff::EncodeOptions { icc_profile: icc, ..tiff::EncodeOptions::default() },
                    )?,
                    100,
                ))
            }
            FileFormat::Jpeg => {
                let buf = out.to_buffer(SampleFormat::U8)?;
                let enc = |q: u8| {
                    jpeg::encode(
                        &buf,
                        &jpeg::EncodeOptions {
                            quality: q,
                            subsampling: jpeg::Subsampling::S444,
                            icc_profile: icc.clone(),
                        },
                    )
                };
                match rules {
                    Some(r) => {
                        let mut q = r.jpeg_quality_start;
                        loop {
                            let data = enc(q)?;
                            if data.len() as u64 <= r.max_file_bytes || q <= r.jpeg_quality_floor {
                                return Ok((data, q));
                            }
                            q -= 1;
                        }
                    }
                    None => {
                        let q = req.jpeg_quality.unwrap_or(95).clamp(1, 100);
                        Ok((enc(q)?, q))
                    }
                }
            }
        }
    }
}

fn flatten_on_white(p: &Pixels) -> Pixels {
    let c = p.channels - 1;
    let data = p.data.chunks(p.channels).flat_map(|px| {
        let a = px[c];
        (0..c).map(move |i| px[i] * a + (1.0 - a)).collect::<Vec<_>>()
    });
    Pixels { width: p.width, height: p.height, channels: c, data: data.collect() }
}

/// A temporary file name next to `path`.
fn temp_path(path: &Path) -> Result<PathBuf> {
    let dir = path.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
    let name = path.file_name().ok_or_else(|| Error::invalid_input("output path has no file name"))?;
    Ok(dir.join(format!(".{}.sf-tmp-{}", name.to_string_lossy(), std::process::id())))
}

/// Writes via a temporary file in the same directory, then renames, so a
/// failure never leaves a truncated output. Without `overwrite`, an
/// existing target is never replaced.
fn write_atomically(path: &Path, bytes: &[u8], overwrite: bool) -> Result<()> {
    use std::io::Write;
    let tmp = temp_path(path)?;
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tmp)
        .map_err(|e| Error::from(e).context(tmp.display()))?;
    let result = f.write_all(bytes);
    drop(f);
    if let Err(e) = result {
        let _ = std::fs::remove_file(&tmp);
        return Err(Error::from(e).context(path.display()));
    }
    commit(&tmp, path, overwrite)
}

/// Flushes a completed temporary file to disk and renames it to `path`.
fn commit(tmp: &Path, path: &Path, overwrite: bool) -> Result<()> {
    let synced = std::fs::OpenOptions::new().write(true).open(tmp).and_then(|f| f.sync_all());
    if let Err(e) = synced {
        let _ = std::fs::remove_file(tmp);
        return Err(Error::from(e).context(path.display()));
    }
    if !overwrite && path.exists() {
        let _ = std::fs::remove_file(tmp);
        return Err(Error::invalid_input(format!(
            "{} appeared during processing; not overwritten",
            path.display()
        )));
    }
    std::fs::rename(tmp, path).map_err(|e| {
        let _ = std::fs::remove_file(tmp);
        Error::from(e).context(path.display())
    })
}

/// Input rows restored around each band. Restoration reaches 33 rows
/// (denoising 30, deblocking 3); the rows then enlarged lie at least
/// `BAND_MARGIN - ENLARGE_MARGIN` = 40 rows inside, so they are exactly
/// the whole-image values. A multiple of 8 keeps bands on the 8-pixel JPEG
/// grid.
const BAND_MARGIN: u32 = 64;

/// Input rows enlarged around each band. The enlargement and finishing
/// stages reach about 12 input rows (enlargement 4, consistency 7,
/// sharpening 1–4, and the QC low-pass 4 more).
const ENLARGE_MARGIN: u32 = 24;

/// The decoded input, or a source read band by band.
enum Input {
    Decoded(Image),
    Bands(Box<dyn RowSource>),
}

/// What `run` hands to `run_banded`.
struct BandJob<'a> {
    scale: u32,
    plan: Plan,
    analysis: AnalysisReport,
    out_format: FileFormat,
    why: String,
    timings: Vec<(&'static str, f64)>,
    warnings: Vec<String>,
    started: Instant,
    progress: &'a dyn ProgressSink,
    cancel: &'a CancelToken,
}

/// Size and format of a decoded image after its EXIF orientation.
fn oriented_info(image: &Image) -> SourceInfo {
    let (w, h) = (image.buffer.width(), image.buffer.height());
    let swap = image.meta.orientation.is_some_and(|o| (5..=8).contains(&o));
    SourceInfo {
        width: if swap { h } else { w },
        height: if swap { w } else { h },
        channels: image.buffer.channels(),
        sample: image.buffer.format(),
        meta: image.meta.clone(),
        format: image.format,
    }
}

/// For an image read band by band: a contiguous region of up to
/// 2048×2048 native pixels at the centre, for the analysis. One pass over
/// the source, which is then rewound.
///
/// A mosaic of patches from the whole image was tried first and rejected:
/// the seams between patches lie on the 8-pixel grid and read as JPEG
/// block edges (blockiness 7.6 instead of 1.2 on a real photo), which
/// switched deblocking on wrongly. A single region has no seams; it does
/// not see the rest of the image, which the report states.
fn analysis_region(src: &mut dyn RowSource) -> Result<(Image, String)> {
    const SIDE: u32 = 2048;
    let info = src.info().clone();
    let (w, h, c) = (info.width, info.height, info.channels as usize);
    let (rw, rh) = (w.min(SIDE), h.min(SIDE));
    // Origin on the 8-pixel grid so JPEG block statistics are unaffected.
    let (ox, oy) = ((w - rw) / 2 / 8 * 8, (h - rh) / 2 / 8 * 8);
    let mut region = Vec::with_capacity(rw as usize * rh as usize * c);
    let mut y = 0u32;
    while y < oy + rh {
        let band = src.read_rows(256.min(oy + rh - y))?;
        let px = band.to_f32();
        for r in 0..band.height() {
            if (oy..oy + rh).contains(&(y + r)) {
                let at = (r as usize * w as usize + ox as usize) * c;
                region.extend_from_slice(&px[at..at + rw as usize * c]);
            }
        }
        y += band.height();
    }
    src.rewind()?;
    let pixels = Pixels { width: rw as usize, height: rh as usize, channels: c, data: region };
    let buffer = pixels.to_buffer(info.sample)?;
    let note = if (rw, rh) == (w, h) {
        "whole image".to_string()
    } else {
        format!("{rw}x{rh} region at the centre only (the image does not fit in memory)")
    };
    Ok((Image { buffer, meta: info.meta, format: info.format }, note))
}
/// Restoration of the input colour: denoising, then deblocking.
fn restore(lr: &mut Pixels, plan: &Plan) {
    let (w, h, c) = (lr.width, lr.height, lr.channels);
    if let Some((sigma, strength)) = plan.denoise {
        sf_classic::denoise(&mut lr.data, w, h, c, sigma, strength);
    }
    if let Some(step) = plan.deblock {
        sf_classic::deblock(&mut lr.data, w, h, c, step, 0);
    }
}

/// Classical enlargement by an integer scale.
fn enlarge(lr: &Pixels, scale: u32) -> Pixels {
    if scale <= 1 {
        return lr.clone();
    }
    let s = scale as usize;
    Pixels {
        width: lr.width * s,
        height: lr.height * s,
        channels: lr.channels,
        data: sf_classic::upscale(&lr.data, lr.width, lr.height, lr.channels, s),
    }
}

/// Consistency correction, sharpening, tone and the final clamp.
fn finish_colour(lr: &Pixels, hr: &mut Pixels, plan: &Plan) {
    qc::consistency_correct(lr, hr, plan.consistency);
    if plan.sharpen > 0.0 {
        sf_classic::sharpen(&mut hr.data, hr.width, hr.height, hr.channels, plan.sharpen, 1.0, 2.0 / 255.0);
    }
    if let Some(tone) = plan.tone {
        sf_classic::tone(&mut hr.data, hr.channels, tone);
    }
    hr.data.iter_mut().for_each(|v| *v = v.clamp(0.0, 1.0));
}
