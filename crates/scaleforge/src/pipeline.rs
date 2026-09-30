//! The processing pipeline and public entry points.
//!
//! Input → validation → decode → orientation → analysis → strategy →
//! restoration → enlargement (classical and/or model, tiled) → consistency
//! → sharpening/tone → quality control → export profile → encode → output.

use std::collections::HashMap;
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
use sf_image::resample::{Filter, resize};
use sf_image::{FileFormat, Image, SampleFormat, jpeg, png, tiff};

use crate::export::{Compliance, ExportRules};
use crate::hostmem::HostBudget;
use crate::imageops::Pixels;
use crate::qc::{self, QcReport};
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

        // Decode and orient.
        let image = self.decode(&req.input)?;
        let source_format = image.buffer.format();
        let pixels = Pixels::from_buffer(&image.buffer).oriented(image.meta.orientation.unwrap_or(1));
        let (w, h) = (pixels.width, pixels.height);
        stage("decode", &mut t);
        cancel.check()?;

        // Analysis.
        let analysis = sf_analysis::analyze(&image);
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
        let working =
            (out_w * out_h * pixels.channels) as u64 * 4 * 4 + (w * h * pixels.channels) as u64 * 4 * 4;
        let _reservation = self.host.reserve(working, "image processing")?;

        let mut plan =
            strategy::plan(&analysis, req.mode, scale, &req.controls, model.as_ref().map(|m| &m.0.info));
        plan.decisions.extend(profile_decisions);
        stage("strategy", &mut t);

        // Restoration and enlargement of colour.
        let (colour, alpha) = pixels.split_alpha();
        let mut lr = colour.clone();
        if let Some((sigma, strength)) = plan.denoise {
            sf_classic::denoise(&mut lr.data, w, h, lr.channels, sigma, strength);
        }
        if let Some(step) = plan.deblock {
            sf_classic::deblock(&mut lr.data, w, h, lr.channels, step, 0);
        }
        stage("restore", &mut t);
        cancel.check()?;
        let classical = if scale > 1 {
            Pixels {
                width: out_w,
                height: out_h,
                channels: lr.channels,
                data: sf_classic::upscale(&lr.data, w, h, lr.channels, scale as usize),
            }
        } else {
            lr.clone()
        };
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
        qc::consistency_correct(&lr, &mut hr, plan.consistency);
        if plan.sharpen > 0.0 {
            sf_classic::sharpen(&mut hr.data, out_w, out_h, hr.channels, plan.sharpen, 1.0, 2.0 / 255.0);
        }
        if let Some(tone) = plan.tone {
            sf_classic::tone(&mut hr.data, hr.channels, tone);
        }
        hr.data.iter_mut().for_each(|v| *v = v.clamp(0.0, 1.0));
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

/// Writes via a temporary file in the same directory, then renames, so a
/// failure never leaves a truncated output. Without `overwrite`, an
/// existing target is never replaced.
fn write_atomically(path: &Path, bytes: &[u8], overwrite: bool) -> Result<()> {
    use std::io::Write;
    let dir = path.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
    let name = path.file_name().ok_or_else(|| Error::invalid_input("output path has no file name"))?;
    let tmp = dir.join(format!(".{}.sf-tmp-{}", name.to_string_lossy(), std::process::id()));
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tmp)
        .map_err(|e| Error::from(e).context(tmp.display()))?;
    let result = f.write_all(bytes).and_then(|_| f.sync_all());
    drop(f);
    if let Err(e) = result {
        let _ = std::fs::remove_file(&tmp);
        return Err(Error::from(e).context(path.display()));
    }
    if !overwrite && path.exists() {
        let _ = std::fs::remove_file(&tmp);
        return Err(Error::invalid_input(format!(
            "{} appeared during processing; not overwritten",
            path.display()
        )));
    }
    std::fs::rename(&tmp, path).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        Error::from(e).context(path.display())
    })
}
