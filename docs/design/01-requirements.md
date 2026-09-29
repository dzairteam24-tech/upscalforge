# Phase 1 — Requirements Analysis

Status: **complete (design phase)**. No production code exists yet.

This document turns the ScaleForge brief into requirements that can be
tested. Each requirement has an ID so that later design documents, tests and
reviews can refer to it.

---

## 1. Product definition

ScaleForge is an independently designed platform for AI image upscaling and
restoration. It has four parts:

1. **Inference engine** — a native library that upscales and restores images
   of any size on CPUs and GPUs.
2. **ScaleForge model family** — our own neural architecture, trained by our
   own training system on data with documented provenance.
3. **Training system** — dataset ingestion, synthetic degradation, training,
   evaluation, versioning and export.
4. **Tooling** — CLI, benchmark harness, quality evaluation, and a public API
   that a future GUI will use.

### 1.1 Originality constraint (applies to everything)

| ID | Requirement |
|----|-------------|
| O-1 | No source code, snippets, tests, docs or comments copied or translated from other projects. |
| O-2 | No external pretrained weights used as, or used to initialise, a ScaleForge model. |
| O-3 | No external upscaling engine used as a backend. |
| O-4 | The model architecture, degradation pipeline, tiling scheme and runtime are designed from general principles. Well-known general building blocks (convolution, residual connections, gating, pixel shuffle, feature modulation) are used; published architectures are not reproduced. |
| O-5 | A third-party library may be used only for well-scoped infrastructure (e.g. a PNG decoder or a GPU API binding). It must first be documented in `DEPENDENCIES.md`. |

---

## 2. Functional requirements

### 2.1 Upscaling and restoration

| ID | Requirement | Acceptance criterion |
|----|-------------|----------------------|
| F-1 | Native scale factors 2x, 4x and 8x | One model file can serve all three; the scale is chosen at run time. |
| F-2 | Restoration of blur, noise, compression artefacts, ringing and oversharpening | Measured on synthetic and real evaluation sets (see Q-*). |
| F-3 | **Faithful** mode | Output is produced only by the model path trained with distortion losses. The detail-synthesis path is not executed (§2.2). |
| F-4 | **Reconstruction** mode with a user-controlled strength `s ∈ [0, 1]` | `s = 0` gives output identical to Faithful mode. Larger `s` monotonically increases the contribution of the synthesis path. |
| F-5 | Degradation-aware processing | The model estimates the input's degradation. The user may override the estimate (e.g. with a noise level). |
| F-6 | Baseline, non-AI resampling | A high-quality analytic resampler is used for alpha channels, as a comparison baseline, and for diagnostics. |

### 2.2 What "Faithful" means (made precise)

"Invents no detail" cannot be guaranteed absolutely, so Faithful mode is defined
by three structural properties:

1. The output comes only from the **base path**, which is trained only with
   distortion losses (pixel, gradient and frequency fidelity). Such losses push
   the output towards the conditional mean rather than towards a plausible
   sample.
2. A **consistency operator** makes the low-frequency content of the output,
   re-degraded to the input resolution, match the input. This bounds colour
   and brightness shifts and large-scale fabrication.
3. The synthesis path does not run, so its weights cannot affect the output.
   This is checked by a test: changing the synthesis weights must leave the
   Faithful output unchanged, bit for bit.

Reconstruction mode adds a learned **synthesis residual** scaled by `s`. This
residual is trained with texture and adversarial objectives. So the difference
between the modes is a difference in computation, not a label.

### 2.3 Image handling

| ID | Requirement |
|----|-------------|
| I-1 | Decode and encode PNG, JPEG, WebP and TIFF. |
| I-2 | The codec layer is pluggable, so AVIF, JPEG XL and OpenEXR can be added without changing the engine. |
| I-3 | 8-bit, 16-bit and 32-bit-float samples; grey, grey+alpha, RGB and RGBA. |
| I-4 | Output bit depth defaults to the input bit depth. |
| I-5 | Alpha channels are preserved and upscaled. |
| I-6 | ICC profiles are preserved. There is no unintended colour shift; see C-*. |
| I-7 | Format limits are checked **before** processing starts. For example, WebP cannot exceed 16383 px per side and JPEG cannot exceed 65535 px. |
| I-8 | Metadata policy is explicit: ICC is kept; EXIF orientation is applied or kept as the user chooses; other metadata is dropped by default. |

