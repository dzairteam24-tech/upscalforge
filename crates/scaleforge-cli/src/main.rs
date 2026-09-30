//! The `scaleforge` command-line interface: a thin client of the engine
//! API. All processing lives in the `scaleforge` crate.

mod args;
mod bench;

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use args::{Args, Spec};
use scaleforge::{Controls, Engine, EngineConfig, ExportProfile, JobRequest, Mode, report};
use sf_core::{CancelToken, DeviceErrorKind, Error, ErrorKind, Limits, ProgressEvent, ProgressSink, Result};

const HELP: &str = "\
ScaleForge — image restoration and upscaling

USAGE:
  scaleforge <command> [arguments] [options]

COMMANDS:
  upscale <input> -o <output>     Process one image
  batch <input-dir> -o <out-dir>  Process every image in a folder
  analyze <input> [--json]        Measure an image without processing it
  models [dir]                    List models (default dir: ./models)
  convert-model <in.pth> -o <out.sfm> [--name N]
                                  Import external Real-ESRGAN weights (ADR-0015)
  devices                         Show compute devices
  doctor                          Check the installation and run self-tests
  benchmark [--size WxH] [--scale N] [--repeat N] [--model M] [--json F]
                                  Measure performance on a synthetic image
  help                            Show this help

PROCESSING OPTIONS (upscale, batch):
  --scale 1|2|4|8          Enlargement (default 1, or chosen by --export)
  --mode faithful|balanced|reconstruction   (default faithful)
  --strength 0..1          Model strength in reconstruction mode (default 1)
  --model FILE.sfm         Use a model (not used in faithful mode)
  --denoise X              Denoise strength multiplier (0 disables)
  --deblock / --no-deblock Force JPEG deblocking on or off
  --sharpen X              Sharpening amount 0..1
  --auto-tone              Automatic white balance, exposure and contrast
  --export adobe-stock     Apply the Adobe Stock photo rules (JPEG output)
  --quality Q              JPEG quality (default 95)
  --tile N                 Tile size for model inference
  --stream                 Process in bands of rows (automatic when the image
                           does not fit in memory; classical path, PNG/TIFF output)
  --band-rows N            Input rows per band (default: from the memory budget)
  --memory MB              Host memory budget (default: half of physical memory
                           where the OS reports it; otherwise 4096)
  --overwrite              Replace existing outputs
  --report FILE.json       Write the job report (upscale)
  --ext png|jpg|tif        Output format for batch (default: same as input)
  --fail-fast              Stop a batch at the first error

EXIT CODES: 0 ok, 2 invalid input, 3 unsupported, 4 limit exceeded, 5 I/O,
6 invalid model, 7 device error, 8 batch had failures, 9 export profile not met,
70 internal error, 130 cancelled.
";

const PROCESS: Spec = &[
    ("output", true),
    ("scale", true),
    ("mode", true),
    ("strength", true),
    ("model", true),
    ("denoise", true),
    ("deblock", false),
    ("no-deblock", false),
    ("sharpen", true),
    ("auto-tone", false),
    ("export", true),
    ("quality", true),
    ("tile", true),
    ("stream", false),
    ("band-rows", true),
    ("memory", true),
    ("overwrite", false),
    ("report", true),
    ("ext", true),
    ("fail-fast", false),
];

fn exit_code(e: &Error) -> i32 {
    match e.kind() {
        ErrorKind::InvalidInput => 2,
        ErrorKind::Unsupported => 3,
        ErrorKind::LimitExceeded => 4,
        ErrorKind::Io => 5,
        ErrorKind::ModelInvalid => 6,
        ErrorKind::Device(DeviceErrorKind::OutOfMemory | DeviceErrorKind::Lost | DeviceErrorKind::Other) => 7,
        ErrorKind::Cancelled => 130,
        ErrorKind::Internal => 70,
    }
}

/// Prints tile progress in 10 % steps.
struct Progress(AtomicU64);

