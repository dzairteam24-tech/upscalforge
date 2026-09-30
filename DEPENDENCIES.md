# Dependency Audit and Register (Phase 2)

Policy (§18–20): no dependency is added until it is audited here and approved
by the project owner. Versions are the latest stable releases on crates.io as
of 2026-09-29. Licences were read from crates.io metadata. Everything must be
compatible with the project's Apache-2.0 licence.

**Current state (2026-09-30): zero third-party crates.** The whole
workspace builds from the Rust standard library alone; `Cargo.lock` lists only
our own crates. Every "MUST REPLACE WITH OUR OWN" item below has been replaced:
our own JSON, PNG, JPEG (encoder and decoder), TIFF, argument parser and
benchmark. **`sha2` was not adopted** either: SHA-256 is our own
implementation (`sf_core::sha256`), checked against the FIPS 180-4 test
vectors. `zune-jpeg` and `image-webp` were not needed as interim decoders:
WebP decoding (lossless VP8L and lossy VP8, RFC 9649 / RFC 6386) is our own
(`sf_image::webp`, 2026-09-30).
Differential checks against independent decoders ran locally with tools
outside the repository. Nothing is installed automatically.

## 1. Classification scheme

Category (§19):
1. **CORE** — implements ScaleForge product logic. The target is zero
   external CORE dependencies.
2. **HW/SYS** — hardware or system interface (OS APIs, GPU driver APIs).
3. **BUILD** — development and build tooling, never shipped in the runtime.
4. **OPTIONAL** — feature-gated, and the product works without it.

Audit verdict (Phase 2 labels): **MUST REMOVE** · **MUST REPLACE WITH OUR OWN
IMPLEMENTATION** · **ACCEPTABLE LOW-LEVEL SYSTEM/HARDWARE INTERFACE** ·
**OPTIONAL** · **NEEDS TECHNICAL REVIEW**.

"Introduces external product logic?" asks whether the dependency would carry
out something that is ScaleForge's job: image enhancement, AI, analysis,
tiling, memory management, or anything similar.

---

## 2. Audit of everything proposed in revision 1

| Dependency | Version / licence | Rev-1 purpose | External product logic? | Verdict | Reasoning |
|------------|------------------|---------------|-------------------------|---------|-----------|
| PyTorch | — / BSD-3-Clause | Training | **Yes** (AI framework) | **MUST REMOVE** | §31. Our own training framework is feasible (requirements §5, ADR-0011). |
| NumPy | — / BSD-3-Clause | Training arrays | Yes (numerics in the training path) | **MUST REMOVE** | Follows from removing Python training. |
| Pillow | — / HPND | Training image decode | No (format interface) | **MUST REMOVE** | Training uses our own image engine. |
| `cudarc` | 0.19.10 / MIT OR Apache-2.0 | CUDA access | Partly (a wrapper layer; also exposes cuBLAS/cuDNN wrappers) | **MUST REMOVE** | Replaced by our own FFI to the **CUDA driver API**. |
| `libloading` | 0.9.0 / ISC | Dynamic library loading | No | **MUST REPLACE WITH OUR OWN** | Three platform calls (`dlopen`/`dlsym`/`dlclose`, `LoadLibraryW`/`GetProcAddress`). Trivial. |
| `rayon` | 1.12.0 / MIT OR Apache-2.0 | Parallel loops | Yes (scheduling) | **MUST REMOVE** | Scheduling is ours (§17). `std::thread::scope` plus our own work splitting. |
| `serde` + `serde_json` | 1.0.229 / 1.0.151, MIT OR Apache-2.0 | JSON (model header, reports, manifests) | No | **MUST REPLACE WITH OUR OWN** | A strict JSON reader/writer is about 600–800 lines, can be fuzzed, and has size and depth limits built in. Parsing untrusted headers in safe Rust has bounded risk. |
| `clap` | 4.6.7 / MIT OR Apache-2.0 | CLI parsing | No | **MUST REPLACE WITH OUR OWN** | The CLI grammar is small (subcommands, typed flags, help). An own parser is realistic and keeps the binary dependency-free. |
| `proptest` | 1.11.0 / MIT OR Apache-2.0 | Property tests | No | **MUST REMOVE** | Our own seeded generators; shrinking is not essential. |
| `criterion` | 0.8.2 / MIT OR Apache-2.0 | Micro-benchmarks | No | **MUST REMOVE** | The benchmark system is a product feature (§33) and is ours. |
| `jpeg-encoder` | 0.7.1 / (MIT OR Apache-2.0) AND IJG | JPEG output | No (format interface) | **MUST REPLACE WITH OUR OWN** | We need our own baseline JPEG encoder anyway, to synthesise compression degradations for training. One implementation serves both. |
| `png` | 0.18.1 / MIT OR Apache-2.0 | PNG decode/encode | No (format interface) | **MUST REPLACE WITH OUR OWN** (runtime); **BUILD** as test oracle | PNG = zlib/DEFLATE + filters + chunks. Realistic in safe Rust. The crate stays a **dev-only differential-testing oracle**. |
| `tiff` | 0.11.3 / MIT | TIFF decode/encode | No (format interface) | **MUST REPLACE WITH OUR OWN** (runtime); **BUILD** as test oracle | We support a defined subset: strips and tiles, uncompressed/LZW/DEFLATE/PackBits, 8/16/32-bit float, BigTIFF. Realistic. Oracle as above. |
| `zune-jpeg` | 0.5.15 / MIT OR Apache-2.0 OR Zlib | JPEG decode | No (format interface) | **OPTIONAL (interim)** → planned replacement | Baseline decode is realistic now. Progressive and arithmetic-coded variants take more work. Interim feature `jpeg-decode-external` until our decoder reaches differential parity on a fuzz corpus; then it becomes a dev-only oracle. |
| `image-webp` | 0.2.4 / MIT OR Apache-2.0 | WebP decode, lossless encode | No (format interface) | **OPTIONAL (interim)** → **NEEDS TECHNICAL REVIEW** | Lossless (VP8L) decode/encode is realistic in-house. Lossy VP8 decode is a substantial codec. Interim optional feature. Lossy WebP *encode* is not offered by pure-Rust crates, so there is no lossy WebP output in v1. |
| `sha2` | 0.11.0 / MIT OR Apache-2.0 | Model and checkpoint integrity | No | **NEEDS TECHNICAL REVIEW** → recommended **keep** | A security primitive. §35 says not to rewrite mature primitives without need, and a future signature scheme (MR-2) will depend on correct hashing. Our own version would be small, but the specification's security rule outweighs that. |
| `ash` | 0.38.0+1.3.281 / MIT OR Apache-2.0 | Vulkan bindings | No (generated declarations only) | **ACCEPTABLE LOW-LEVEL SYSTEM/HARDWARE INTERFACE** | Mechanically generated from the Vulkan registry. Contains no logic. Hand-writing the subset we use is possible, but struct-layout mistakes cause undefined behaviour, so generated bindings are the safer choice. Vulkan backend only (OPTIONAL feature). |
| `cargo-fuzz` / libFuzzer | tool / MIT OR Apache-2.0 (+ LLVM licence) | Fuzzing | No | **BUILD** | Needs a nightly toolchain for fuzz runs only. |

