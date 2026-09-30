# Development Guide

## Principles
- Read `ARCHITECTURE.md` and the ADRs before changing a subsystem. Record
  significant decisions as a new ADR.
- **Originality:** no copied or translated code, tests, documentation or
  comments from other projects. External pretrained models are allowed only
  under ADR-0015's rules.
- **Dependencies:** none may be added without an entry in `DEPENDENCIES.md`
  and owner approval.
- **No `unsafe`:** forbidden workspace-wide (`unsafe_code = "forbid"`). The
  only planned exceptions are the GPU backend crates' FFI layers, each with a
  documented justification.
- **Honesty:** incomplete functionality is labelled `INCOMPLETE` in docs and
  errors. No placeholder implementations are presented as working.

## Repository layout
See `docs/design/05-repository-and-roadmap.md`. Crates appear only in the
phase that fills them.

| Crate | State |
|-------|-------|
| `crates/sf-core` | Foundation types, JSON, RNG (Phase 6) |
| `crates/sf-graph` | Operators, graph IR, validation, shape inference, locality, memory planning (Phase 7) |
| `crates/sf-compute` | Device abstraction and CPU reference backend (Phase 7) |
| `crates/sf-image` | Own zlib/DEFLATE, PNG, JPEG, TIFF/BigTIFF, EXIF, ICC/sRGB, resampling (Phase 11) |
| `crates/sf-analysis` | Degradation estimators, PSNR/SSIM (Phase 11) |
| `crates/sf-classic` | Classical restoration: denoise, deblock, upscale, sharpen, tone (ADR-0015) |
| `crates/sf-import` | ZIP, restricted pickle, `.pth` → `.sfm` for Real-ESRGAN architectures (ADR-0015) |
| `crates/scaleforge` | Engine: VRAM/host memory, tiling, runtime, strategy, QC, export, pipeline, reports |
| `crates/scaleforge-cli` | The `scaleforge` command (argument parsing and printing only) |
| `training/` | **Empty placeholder**: own-model training comes later |

## Before every commit
```sh
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace --release
```

## Tests
- Unit tests live next to the code (`#[cfg(test)]`).
- Property tests use `sf_core::Rng` with a fixed seed, so failures reproduce
  exactly.
- Robustness tests feed mutated and hand-built malformed input to parsers.
  Coverage-guided fuzzing is not set up yet (needs nightly + cargo-fuzz).
- End-to-end tests: `crates/scaleforge/tests/pipeline.rs` (engine) and
  `crates/scaleforge-cli/tests/cli.rs` (runs the real binary).

## Phase workflow
Each phase ends with a self-review (§42 of the specification) and a
`CHANGELOG.md` entry listing what was reviewed and fixed.