impl ProgressSink for Progress {
    fn report(&self, e: &ProgressEvent) {
        if !matches!(e.stage, "tiles" | "bands") || e.total < 2 {
            return;
        }
        let pct = e.completed * 100 / e.total;
        let step = pct / 10;
        if self.0.swap(step, Ordering::Relaxed) != step {
            eprintln!("  {}: {}/{} ({pct}%)", e.stage, e.completed, e.total);
        }
    }
}

fn request(a: &Args, input: PathBuf, output: PathBuf) -> Result<JobRequest> {
    let mut r = JobRequest::new(input, output);
    r.scale = a.number::<u32>("scale")?;
    let strength = a.number::<f32>("strength")?.unwrap_or(1.0);
    if !(0.0..=1.0).contains(&strength) {
        return Err(Error::invalid_input("--strength must be between 0 and 1"));
    }
    r.mode = match a.value("mode").unwrap_or("faithful") {
        "faithful" => Mode::Faithful,
        "balanced" => Mode::Balanced,
        "reconstruction" => Mode::Reconstruction { strength },
        other => {
            return Err(Error::invalid_input(format!(
                "--mode {other:?} (use faithful, balanced or reconstruction)"
            )));
        }
    };
    r.model = a.value("model").map(PathBuf::from);
    r.controls = Controls {
        denoise: a.number::<f32>("denoise")?,
        deblock: match (a.has("deblock"), a.has("no-deblock")) {
            (true, true) => return Err(Error::invalid_input("--deblock and --no-deblock are exclusive")),
            (true, false) => Some(true),
            (false, true) => Some(false),
            _ => None,
        },
        sharpen: a.number::<f32>("sharpen")?,
        auto_tone: a.has("auto-tone"),
    };
    r.export = match a.value("export") {
        None => None,
        Some("adobe-stock") => Some(ExportProfile::AdobeStock),
        Some(other) => {
            return Err(Error::invalid_input(format!("--export {other:?} (available: adobe-stock)")));
        }
    };
    r.overwrite = a.has("overwrite");
    r.jpeg_quality = a.number::<u8>("quality")?;
    r.tile = a.number::<u32>("tile")?;
    r.stream = a.has("stream");
    r.band_rows = a.number::<u32>("band-rows")?;
    Ok(r)
}

fn print_report(rep: &scaleforge::JobReport) {
    println!("{} -> {}", rep.input.display(), rep.output.display());
    println!(
        "  {}x{} -> {}x{}, {} bytes",
        rep.input_size.0, rep.input_size.1, rep.output_size.0, rep.output_size.1, rep.output_bytes
    );
    for d in &rep.decisions {
        if d.parameter == "policy" {
            continue;
        }
        let ev = if d.evidence.is_empty() { String::new() } else { format!(" — {}", d.evidence) };
        println!("  {:<12} {:<40} [{} · {}]{ev}", d.parameter, d.value, d.source.name(), d.rule);
    }
    println!("  QC: {}", if rep.qc.passed() { "passed" } else { "FLAGGED" });
    for c in &rep.qc.checks {
        println!(
            "    {:<16} {:.4} (limit {}) {}",
            c.name,
            c.value,
            c.limit,
            if c.pass { "ok" } else { "FAIL" }
        );
    }
    if let Some(c) = &rep.compliance {
        println!("  Export {}: {}", c.profile, c.verdict.to_uppercase());
        for (rule, ok, detail) in &c.rules {
            println!("    [{}] {rule} {detail}", if *ok { "ok" } else { "FAIL" });
        }
        for w in &c.warnings {
            println!("    warning: {w}");
        }
        println!("    AI disclosure: {}", c.ai_disclosure);
    }
    for w in &rep.warnings {
        println!("  warning: {w}");
    }
    let total: f64 = rep.timings_ms.iter().map(|t| t.1).sum();
    println!("  time: {:.0} ms", total);
}

fn engine() -> Result<Engine> {
    Engine::new(EngineConfig::default())
}

