//! End-to-end pipeline tests on real files in a temporary directory.

use std::path::{Path, PathBuf};

use scaleforge::{Controls, Engine, EngineConfig, ExportProfile, JobRequest, Mode, report};
use sf_core::json::Object;
use sf_core::{CancelToken, ErrorKind, Limits, NoProgress, Rng};
use sf_graph::sfm::{self, ModelFile};
use sf_graph::{Graph, GraphRole, InputKind, Op, OutputKind};
use sf_image::{ImageBuffer, Samples, jpeg, png};

struct TempDir(PathBuf);

impl TempDir {
    fn new(tag: &str) -> TempDir {
        let p = std::env::temp_dir().join(format!(
            "sf-test-{tag}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        TempDir(p)
    }
    fn path(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn engine() -> Engine {
    Engine::new(EngineConfig { threads: 2, host_budget: Some(2 << 30), ..EngineConfig::default() }).unwrap()
}

fn gaussian(rng: &mut Rng) -> f64 {
    let (u1, u2) = (rng.next_f64().max(1e-12), rng.next_f64());
    (-2.0 * u1.ln()).sqrt() * (2.0 * std::f64::consts::PI * u2).cos()
}

/// A smooth colour scene (values 0–255) with an edge.
fn scene(w: usize, h: usize) -> Vec<f64> {
    let mut v = Vec::new();
    for y in 0..h {
        for x in 0..w {
            let e = if x > w / 2 { 50.0 } else { 0.0 };
            v.extend([
                60.0 + 100.0 * x as f64 / w as f64 + e,
                70.0 + 80.0 * y as f64 / h as f64,
                150.0 - 60.0 * x as f64 / w as f64,
            ]);
        }
    }
    v
}

fn to_u8(v: &[f64]) -> Vec<u8> {
    v.iter().map(|x| x.round().clamp(0.0, 255.0) as u8).collect()
}

fn write_png(path: &Path, w: usize, h: usize, c: u8, samples: Samples) {
    let b = ImageBuffer::new(w as u32, h as u32, c, samples).unwrap();
    std::fs::write(path, png::encode(&b, &png::EncodeOptions::default()).unwrap()).unwrap();
}

fn run(e: &Engine, r: &JobRequest) -> sf_core::Result<scaleforge::JobReport> {
    e.run(r, &NoProgress, &CancelToken::new())
}

fn decision<'a>(rep: &'a scaleforge::JobReport, p: &str) -> &'a scaleforge::strategy::Decision {
    rep.decisions.iter().find(|d| d.parameter == p).unwrap_or_else(|| panic!("no decision {p}"))
}

#[test]
fn noisy_image_is_denoised_and_enlarged_faithfully() {
    let dir = TempDir::new("noise");
    let (w, h) = (96, 72);
    let clean = scene(w, h);
    let mut rng = Rng::seed_from_u64(1);
    let noisy: Vec<f64> = clean.iter().map(|v| v + 6.0 * gaussian(&mut rng)).collect();
    write_png(&dir.path("in.png"), w, h, 3, Samples::U8(to_u8(&noisy)));
    let e = engine();
    let mut req = JobRequest::new(dir.path("in.png"), dir.path("out.png"));
    req.scale = Some(2);
    let rep = run(&e, &req).unwrap();
    assert_eq!(rep.output_size, (192, 144));
    // Luma noise of independent per-channel noise: 6 · √(0.299² + 0.587² + 0.114²) ≈ 4.0.
    let luma_sigma = 6.0 * (0.299f64.powi(2) + 0.587f64.powi(2) + 0.114f64.powi(2)).sqrt();
    let est = rep.analysis.noise_sigma.value;
    assert!((est - luma_sigma).abs() < 0.15 * luma_sigma, "noise estimate {est} vs {luma_sigma}");
    let d = decision(&rep, "denoise");
    assert_eq!((d.rule, d.source.name()), ("noise-above-1-level", "auto"));
    assert!(rep.qc.passed(), "{:?}", rep.qc);
    // The denoised result, downscaled back, is closer to the clean scene than the noisy input.
    let out = sf_image::decode_any(&std::fs::read(dir.path("out.png")).unwrap(), &Limits::default()).unwrap();
    let down =
        sf_image::resample::resize(&out.buffer.to_f32(), 192, 144, 3, w, h, sf_image::resample::Filter::Area);
    let err =
        |a: &[f64]| (a.iter().zip(&clean).map(|(x, y)| (x - y).powi(2)).sum::<f64>() / a.len() as f64).sqrt();
    let down255: Vec<f64> = down.iter().map(|&v| f64::from(v) * 255.0).collect();
    assert!(err(&down255) < 0.6 * err(&noisy), "{} vs {}", err(&down255), err(&noisy));
    // The report serialises to JSON and parses back.
    let text = sf_core::json::to_string_pretty(&report::job_json(&rep)).unwrap();
    assert!(sf_core::json::parse(text.as_bytes(), &Limits::default()).is_ok());
}

#[test]
fn jpeg_artefacts_trigger_deblocking_and_output_is_jpeg() {
    let dir = TempDir::new("jpeg");
    let (w, h) = (96, 64);
    let b = ImageBuffer::new(w as u32, h as u32, 3, Samples::U8(to_u8(&scene(w, h)))).unwrap();
    std::fs::write(
        dir.path("in.jpg"),
        jpeg::encode(&b, &jpeg::EncodeOptions { quality: 20, ..Default::default() }).unwrap(),
    )
    .unwrap();
    let e = engine();
    let rep = run(&e, &JobRequest::new(dir.path("in.jpg"), dir.path("out.jpg"))).unwrap();
    assert_eq!(decision(&rep, "deblock").rule, "jpeg-evidence");
    assert!(rep.analysis.jpeg_quality.as_ref().is_some_and(|q| (q.value - 20.0).abs() <= 1.0));
    assert!(jpeg::decode(&std::fs::read(dir.path("out.jpg")).unwrap(), &Limits::default()).is_ok());
}

#[test]
fn outputs_are_never_overwritten_by_accident() {
    let dir = TempDir::new("overwrite");
    write_png(&dir.path("in.png"), 8, 8, 1, Samples::U8(vec![100; 64]));
    let e = engine();
    let req = JobRequest::new(dir.path("in.png"), dir.path("out.png"));
    run(&e, &req).unwrap();
    let err = run(&e, &req).unwrap_err();
    assert_eq!(err.kind(), ErrorKind::InvalidInput);
    let mut again = req.clone();
    again.overwrite = true;
    run(&e, &again).unwrap();
    // No temporary files are left behind.
    let leftovers = std::fs::read_dir(&dir.0)
        .unwrap()
        .filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().contains("sf-tmp"))
        .count();
    assert_eq!(leftovers, 0);
    // Same input and output file is refused.
    let mut same = JobRequest::new(dir.path("in.png"), dir.path("in.png"));
    same.overwrite = true;
    assert!(run(&e, &same).is_err());
    // Unknown formats are refused up front.
    assert_eq!(
        run(&e, &JobRequest::new(dir.path("in.png"), dir.path("x.gif"))).unwrap_err().kind(),
        ErrorKind::Unsupported
    );
}

#[test]
fn orientation_alpha_and_16_bit_are_preserved() {
    let dir = TempDir::new("layout");
    // RGBA 16-bit, 6×4.
    let px: Vec<u16> = (0..6 * 4)
        .flat_map(|i| [i * 1000, 20_000, 40_000, if i % 2 == 0 { 65_535 } else { 32_768 }])
        .collect();
    write_png(&dir.path("in.png"), 6, 4, 4, Samples::U16(px));
    let e = engine();
    let mut req = JobRequest::new(dir.path("in.png"), dir.path("out.png"));
    req.scale = Some(2);
    run(&e, &req).unwrap();
    let out = sf_image::decode_any(&std::fs::read(dir.path("out.png")).unwrap(), &Limits::default()).unwrap();
    assert_eq!((out.buffer.width(), out.buffer.height(), out.buffer.channels()), (12, 8, 4));
    assert!(matches!(out.buffer.samples(), Samples::U16(_)));

    // A JPEG marked with EXIF orientation 6 comes out rotated upright.
    let b = ImageBuffer::new(10, 4, 3, Samples::U8(vec![128; 120])).unwrap();
    let mut data = jpeg::encode(&b, &jpeg::EncodeOptions::default()).unwrap();
    let exif = b"Exif\0\0MM\0\x2a\0\0\0\x08\0\x01\x01\x12\0\x03\0\0\0\x01\0\x06\0\0\0\0\0\0";
    let mut seg = vec![0xFF, 0xE1];
    seg.extend(((exif.len() + 2) as u16).to_be_bytes());
    seg.extend(exif);
    data.splice(2..2, seg);
    std::fs::write(dir.path("rot.jpg"), data).unwrap();
    let rep = run(&e, &JobRequest::new(dir.path("rot.jpg"), dir.path("rot.png"))).unwrap();
    assert_eq!(rep.output_size, (4, 10));
}

fn tiny_model(dir: &TempDir, scope: &str) -> PathBuf {
    // A ×2 "model": nearest upsampling followed by a 3×3 averaging conv.
    let mut g = Graph::new(GraphRole::Main);
    let x = g.input("image", InputKind::Spatial { channels: 3, spacing_log2: 0 });
    let u = g.node(Op::UpsampleNearest2, &[x]);
    let w = g.param("w", &[3, 3, 3, 3]);
    let b = g.param("b", &[3]);
    let y = g
        .node(Op::Conv2d { out_channels: 3, kernel: 3, stride: 1, depthwise: false, bias: true }, &[u, w, b]);
    let y = g.node(Op::Clamp { lo: 0.0, hi: 1.0 }, &[y]);
    g.output("image", y, OutputKind::Tensor);
    let mut wt = vec![0f32; 81];
    for c in 0..3 {
        for k in 0..9 {
            wt[(c * 3 + c) * 9 + k] = 1.0 / 9.0;
        }
    }
    let mut m = Object::new();
    m.insert("name", format!("tiny-{scope}"));
    m.insert("provenance", "external");
    m.insert("licence", "test");
    m.insert("licence_scope", scope);
    m.insert("scale", 2u64);
    m.insert("architecture", "test-x2");
    let path = dir.path(&format!("tiny-{scope}.sfm"));
    std::fs::write(
        &path,
        sfm::write(&ModelFile { metadata: m, graph: g, weights: vec![wt, vec![0.0; 3]] }).unwrap(),
    )
    .unwrap();
    path
}

#[test]
fn model_path_modes_and_licence_block() {
    let dir = TempDir::new("model");
    let (w, h) = (40, 30);
    write_png(&dir.path("in.png"), w, h, 3, Samples::U8(to_u8(&scene(w, h))));
    let e = engine();
    let commercial = tiny_model(&dir, "commercial");
    let noncommercial = tiny_model(&dir, "non-commercial");

    let mut req = JobRequest::new(dir.path("in.png"), dir.path("bal.png"));
    req.scale = Some(2);
    req.mode = Mode::Balanced;
    req.model = Some(commercial.clone());
    let rep = run(&e, &req).unwrap();
    assert!(decision(&rep, "upscale").value.contains("weight 0.50"));
    assert!(decision(&rep, "tile").value.contains("tiles"));
    assert!(rep.qc.notes.iter().any(|n| n.contains("exact tiling")));
    assert_eq!(rep.model.as_ref().unwrap().1, "external");

    // Faithful ignores generative models, with an explanation.
    req.mode = Mode::Faithful;
    req.output = dir.path("faith.png");
    let rep = run(&e, &req).unwrap();
    assert_eq!(decision(&rep, "model").rule, "faithful-excludes-generative");

    // ×4 request from a ×2 model: model then classical ×2.
    req.mode = Mode::Reconstruction { strength: 1.0 };
    req.scale = Some(4);
    req.output = dir.path("x4.png");
    let rep = run(&e, &req).unwrap();
    assert_eq!(rep.output_size, (160, 120));

    // The Adobe Stock profile refuses non-commercial models outright.
    let mut adobe = JobRequest::new(dir.path("in.png"), dir.path("stock.jpg"));
    adobe.export = Some(ExportProfile::AdobeStock);
    adobe.mode = Mode::Balanced;
    adobe.model = Some(noncommercial);
    let err = run(&e, &adobe).unwrap_err();
    assert!(err.message().contains("non-commercial"), "{err}");
}

#[test]
fn adobe_stock_profile_produces_a_compliant_file() {
    let dir = TempDir::new("adobe");
    let (w, h) = (1000, 700); // 0.7 MP → ×4 = 11.2 MP (×2 = 2.8 MP is too small)
    let mut rng = Rng::seed_from_u64(7);
    let v: Vec<f64> = scene(w, h).iter().map(|x| x + 1.5 * gaussian(&mut rng)).collect();
    write_png(&dir.path("in.png"), w, h, 3, Samples::U8(to_u8(&v)));
    let e = engine();
    let mut req = JobRequest::new(dir.path("in.png"), dir.path("stock.jpg"));
    req.export = Some(ExportProfile::AdobeStock);
    let rep = run(&e, &req).unwrap();
    let c = rep.compliance.as_ref().unwrap();
    assert_eq!(decision(&rep, "scale").value, "x4");
    assert_eq!(c.verdict, "pass-with-warnings", "{c:?}");
    assert!(c.rules.iter().all(|r| r.1), "{:?}", c.rules);
    assert!(c.warnings[0].contains("enlarged x4"));
    assert!(c.ai_disclosure.contains("No generative AI"));
    let out = jpeg::decode(&std::fs::read(dir.path("stock.jpg")).unwrap(), &Limits::default()).unwrap();
    assert_eq!((out.buffer.width(), out.buffer.height()), (4000, 2800));
    let icc = sf_image::color::IccProfile::parse(out.meta.icc_profile.as_ref().unwrap()).unwrap();
    assert_eq!(icc.transfer(), sf_image::color::TransferClass::SrgbLike);

    // PNG output is refused for this profile.
    let mut bad = JobRequest::new(dir.path("in.png"), dir.path("stock.png"));
    bad.export = Some(ExportProfile::AdobeStock);
    assert!(run(&e, &bad).is_err());
}

#[test]
fn cancellation_stops_a_job() {
    let dir = TempDir::new("cancel");
    write_png(&dir.path("in.png"), 16, 16, 3, Samples::U8(vec![90; 768]));
    let cancel = CancelToken::new();
    cancel.cancel();
    let err = engine()
        .run(&JobRequest::new(dir.path("in.png"), dir.path("o.png")), &NoProgress, &cancel)
        .unwrap_err();
    assert_eq!(err.kind(), ErrorKind::Cancelled);
    assert!(!dir.path("o.png").exists());
    let _ = Controls::default();
}

/// Runs `req` whole and band by band (bands of 16 rows, so there are many)
/// and checks that the two output files are byte-for-byte identical.
fn assert_banded_matches_whole(
    e: &Engine,
    dir: &TempDir,
    input: &str,
    out: &str,
    set: impl Fn(&mut JobRequest),
) {
    let mut whole = JobRequest::new(dir.path(input), dir.path(&format!("whole-{out}")));
    set(&mut whole);
    let rep_whole = run(e, &whole).unwrap();
    let mut banded = JobRequest::new(dir.path(input), dir.path(&format!("banded-{out}")));
    set(&mut banded);
    banded.stream = true;
    banded.band_rows = Some(16);
    let rep = run(e, &banded).unwrap();
    assert!(decision(&rep, "processing").value.starts_with("band by band: 16 input rows"));
    let a = std::fs::read(dir.path(&format!("whole-{out}"))).unwrap();
    let b = std::fs::read(dir.path(&format!("banded-{out}"))).unwrap();
    assert!(a == b, "{input} → {out}: banded output differs from whole-image output");
    // QC statistics are sums over bands: equal up to summation order.
    for (x, y) in rep_whole.qc.checks.iter().zip(&rep.qc.checks) {
        assert!(
            (x.value - y.value).abs() <= 1e-9 * x.value.abs().max(1.0),
            "{}: {} vs {}",
            x.name,
            x.value,
            y.value
        );
    }
}

#[test]
fn banded_processing_is_bit_identical_to_whole_image_processing() {
    let dir = TempDir::new("banded");
    let e = engine();
    // Noisy RGB (denoising active), 300 rows: interior bands see full margins.
    let (w, h) = (48, 300);
    let mut rng = Rng::seed_from_u64(21);
    let noisy: Vec<f64> = scene(w, h).iter().map(|v| v + 6.0 * gaussian(&mut rng)).collect();
    write_png(&dir.path("noisy.png"), w, h, 3, Samples::U8(to_u8(&noisy)));
    for scale in [1, 2, 4] {
        assert_banded_matches_whole(&e, &dir, "noisy.png", &format!("x{scale}.png"), |r| {
            r.scale = Some(scale);
            r.controls = Controls { sharpen: Some(0.6), auto_tone: true, ..Controls::default() };
        });
    }
    // JPEG blocks (deblocking active), TIFF output.
    let b = ImageBuffer::new(40, 264, 3, Samples::U8(to_u8(&scene(40, 264)))).unwrap();
    std::fs::write(
        dir.path("blocky.jpg"),
        jpeg::encode(&b, &jpeg::EncodeOptions { quality: 20, ..Default::default() }).unwrap(),
    )
    .unwrap();
    assert_banded_matches_whole(&e, &dir, "blocky.jpg", "x2.tif", |r| r.scale = Some(2));
    // 16-bit RGBA: alpha is enlarged separately and re-attached.
    let px: Vec<u16> = (0..36 * 200u32)
        .flat_map(|i| [(i * 97 % 65_536) as u16, 20_000, (i * 13 % 65_536) as u16, (i % 36 * 1800) as u16])
        .collect();
    write_png(&dir.path("rgba16.png"), 36, 200, 4, Samples::U16(px));
    assert_banded_matches_whole(&e, &dir, "rgba16.png", "x8.png", |r| r.scale = Some(8));
}

#[test]
fn banding_is_chosen_automatically_when_the_image_does_not_fit() {
    let dir = TempDir::new("auto-band");
    let (w, h) = (160, 120);
    write_png(&dir.path("in.png"), w, h, 3, Samples::U8(to_u8(&scene(w, h))));
    // x8 needs 1280×960×3×16 B ≈ 59 MB whole; the budget is 56 MB.
    let small =
        Engine::new(EngineConfig { threads: 2, host_budget: Some(56 << 20), ..EngineConfig::default() })
            .unwrap();
    let mut req = JobRequest::new(dir.path("in.png"), dir.path("small.png"));
    req.scale = Some(8);
    let rep = run(&small, &req).unwrap();
    let d = decision(&rep, "processing");
    assert_eq!(d.source.name(), "auto");
    assert!(d.evidence.contains("memory budget is 56 MB"), "{}", d.evidence);
    // Same bytes as with enough memory.
    let mut big_req = JobRequest::new(dir.path("in.png"), dir.path("big.png"));
    big_req.scale = Some(8);
    run(&engine(), &big_req).unwrap();
    assert!(std::fs::read(dir.path("small.png")).unwrap() == std::fs::read(dir.path("big.png")).unwrap());
}

#[test]
fn a_png_larger_than_the_budget_is_read_band_by_band() {
    let dir = TempDir::new("png-bands");
    // 2400×1600 RGB decodes to 11.5 MB, more than a quarter of the 40 MB
    // budget: the file is never decoded whole, and the analysis sees a
    // region at the centre.
    let (w, h) = (2400, 1600);
    // Smooth gradients with mild noise and no edges on the 8-pixel grid.
    let mut rng = Rng::seed_from_u64(33);
    let smooth: Vec<f64> = (0..w * h)
        .flat_map(|i| {
            let (x, y) = ((i % w) as f64, (i / w) as f64);
            [40.0 + 0.07 * x, 60.0 + 0.1 * y, 200.0 - 0.05 * x - 0.03 * y]
        })
        .map(|v| v + 1.5 * gaussian(&mut rng))
        .collect();
    write_png(&dir.path("in.png"), w, h, 3, Samples::U8(to_u8(&smooth)));
    let e = Engine::new(EngineConfig { threads: 2, host_budget: Some(40 << 20), ..EngineConfig::default() })
        .unwrap();
    let rep = run(&e, &JobRequest::new(dir.path("in.png"), dir.path("out.png"))).unwrap();
    assert_eq!(decision(&rep, "analysis").rule, "image-larger-than-memory");
    // Regression: the seams of a patch mosaic once read as JPEG block edges.
    // The region analysis must decide like a whole-image analysis.
    let whole = run(&engine(), &JobRequest::new(dir.path("in.png"), dir.path("whole.png"))).unwrap();
    for p in ["deblock", "denoise"] {
        assert_eq!(decision(&rep, p).value, decision(&whole, p).value, "{p}");
    }
    assert_eq!(decision(&rep, "deblock").value, "off");
    assert!(decision(&rep, "processing").value.starts_with("band by band"));
    let out = sf_image::decode_any(&std::fs::read(dir.path("out.png")).unwrap(), &Limits::default()).unwrap();
    assert_eq!((out.buffer.width(), out.buffer.height()), (2400, 1600));
    assert!(rep.qc.passed(), "{:?}", rep.qc);
}

#[test]
fn banding_refuses_what_it_does_not_support_yet() {
    let dir = TempDir::new("band-limits");
    write_png(&dir.path("in.png"), 64, 48, 3, Samples::U8(to_u8(&scene(64, 48))));
    let e = engine();
    let mut jpg = JobRequest::new(dir.path("in.png"), dir.path("out.jpg"));
    jpg.stream = true;
    let err = run(&e, &jpg).unwrap_err();
    assert_eq!(err.kind(), ErrorKind::LimitExceeded);
    assert!(err.to_string().contains("INCOMPLETE"), "{err}");
    let mut with_model = JobRequest::new(dir.path("in.png"), dir.path("m.png"));
    with_model.stream = true;
    with_model.model = Some(tiny_model(&dir, "commercial"));
    with_model.mode = Mode::Reconstruction { strength: 1.0 };
    with_model.scale = Some(2);
    let err = run(&e, &with_model).unwrap_err();
    assert!(err.to_string().contains("AI models"), "{err}");
    assert!(!dir.path("m.png").exists());
}