### 2.4 Colour management

| ID | Requirement |
|----|-------------|
| C-1 | sRGB input comes out as sRGB with the same encoding. Round-tripping an image through the pipeline with an identity model changes it by at most 1 LSB. |
| C-2 | Images with other RGB profiles (Display P3, Adobe RGB, …) are not clipped to sRGB. |
| C-3 | Linear-light and HDR (float) inputs go through a documented, invertible encoding into the model's working range. |
| C-4 | An unparseable or unsupported profile triggers a warning and a documented fallback. It is never silently misinterpreted. |

### 2.5 Scale of inputs

| ID | Requirement |
|----|-------------|
| S-1 | Small images (e.g. 64×64) are handled without tiling overhead. |
| S-2 | Large images: the whole image does not need to fit in GPU memory. |
| S-3 | Very large images: when the source format allows streaming, the whole image **and the whole output** do not need to fit in host RAM (e.g. 20k×20k in, 8x out = 160k×160k, 25.6 Gpx). |
| S-4 | Host RAM and VRAM use are bounded by budgets that are known before execution. |

### 2.6 Execution

| ID | Requirement |
|----|-------------|
| E-1 | Single-image and batch (many files) processing. |
| E-2 | Tiled inference with **no visible seams**. Defined numerically in Q-3. |
| E-3 | Tile size, overlap, batch size, precision and execution strategy are chosen automatically, and can be overridden. |
| E-4 | Memory needs are estimated before expensive work. If the configuration does not fit, the engine adapts automatically. |
| E-5 | Recovery from out-of-memory: shrink and retry. From device loss: report the error, and fall back to CPU if the user allows it. |
| E-6 | Cancellation and progress reporting through the public API. |
| E-7 | In batch mode, a failure in one file does not abort the batch unless requested. |

### 2.7 GPU

| ID | Requirement |
|----|-------------|
| G-1 | The engine talks only to a backend abstraction. It contains no vendor-specific code. |
| G-2 | Backends are planned for CPU (reference, always available), CUDA and Vulkan. |
| G-3 | The abstraction separates device management, memory allocation, buffers, operations, synchronisation, transfers and execution. |
| G-4 | Devices can be enumerated and selected, and their capabilities queried (memory budget, fp16 support, limits). |

### 2.8 Model runtime

| ID | Requirement |
|----|-------------|
| M-1 | Load, unload, validate and inspect models (metadata). |
| M-2 | Adding a new model version or variant needs no engine code change, as long as it uses the supported operator set. |
| M-3 | Exact memory estimate for a given input shape, batch size and precision. |
| M-4 | Precision selection (fp32, fp16), limited by what the model declares is safe. |
| M-5 | Scale selection within the scales the model declares. |

### 2.9 Training

| ID | Requirement |
|----|-------------|
| T-1 | A dataset manifest records, for every image, its source, licence and hash. Images without an acceptable licence are rejected. |
| T-2 | Dataset validation: decodability, minimum size, duplicate detection, split leakage. |
| T-3 | Synthetic degradation covering blur, noise (including sensor-realistic noise), compression, ringing, oversharpening, resolution loss, and mixed or repeated chains. Parameters are logged per sample. |
| T-4 | Deterministic, seeded data generation. The same seed and config give the same pairs. |
| T-5 | Losses, validation, checkpoints, resumable training and experiment tracking, with no mandatory external service. |
| T-6 | Export to the ScaleForge model format, with metadata that links back to the training run and dataset manifest. |
| T-7 | Numerical parity between the training implementation and the inference runtime is tested. |

### 2.10 CLI, API, GUI readiness, plugins

| ID | Requirement |
|----|-------------|
| A-1 | Commands: `upscale`, `batch`, `models`, `devices`, `benchmark`, `doctor`, plus `eval` for quality evaluation. |
| A-2 | The CLI is a thin client of the public API and contains no processing logic. |
| A-3 | The public API is complete enough that a GUI needs nothing else. This includes progress, cancellation, previews (running on a region), and device and model queries. |
| A-4 | Extension points exist for models, processing stages, backends and codecs, behind validated interfaces. |