/// The engine for processing commands: `--memory MB` sets the host memory
/// budget (default: half of physical memory where it can be read, else 4 GiB).
fn processing_engine(a: &Args) -> Result<Engine> {
    let host_budget = a.number::<u64>("memory")?.map(|mb| mb << 20);
    if host_budget == Some(0) {
        return Err(Error::invalid_input("--memory must be greater than zero"));
    }
    Engine::new(EngineConfig { host_budget, ..EngineConfig::default() })
}

fn cmd_upscale(raw: &[String]) -> Result<()> {
    let a = Args::parse(raw, PROCESS)?;
    let [input] = a.positional.as_slice() else {
        return Err(Error::invalid_input("upscale needs exactly one input file"));
    };
    let output = a.value("output").ok_or_else(|| Error::invalid_input("-o <output> is required"))?;
    let req = request(&a, input.into(), output.into())?;
    let rep = processing_engine(&a)?.run(&req, &Progress(AtomicU64::new(u64::MAX)), &CancelToken::new())?;
    print_report(&rep);
    if let Some(p) = a.value("report") {
        std::fs::write(p, sf_core::json::to_string_pretty(&report::job_json(&rep))?)?;
    }
    if rep.compliance.as_ref().is_some_and(|c| c.verdict == "fail") {
        eprintln!("error: the output does not comply with the export profile (see above)");
        std::process::exit(9);
    }
    Ok(())
}

fn is_image(p: &Path) -> bool {
    matches!(
        p.extension().and_then(|e| e.to_str()).map(str::to_ascii_lowercase).as_deref(),
        Some("png" | "jpg" | "jpeg" | "tif" | "tiff" | "webp")
    )
}

fn cmd_batch(raw: &[String]) -> Result<()> {
    let a = Args::parse(raw, PROCESS)?;
    let [input] = a.positional.as_slice() else {
        return Err(Error::invalid_input("batch needs one input directory"));
    };
    let out_dir =
        PathBuf::from(a.value("output").ok_or_else(|| Error::invalid_input("-o <out-dir> is required"))?);
    std::fs::create_dir_all(&out_dir)?;
    let out_dir = out_dir.canonicalize()?;
    let mut files: Vec<PathBuf> =
        std::fs::read_dir(input)?.filter_map(|e| e.ok()).map(|e| e.path()).collect();
    files.sort();
    let engine = processing_engine(&a)?;
    let (mut ok, mut failed, mut skipped) = (0, 0, 0);
    for f in files {
        // Symlinks are skipped so a batch cannot be redirected elsewhere.
        let Ok(meta) = std::fs::symlink_metadata(&f) else { continue };
        if meta.file_type().is_symlink() || !meta.is_file() || !is_image(&f) {
            skipped += 1;
            continue;
        }
        // Output names are derived from the input's own file name only, so
        // outputs stay inside the output directory.
        let stem = f.file_stem().and_then(|s| s.to_str()).unwrap_or("image");
        let ext = match a.value("ext") {
            Some(e) => e.to_string(),
            None if a.value("export").is_some() => "jpg".into(),
            // WebP can be read but not yet written: such outputs become PNG.
            None => match f.extension().and_then(|e| e.to_str()).map(str::to_ascii_lowercase) {
                Some(e) if e != "webp" => e,
                _ => "png".into(),
            },
        };
        let out = out_dir.join(format!("{stem}.{ext}"));
        if out.parent() != Some(out_dir.as_path()) {
            skipped += 1;
            continue;
        }
        let result = request(&a, f.clone(), out)
            .and_then(|r| engine.run(&r, &Progress(AtomicU64::new(u64::MAX)), &CancelToken::new()));
        match result {
            Ok(rep) => {
                ok += 1;
                let verdict =
                    rep.compliance.as_ref().map(|c| format!(", export {}", c.verdict)).unwrap_or_default();
                println!("ok    {} ({}x{}{verdict})", f.display(), rep.output_size.0, rep.output_size.1);
            }
            Err(e) => {
                failed += 1;
                println!("FAIL  {}: {e}", f.display());
                if a.has("fail-fast") {
                    return Err(e);
                }
            }
        }
    }
    println!("{ok} processed, {failed} failed, {skipped} skipped");
    if failed > 0 {
        std::process::exit(8);
    }
    Ok(())
}

