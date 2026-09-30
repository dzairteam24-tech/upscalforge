# ScaleForge — notes for Claude Code

Owner: personal, local-only use. The owner writes in Arabic; reply in Arabic.

## Hard rules (from the master specification — never break)
- Independent implementation: no copied/translated code, tests or docs.
- **Zero third-party crates.** Adding one needs an entry in DEPENDENCIES.md and
  explicit owner approval. Never install anything automatically.
- No external inference engines (ONNX Runtime, TensorRT, OpenVINO, ...), no
  cuDNN/cuBLAS. GPU work uses the CUDA *driver API* through our own FFI.
- External pretrained weights only under ADR-0015: run by our engine, labelled
  `external`, never called ScaleForge models. Non-commercial ones are blocked
  by the Adobe Stock profile.
- Honesty: unfinished work is labelled INCOMPLETE; never publish unmeasured
  benchmark numbers; no fake/placeholder functionality.
- `unsafe_code = "forbid"` workspace-wide. The only planned exception is a GPU
  FFI crate, with a documented justification.
- `training/` is intentionally empty: own-model (SF-Net) training is postponed
  by the owner until the GPUs are installed. Do not start it unless asked.

## Gate before every commit
```sh
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace --release
```
Every change updates CHANGELOG.md and the docs it affects.

## Where things are
See DEVELOPMENT.md (crate table), ARCHITECTURE.md §27 (status),
docs/design/05-repository-and-roadmap.md (phases and exit criteria),
docs/adr/ (decisions).
