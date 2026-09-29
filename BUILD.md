# Building ScaleForge

## Requirements

| Tool | Version | Needed for |
|------|---------|------------|
| Rust toolchain (`rustc`, `cargo`, `clippy`, `rustfmt`) | stable ≥ 1.88 (edition 2024); developed with 1.94 | everything |

No third-party crates are used yet. The GPU toolchains (CUDA toolkit,
Vulkan SDK) will be listed here when the GPU backends arrive (Phase 8).

## Commands

```sh
cargo build --release          # build all crates
cargo test                     # run all tests (debug)
cargo test --release           # run all tests (optimised)
cargo clippy --all-targets -- -D warnings
cargo fmt --check
RUSTDOCFLAGS="-D warnings" cargo doc --no-deps
```

There is no executable yet. The CLI arrives in Phase 18.