---

## 3. Hardware and system interfaces (not crates)

| Interface | Purpose | Verdict | Notes |
|-----------|---------|---------|-------|
| OS APIs through Rust `std` (files, threads, time) | Everything | ACCEPTABLE | |
| Memory size query (`/proc/meminfo`, `sysctl`, `GlobalMemoryStatusEx`) | Host memory budget | ACCEPTABLE | Called directly through our own small FFI |
| `getrusage` / `GetProcessTimes` | CPU utilisation in benchmarks | ACCEPTABLE | |
| CUDA **driver API** (`libcuda`, loaded at run time) | Device, memory, streams, events, module loading | ACCEPTABLE LOW-LEVEL HW INTERFACE | The lowest supported interface. No CUDA runtime library, cuBLAS or cuDNN. |
| PTX generation for our CUDA kernels | Compiling our own kernels | **NEEDS TECHNICAL REVIEW** | Option A: `nvcc` at build time (BUILD), with PTX embedded and JIT-compiled by the driver. Option B: NVRTC at run time (a runtime compiler library). **Recommended: A** — no extra runtime library. |
| Vulkan loader (`libvulkan` / `vulkan-1.dll`) | Vulkan backend | ACCEPTABLE LOW-LEVEL HW INTERFACE | Uses `VK_EXT_memory_budget` for VRAM budgets |
| GLSL → SPIR-V compiler (`glslc` or `glslangValidator`) | Compiling our own compute shaders | BUILD | SPIR-V is generated at build time. We do not commit generated binaries without their source. |
| NVML (loaded at run time if present) | GPU utilisation in benchmarks | OPTIONAL HW INTERFACE | When it is absent, the field is reported as `null` (§33) |

## 4. Excluded outright (§18)

External upscaling engines and super-resolution implementations; ONNX
Runtime, TensorRT, OpenVINO and other inference engines; cuDNN and cuBLAS; any
external model architecture or weights. **LPIPS** as normally used depends on
pretrained networks, so it is excluded from the system (requirements X-1).
The `image` umbrella crate is excluded because it couples the engine to one
library's abstractions.

## 5. Resulting runtime dependency set, if approved

| Build | Third-party runtime crates |
|-------|----------------------------|
| Default CPU build | none (as built today) |
| + `jpeg-decode-external` (interim) | `zune-jpeg` |
| + `webp-external` (interim) | `image-webp` |
| + `vulkan` | `ash` |
| + `cuda` | none (driver API through our own FFI) |

Development-only: `png`, `tiff`, `zune-jpeg`, `image-webp` (as differential
test oracles) and `cargo-fuzz`.

## 6. Decisions requested from the owner

1. Approve the verdicts above, in particular the **staged codec plan**
   (our own PNG/TIFF/JPEG-encode now; interim external JPEG and WebP decoders
   as optional features).
2. Approve `sha2` as a kept security primitive, or require our own
   implementation.
3. Approve the use of external codec crates as **development-only test
   oracles**.
4. Choose the PTX strategy (recommended: build-time `nvcc`).
