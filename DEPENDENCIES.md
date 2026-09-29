# Dependencies

Policy: no dependency is added before it is documented here **and approved by
the project owner**. For each one we ask whether an in-house implementation is
realistic, and use the dependency only when writing our own would be
technically worse or would add security risk without a benefit.

Versions are the latest stable releases on crates.io as of 2026-09-29. Licences
were read from crates.io metadata. Every licence must be compatible with the
project's Apache-2.0 licence.

**Status of every entry below: PROPOSED, not approved, not installed.**

## Rust — runtime

| Name | Version | Purpose | Licence | Class | Security | Performance | In-house realistic? |
|------|---------|---------|---------|-------|----------|-------------|---------------------|
| `png` | 0.18.1 | PNG decode/encode, row streaming | MIT OR Apache-2.0 | runtime (`sf-image`, feature `png`) | Parses untrusted input. Memory-safe Rust, widely fuzzed. We add our own limits in front. | Good; streaming rows | Technically yes (inflate + filters), but it adds security-critical parsing surface for no product benefit. **Use the dependency.** |
| `zune-jpeg` | 0.5.15 | JPEG decode | MIT OR Apache-2.0 OR Zlib | runtime (feature `jpeg`) | Untrusted input; memory-safe, fuzzed | Fast (SIMD) | Same reasoning as `png`. **Use the dependency.** |
| `jpeg-encoder` | 0.7.1 | JPEG encode | (MIT OR Apache-2.0) AND IJG | runtime (feature `jpeg`) | Encodes our own data only (low risk) | Adequate | Realistic (baseline JPEG encode is well specified). **Decide in Phase 6** after comparing output quality. The IJG term requires an attribution notice. |
| `image-webp` | 0.2.4 | WebP decode; lossless encode | MIT OR Apache-2.0 | runtime (feature `webp`) | Untrusted input; memory-safe | Adequate | Not realistic for lossy VP8 decoding. Note: **lossy WebP encoding is not available** in pure Rust. Encoding a lossy WebP would need libwebp (C); not proposed. |
| `tiff` | 0.11.3 | TIFF decode/encode, including BigTIFF | MIT | runtime (feature `tiff`) | Untrusted input; memory-safe | Adequate; random access for tiled TIFF | Same reasoning as `png` |
| `serde` + `serde_json` | 1.0.229 / 1.0.151 | `.sfm` header, reports, tuning cache, manifests | MIT OR Apache-2.0 | runtime | JSON parsing of untrusted model headers. Mature and fuzzed. Size-limited before parsing. | Headers are small; negligible | A minimal JSON parser is realistic (~600 lines). The dependency is preferred for its robustness on a security-relevant parser. **Open for owner decision.** |
| `clap` | 4.6.7 | CLI argument parsing, help, validation | MIT OR Apache-2.0 | runtime (CLI crate only) | Low | Negligible | Realistic but tedious. It would give an inferior user experience (help output, suggestions). **Use the dependency.** |
| `ash` | 0.38.0+1.3.281 | Vulkan API bindings | MIT OR Apache-2.0 | runtime, optional (`sf-compute-vulkan`) | FFI boundary; loads the system Vulkan loader | None (thin bindings) | Hand-written Vulkan bindings are not realistic at this API size. Needed in Phase 14b. |
| CUDA driver access | — | CUDA backend | — | runtime, optional | FFI | — | **Planned in-house**: a small, hand-written FFI to about 30 driver API and NVRTC functions, loaded at run time. Needs one dynamic-loading helper: `libloading` 0.9.0 (ISC) or a direct platform call. Decided in Phase 14b. `cudarc` 0.19.10 (MIT OR Apache-2.0) is the alternative if the hand-written FFI proves error-prone. |

## Rust — in-house by decision (no dependency)

| Capability | Why in-house |
|------------|--------------|
| SHA-256 (model integrity) | Small, standard algorithm, verifiable against NIST test vectors. It checks integrity, not authenticity. |
| Thread pool / parallel loops | `std::thread::scope` covers our row-parallel kernels. `rayon` 1.12.0 would be proposed only if measurements show a benefit. |
| ICC profile classification | Only the header and a few tags are needed (ARCHITECTURE §5.4). |
| Resampling, colour transfer functions | Core to image quality; we need exact control of kernel support. |
| Benchmark harness | Required as a product feature. `criterion` would not measure the metrics we need (VRAM, transfers). |
| Tensor kernels (CPU) | The operator set is small, and the kernels are the reference implementation. |

## Rust — development only

| Name | Version | Purpose | Licence | Notes |
|------|---------|---------|---------|-------|
| `cargo-fuzz` (tool) | pending | Fuzzing codecs, ICC, `.sfm` | MIT OR Apache-2.0 | Phase 16; needs a nightly toolchain |
| `proptest` | 1.11.0 | Property tests with shrinking | MIT OR Apache-2.0 | **Optional.** The default plan is our own seeded generators. Proposed only if shrinking proves necessary. |

## Python — training only (never linked into the engine)

| Name | Version | Purpose | Licence | Notes |
|------|---------|---------|---------|-------|
| PyTorch | pinned at approval time | Autodiff, optimisers, GPU training | BSD-3-Clause | Building autodiff in-house is not realistic (ADR-0001). Checkpoints are loaded only with weights-only deserialisation. |
| NumPy | pinned at approval time | Array utilities | BSD-3-Clause | |
| Pillow | pinned at approval time | Decoding dataset images | HPND (MIT-CMU) | Parses untrusted dataset files. Size limits are enforced before decoding. |

## Explicitly rejected

| Candidate | Reason |
|-----------|--------|
| The `image` umbrella crate | Pulls in many formats; ties the engine to one library's abstractions (conflicts with I-2) |
| `tokio` / async runtimes | Not needed; the scheduler uses threads and channels (ADR-0010) |
| ONNX Runtime, TensorRT, ncnn, etc. | These are inference engines. Using one would make ScaleForge a wrapper (O-3). |
| Pretrained perceptual networks (VGG, LPIPS weights) in training | Violates the spirit of O-2. LPIPS is allowed only as an optional, external *evaluation* script with user-supplied weights. |
| Python pickle-based model files | Unsafe deserialisation |
