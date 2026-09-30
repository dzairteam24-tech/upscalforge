# Building ScaleForge

## Requirements

| Tool | Version | Needed for |
|------|---------|------------|
| Rust toolchain (`rustc`, `cargo`, `clippy`, `rustfmt`) | stable ≥ 1.88 (edition 2024); developed with 1.94, also checked with 1.98.1 | everything |

No third-party crates are used. Building needs no network access after the
toolchain is installed. The GPU toolchains (CUDA toolkit, Vulkan SDK) will be
listed here when the GPU backends arrive (Phase 8, INCOMPLETE).

## Commands

```sh
cargo build --release          # build all crates
cargo test                     # run all tests (debug)
cargo test --release           # run all tests (optimised)
cargo clippy --all-targets -- -D warnings
cargo fmt --check
RUSTDOCFLAGS="-D warnings" cargo doc --no-deps
```

## Running

The executable is `target/release/scaleforge`. Run `scaleforge help` for all
commands, or see README.md. `scaleforge doctor` checks the installation.

Install it with:

```sh
cargo install --path crates/scaleforge-cli
```