fn cmd_analyze(raw: &[String]) -> Result<()> {
    let a = Args::parse(raw, &[("json", false)])?;
    let [input] = a.positional.as_slice() else {
        return Err(Error::invalid_input("analyze needs one input file"));
    };
    let (img, r) = engine()?.analyze(Path::new(input))?;
    if a.has("json") {
        println!("{}", sf_core::json::to_string_pretty(&report::analysis_json(&r))?);
        return Ok(());
    }
    println!("{input}: {:?}, {}x{}, {} channel(s)", img.format, r.width, r.height, img.buffer.channels());
    println!("  noise sigma      {:.2} levels ({})", r.noise_sigma.value, r.noise_sigma.estimator);
    if let Some(q) = &r.jpeg_quality {
        println!("  JPEG quality     ~{:.0} (from the file's quantisation tables)", q.value);
    }
    println!("  blockiness       {:.2} (1 = none)", r.blockiness.value);
    match &r.edge_width {
        Some(e) => println!("  edge width       {:.2} px (10-90 % rise)", e.value),
        None => println!("  edge width       not enough edges"),
    }
    println!(
        "  exposure         p1 {:.0}, median {:.0}, p99 {:.0}; clipped {:.2}% dark, {:.2}% bright",
        r.exposure.p1,
        r.exposure.p50,
        r.exposure.p99,
        100.0 * r.exposure.clipped_dark,
        100.0 * r.exposure.clipped_bright
    );
    println!("  contrast (RMS)   {:.3}", r.contrast);
    if let Some((rg, bg)) = r.color_balance {
        println!("  colour balance   R/G {rg:.3}, B/G {bg:.3} (1 = neutral)");
    }
    println!("  texture density  {:.2}", r.texture_density);
    println!(
        "  colour profile   {}",
        img.meta
            .icc_profile
            .as_ref()
            .map_or("none embedded".to_string(), |p| format!("{} bytes embedded", p.len()))
    );
    for (q, why) in &r.unavailable {
        println!("  {q:<16} unavailable: {why}");
    }
    Ok(())
}

fn cmd_models(raw: &[String]) -> Result<()> {
    let a = Args::parse(raw, &[])?;
    let dir = a.positional.first().map_or("models", String::as_str);
    let entries = scaleforge::runtime::scan(Path::new(dir), &Limits::default())?;
    if entries.is_empty() {
        println!("no .sfm models in {dir}");
    }
    for e in entries {
        match e.info {
            Ok(i) => println!(
                "{}  {} x{} [{}] provenance={} licence={} ({})",
                e.path.display(),
                i.name,
                i.scale,
                i.architecture,
                i.provenance,
                i.licence,
                i.licence_scope
            ),
            Err(why) => println!("{}  INVALID: {why}", e.path.display()),
        }
    }
    Ok(())
}

fn cmd_convert(raw: &[String]) -> Result<()> {
    let a = Args::parse(raw, &[("output", true), ("name", true), ("overwrite", false)])?;
    let [input] = a.positional.as_slice() else {
        return Err(Error::invalid_input("convert-model needs one .pth file"));
    };
    let out =
        PathBuf::from(a.value("output").ok_or_else(|| Error::invalid_input("-o <out.sfm> is required"))?);
    if out.exists() && !a.has("overwrite") {
        return Err(Error::invalid_input(format!("{} exists (use --overwrite)", out.display())));
    }
    let limits = Limits::default();
    let bytes = std::fs::read(input)?;
    let name = a.value("name").map(str::to_string).unwrap_or_else(|| {
        Path::new(input).file_stem().and_then(|s| s.to_str()).unwrap_or("model").to_string()
    });
    let imp = sf_import::import_pth(&bytes, &name, &limits)?;
    std::fs::write(&out, sf_graph::sfm::write(&imp.model)?)?;
    let loc = sf_graph::locality(&imp.model.graph)?;
    println!(
        "{} -> {}: {} x{}, {} parameters, receptive radius {} px (external model, see ADR-0015)",
        input,
        out.display(),
        imp.architecture,
        imp.scale,
        imp.model.weights.iter().map(Vec::len).sum::<usize>(),
        loc.max_halo()
    );
    Ok(())
}