### 2.11 Quality and benchmarking

| ID | Requirement |
|----|-------------|
| Q-1 | Full-reference metrics: PSNR (RGB and luma), SSIM, MS-SSIM, and gradient-based fidelity. LPIPS is optional and external, because it needs third-party weights. |
| Q-2 | A documented protocol for blind human A/B evaluation, with a tool that supports it. |
| Q-3 | **Seam criterion:** in exact tiling mode, tiled output equals whole-image output within 1e-5 in fp32 on the CPU backend. In bounded-error mode, the maximum deviation is measured and reported. |
| Q-4 | Regression: each model version has stored metrics on a fixed evaluation set. A new version is compared automatically, with tolerances. |
| Q-5 | The benchmark measures model load time, per-stage time, total time, peak VRAM, transfer bytes and time, throughput, CPU utilisation, and GPU utilisation where it can be measured. Anything that cannot be measured is reported as `null`, never estimated silently. |
| Q-6 | Benchmark reports record the environment: hardware, driver, backend, versions, commit, and configuration. |

---

## 3. Non-functional requirements

Priority order, as given in the brief: **correctness > image quality >
stability > memory efficiency > performance > maintainability > extensibility.**

| ID | Requirement |
|----|-------------|
| N-1 | CPU backend: deterministic output for identical inputs and configuration. GPU backends: deterministic kernels (no atomics in reductions) unless a documented fast mode is chosen. |
| N-2 | Security: the malformed input, malicious model and resource exhaustion threats in §5 are mitigated. |
| N-3 | Portability: the engine runs on Linux, Windows and macOS (CPU). GPU backends run where their APIs exist. |
| N-4 | Every major stage can be tested on its own. |
| N-5 | Optimisations are accepted only with before/after measurements. |
| N-6 | Minimal dependency footprint. Each dependency is justified (O-5). |

---

## 4. Constraints and facts about the current environment

These facts limit what can be **validated** in this repository today, and they
shape the plan.

| Fact | Consequence |
|------|-------------|
| No GPU in the development container. | The CUDA and Vulkan backends can be written but **cannot be executed or validated here**. They stay marked *unvalidated* until run on real hardware. The CPU backend is the reference, and every test that must pass in CI runs on it. |
| PyTorch is not installed, and dependencies must not be installed automatically. | The training system cannot run until the user approves its dependencies. |
| No pretrained weights are allowed (O-2). | Model quality depends entirely on our own training compute and data. A model trained on CPU in this environment can **only validate the pipeline**; it will not be a production-quality model. This will be stated plainly wherever the model is described. |
| Dataset licensing. | Many widely used super-resolution research datasets are licensed for non-commercial research only. No dataset is bundled. The manifest system (T-1) makes licensing explicit and enforced. |
| Toolchain present: Rust 1.94, GCC 13, CMake 3.28, Python 3.11. | This informs the language choice (ADR-0001). |

---

## 5. Threat model summary (security requirements)

| Threat | Requirement |
|--------|-------------|
| Malformed or malicious image files (decoder bugs, decompression bombs) | Memory-safe decoders. Dimension, pixel-count and allocation limits are checked before allocating. Decoders are fuzzed. |
| Malicious model files | The model format is pure data (no pickle, no code). Every offset and size is bounds-checked. There is an operator whitelist, and the graph is validated (acyclic, shapes inferable, tensor sizes limited). Hashes are verified. |
| Path traversal in batch mode | Output names are derived, never taken raw from untrusted metadata. Outputs are confined to the output directory. No overwriting unless explicitly allowed. Symlink policy is explicit. |
| Resource exhaustion | Host and device memory budgets; optional wall-time limits; bounded queues. |
| GPU failures (OOM, device lost, driver timeout) | Typed errors; bounded retry with smaller work units; optional CPU fallback; no undefined state after an error. |
| Untrusted plugins | No dynamic loading of native code in v1 (see ADR-0008). |

---

## 6. Explicit non-goals for v1

- Video upscaling (temporal consistency is a different problem).
- Face-specific or text-specific restoration models.
- Arbitrary non-integer scale factors (these can later be done by native upscaling followed by analytic downscaling).
- Distributed or multi-GPU execution of a single image. Using several GPUs for several images in a batch can come later.
- Cloud service or web UI.
