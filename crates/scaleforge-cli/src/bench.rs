//! `scaleforge benchmark`: measures the pipeline on a deterministic
//! synthetic image. Only measured values are reported; anything that
//! cannot be measured here is `null`.

use std::path::PathBuf;
use std::time::Instant;

use scaleforge::{Engine, EngineConfig, JobRequest, Mode};
use sf_core::json::{Number, Object, Value};
use sf_core::{CancelToken, Error, NoProgress, Result, Rng};

use crate::args::Args;

/// Process CPU time in seconds, from `/proc/self/stat` (Linux; the kernel
/// reports it in USER_HZ = 100 ticks per second).
fn cpu_seconds() -> Option<f64> {
    let s = std::fs::read_to_string("/proc/self/stat").ok()?;
    let rest = &s[s.rfind(')')? + 2..];
    let f: Vec<&str> = rest.split_whitespace().collect();
    let (u, k): (f64, f64) = (f.get(11)?.parse().ok()?, f.get(12)?.parse().ok()?);
    Some((u + k) / 100.0)
}

fn cpu_model() -> Option<String> {
    let s = std::fs::read_to_string("/proc/cpuinfo").ok()?;
    s.lines()
        .find(|l| l.starts_with("model name"))
        .and_then(|l| l.split(':').nth(1))
        .map(|v| v.trim().to_string())
}

fn num(v: f64) -> Value {
    Number::from_f64(v).map(Value::Number).unwrap_or(Value::Null)
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(f64::total_cmp);
    v[v.len() / 2]
}

/// Runs the benchmark.
pub fn run(raw: &[String]) -> Result<()> {
    let a = Args::parse(
        raw,
        &[("size", true), ("scale", true), ("repeat", true), ("model", true), ("mode", true), ("json", true)],
    )?;
    let (w, h) = match a.value("size").unwrap_or("1024x768").split_once('x') {
        Some((w, h)) => (
            w.parse::<usize>().map_err(|_| Error::invalid_input("--size WxH"))?,
            h.parse::<usize>().map_err(|_| Error::invalid_input("--size WxH"))?,
        ),
        None => return Err(Error::invalid_input("--size WxH")),
    };
    let scale = a.number::<u32>("scale")?.unwrap_or(2);
    let repeat = a.number::<usize>("repeat")?.unwrap_or(3).max(1);
    let model = a.value("model").map(PathBuf::from);
    let mode = match a.value("mode") {
        Some("balanced") => Mode::Balanced,
        Some("reconstruction") => Mode::Reconstruction { strength: 1.0 },
        _ if model.is_some() => Mode::Balanced,
        _ => Mode::Faithful,
    };
    let dir = std::env::temp_dir().join(format!("scaleforge-bench-{}", std::process::id()));
    std::fs::create_dir_all(&dir)?;
    let result = (|| -> Result<Value> {
        // Deterministic scene: gradients, edges and mild noise.
        let mut rng = Rng::seed_from_u64(0xbe_c4);
        let mut px = Vec::with_capacity(w * h * 3);
        for y in 0..h {
            for x in 0..w {
                let e = if (x / 64 + y / 64) % 2 == 0 { 40.0 } else { 0.0 };
                for c in 0..3 {
                    let v = 50.0
                        + 120.0 * (x as f64 / w as f64)
                        + 60.0 * (y as f64 / h as f64) * c as f64 / 2.0
                        + e
                        + 3.0 * (rng.next_f64() - 0.5);
                    px.push(v.clamp(0.0, 255.0) as u8);
                }
            }
        }
        let b = sf_image::ImageBuffer::new(w as u32, h as u32, 3, sf_image::Samples::U8(px))?;
        std::fs::write(dir.join("in.png"), sf_image::png::encode(&b, &Default::default())?)?;

        let model_load_ms = match &model {
            Some(m) => {
                let t = Instant::now();
                scaleforge::runtime::ModelHandle::load(m, &sf_core::Limits::default())?;
                Some(t.elapsed().as_secs_f64() * 1e3)
            }
            None => None,
        };
        let engine = Engine::new(EngineConfig::default())?;
        let mut totals = Vec::new();
        let mut stages: Vec<(&'static str, Vec<f64>)> = Vec::new();
        let mut peak = 0u64;
        let mut cpu_util = Vec::new();
        for i in 0..=repeat {
            let mut req = JobRequest::new(dir.join("in.png"), dir.join("out.png"));
            req.scale = Some(scale);
            req.mode = mode;
            req.model = model.clone();
            req.overwrite = true;
            let (c0, t0) = (cpu_seconds(), Instant::now());
            let rep = engine.run(&req, &NoProgress, &CancelToken::new())?;
            let wall = t0.elapsed().as_secs_f64();
            if i == 0 {
                continue; // warm-up (includes model upload into the cache)
            }
            totals.push(wall * 1e3);
            if let (Some(a), Some(b)) = (c0, cpu_seconds()) {
                cpu_util.push((b - a) / wall);
            }
            peak = peak.max(rep.peak_device_bytes);
            for (k, v) in rep.timings_ms {
                match stages.iter_mut().find(|s| s.0 == k) {
                    Some(s) => s.1.push(v),
                    None => stages.push((k, vec![v])),
                }
            }
        }
        let total = median(totals.clone());
        let mut o = Object::new();
        let mut env = Object::new();
        env.insert("scaleforge", env!("CARGO_PKG_VERSION"));
        env.insert("os", std::env::consts::OS);
        env.insert("arch", std::env::consts::ARCH);
        env.insert("cpu", cpu_model().map_or(Value::Null, Value::from));
        env.insert("threads", engine.config().threads as u64);
        env.insert("device", engine.device_info().name);
        env.insert("build", if cfg!(debug_assertions) { "debug" } else { "release" });
        o.insert("environment", env);
        let mut cfg = Object::new();
        cfg.insert("input", format!("{w}x{h} synthetic RGB"));
        cfg.insert("scale", u64::from(scale));
        cfg.insert("mode", mode.name());
        cfg.insert("model", model.as_ref().map_or(Value::Null, |m| Value::from(m.display().to_string())));
        cfg.insert("repetitions", repeat as u64);
        o.insert("configuration", cfg);
        let mut r = Object::new();
        r.insert("total_ms_median", num(total));
        r.insert("total_ms_all", totals.iter().map(|&v| num(v)).collect::<Vec<_>>());
        let mut st = Object::new();
        for (k, v) in stages {
            st.insert(k, num(median(v)));
        }
        r.insert("stage_ms_median", st);
        r.insert(
            "output_megapixels_per_second",
            num((w * h) as f64 * f64::from(scale * scale) / 1e6 / (total / 1e3)),
        );
        r.insert("model_load_ms", model_load_ms.map_or(Value::Null, num));
        r.insert("peak_tracked_device_bytes", peak);
        r.insert("cpu_utilization", if cpu_util.is_empty() { Value::Null } else { num(median(cpu_util)) });
        r.insert("gpu_utilization", Value::Null);
        r.insert("transfer_bytes", Value::Null);
        o.insert("results", r);
        o.insert(
            "not_measured",
            vec![
                Value::from("gpu_utilization: no GPU backend (INCOMPLETE)"),
                Value::from("transfer_bytes: host and device share memory on the CPU backend"),
            ],
        );
        Ok(Value::from(o))
    })();
    let _ = std::fs::remove_dir_all(&dir);
    let v = result?;
    let text = sf_core::json::to_string_pretty(&v)?;
    print!("{text}");
    if let Some(p) = a.value("json") {
        std::fs::write(p, &text)?;
    }
    Ok(())
}
