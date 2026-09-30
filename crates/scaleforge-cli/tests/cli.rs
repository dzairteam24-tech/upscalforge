//! Runs the real `scaleforge` binary.

use std::path::PathBuf;
use std::process::Command;

fn bin() -> Command {
    Command::new(env!("CARGO_BIN_EXE_scaleforge"))
}

fn tmp(tag: &str) -> PathBuf {
    let p = std::env::temp_dir().join(format!("sf-cli-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&p);
    std::fs::create_dir_all(&p).unwrap();
    p
}

fn write_png(path: &std::path::Path, w: u32, h: u32) {
    let px: Vec<u8> = (0..w * h * 3).map(|i| ((i / 3) % 200 + 20) as u8).collect();
    let b = sf_image::ImageBuffer::new(w, h, 3, sf_image::Samples::U8(px)).unwrap();
    std::fs::write(path, sf_image::png::encode(&b, &Default::default()).unwrap()).unwrap();
}

#[test]
fn help_and_unknown_command() {
    let out = bin().arg("help").output().unwrap();
    assert!(out.status.success());
    assert!(String::from_utf8_lossy(&out.stdout).contains("upscale <input>"));
    let out = bin().arg("frobnicate").output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    let out = bin().args(["upscale", "a.png", "-o", "b.png", "--bogus"]).output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).contains("unknown option --bogus"));
}

#[test]
fn upscale_writes_output_and_report_and_protects_existing_files() {
    let d = tmp("up");
    write_png(&d.join("in.png"), 24, 16);
    let run = |extra: &[&str]| {
        let mut c = bin();
        c.args([
            "upscale",
            d.join("in.png").to_str().unwrap(),
            "-o",
            d.join("out.png").to_str().unwrap(),
            "--scale",
            "2",
        ]);
        c.args(extra);
        c.output().unwrap()
    };
    let rep = d.join("r.json");
    let out = run(&["--report", rep.to_str().unwrap()]);
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    let report = std::fs::read_to_string(&rep).unwrap();
    assert!(report.contains("\"decisions\""));
    assert_eq!(run(&[]).status.code(), Some(2), "existing output refused");
    assert!(run(&["--overwrite"]).status.success());
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn adobe_profile_refuses_images_that_cannot_reach_the_minimum() {
    let d = tmp("adobe");
    write_png(&d.join("tiny.png"), 100, 80);
    let out = bin()
        .args([
            "upscale",
            d.join("tiny.png").to_str().unwrap(),
            "-o",
            d.join("s.jpg").to_str().unwrap(),
            "--export",
            "adobe-stock",
        ])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).contains("too small"));
    assert!(!d.join("s.jpg").exists());
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn batch_confines_outputs_and_counts_failures() {
    let d = tmp("batch");
    let input = d.join("in");
    std::fs::create_dir_all(&input).unwrap();
    write_png(&input.join("a.png"), 16, 16);
    write_png(&input.join("b.png"), 20, 12);
    std::fs::write(input.join("broken.png"), b"not a png").unwrap();
    std::fs::write(input.join("notes.txt"), b"skip me").unwrap();
    let out = bin()
        .args(["batch", input.to_str().unwrap(), "-o", d.join("out").to_str().unwrap(), "--ext", "jpg"])
        .output()
        .unwrap();
    let text = String::from_utf8_lossy(&out.stdout);
    assert_eq!(out.status.code(), Some(8), "{text}");
    assert!(text.contains("2 processed, 1 failed, 1 skipped"), "{text}");
    assert!(d.join("out/a.jpg").exists() && d.join("out/b.jpg").exists());
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn doctor_passes() {
    let out = bin().arg("doctor").output().unwrap();
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stdout));
}