fn cmd_devices() -> Result<()> {
    let e = engine()?;
    let d = e.device_info();
    println!("{} [{}] memory budget {:?} bytes, fp16: {}", d.name, d.backend, d.total_memory, d.supports_f16);
    println!("CUDA backend:   INCOMPLETE (not implemented yet; needs NVIDIA hardware to validate)");
    println!("Vulkan backend: INCOMPLETE (not implemented yet; needs GPU hardware to validate)");
    Ok(())
}

fn cmd_doctor() -> Result<()> {
    let mut failures = 0;
    let mut check = |name: &str, r: Result<String>| match r {
        Ok(detail) => println!("[ok]   {name}: {detail}"),
        Err(e) => {
            failures += 1;
            println!("[FAIL] {name}: {e}");
        }
    };
    check("limits", Limits::default().validate().map(|_| "valid".into()));
    check("engine", engine().map(|e| e.device_info().name));
    check("sha256", {
        let h = sf_core::sha256::sha256_hex(b"abc");
        if h == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" {
            Ok("FIPS vector ok".into())
        } else {
            Err(Error::internal("wrong digest"))
        }
    });
    check("png round trip", {
        let b = sf_image::ImageBuffer::new(3, 2, 3, sf_image::Samples::U8((0..18).collect())).unwrap();
        sf_image::png::encode(&b, &Default::default())
            .and_then(|d| sf_image::png::decode(&d, &Limits::default()))
            .and_then(|i| if i.buffer == b { Ok("exact".into()) } else { Err(Error::internal("mismatch")) })
    });
    check(
        "adobe stock rules",
        scaleforge::export::ExportRules::adobe_stock().map(|r| format!("{} v{}", r.id, r.version)),
    );
    check("end-to-end", {
        let dir = std::env::temp_dir().join(format!("scaleforge-doctor-{}", std::process::id()));
        let r = (|| -> Result<String> {
            std::fs::create_dir_all(&dir)?;
            let b = sf_image::ImageBuffer::new(
                32,
                24,
                3,
                sf_image::Samples::U8((0..32 * 24 * 3).map(|i| (i % 251) as u8).collect()),
            )?;
            std::fs::write(dir.join("in.png"), sf_image::png::encode(&b, &Default::default())?)?;
            let mut req = JobRequest::new(dir.join("in.png"), dir.join("out.png"));
            req.scale = Some(2);
            let rep = engine()?.run(&req, &sf_core::NoProgress, &CancelToken::new())?;
            Ok(format!("classical x2 produced {}x{}", rep.output_size.0, rep.output_size.1))
        })();
        let _ = std::fs::remove_dir_all(&dir);
        r
    });
    println!("[info] GPU backends (CUDA, Vulkan): INCOMPLETE");
    println!("[info] own trained ScaleForge model: INCOMPLETE (training not implemented; see training/)");
    if failures > 0 {
        return Err(Error::internal(format!("{failures} check(s) failed")));
    }
    Ok(())
}

fn main() {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let (cmd, rest) = match argv.split_first() {
        Some((c, r)) => (c.as_str(), r),
        None => ("help", &[][..]),
    };
    let result = match cmd {
        "upscale" => cmd_upscale(rest),
        "batch" => cmd_batch(rest),
        "analyze" => cmd_analyze(rest),
        "models" => cmd_models(rest),
        "convert-model" => cmd_convert(rest),
        "devices" => cmd_devices(),
        "doctor" => cmd_doctor(),
        "benchmark" => bench::run(rest),
        "help" | "--help" | "-h" => {
            print!("{HELP}");
            Ok(())
        }
        "version" | "--version" => {
            println!("scaleforge {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        other => Err(Error::invalid_input(format!("unknown command {other:?}; see `scaleforge help`"))),
    };
    if let Err(e) = result {
        eprintln!("error: {e}");
        std::process::exit(exit_code(&e));
    }
}
