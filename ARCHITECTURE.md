# ScaleForge Architecture (revision 2)

Status: **Phase 3 proposal, revised after the Phase 4 critical review**
([`docs/design/04-architecture-review.md`](docs/design/04-architecture-review.md)).
Requirement IDs refer to
[`docs/design/01-requirements.md`](docs/design/01-requirements.md). Capability
classifications are in
[`docs/design/02-capability-feasibility.md`](docs/design/02-capability-feasibility.md).
Dependency verdicts are in [`DEPENDENCIES.md`](DEPENDENCIES.md). Decisions
are recorded in [`docs/adr/`](docs/adr/).

**Nothing described here is implemented.** See §27.

---

## 1. Invariants

The whole design rests on four invariants.

1. **Locality.** Everything computed per tile is local, with a receptive
   field known before execution. Anything global is split into an *analysis*
   step over a bounded summary, which produces parameters, vectors or
   low-resolution spatial maps, followed by a local *application* step. This
   gives exact seam-free tiling, streaming beyond RAM, exact memory
   prediction, and region previews identical to the full render.
2. **Model as data.** A model is a declarative graph over our small, versioned
   operator set, plus weights. It is never code. The engine is therefore
   model-agnostic, every backend only has to implement the operator set,
   memory can be planned statically, and loading a model is safe.
3. **Budgets.** Nothing large is allocated without first asking the host
   memory manager or the VRAM manager. Plans are checked against budgets
   before execution starts.
4. **Explainability.** Every processing parameter has a recorded origin: a
   user setting, a named policy rule with its evidence, or a documented
   default. There are no hidden decisions (§14).

---

## 2. One language, one runtime (ADR-0011, supersedes ADR-0001/0007)

Everything is written in **Rust**: engine, GPU backends, image engine,
analysis, training framework, CLI. Training runs on the **same graph IR,
operator set, backends and memory planner** as inference, extended with
gradient operators. As a result:

- no AI framework in any part of the product (D-3);
- no second implementation of every operator, and no parity tests between
  languages (this resolves revision-1 review item R-11);
- training-time validation runs the real inference engine.

The feasibility argument is in requirements §5.

---

## 3. System map

```
     CLI            future GUI           future bindings (C ABI)
      └────────────────┬───────────────────────┘
                       ▼
┌──────────────────────────── Public API (`scaleforge`) ───────────────────────────────┐
│ Engine · Session(image) · JobRequest · Controls · Variants · Report · Progress · Cancel │
├──────────────────────────────── Engine (`scaleforge`) ────────────────────────────────┤
│ Summary pass ─► Analysis ─► Strategy (Auto/Manual) ─► Predictive QC ─► Plan            │
│   ─► Tile scheduler ─► Region executor ─► QC accumulation ─► Post stages ─► Sink       │
│ Model runtime · VRAM manager · Host memory manager · Auto-tuner · Tuning cache          │
│ Instrumentation · Benchmark · Batch                                                     │
├───────────────┬──────────────────┬──────────────────┬───────────────┬─────────────────┤
│ sf-analysis   │ sf-image         │ sf-graph         │ sf-compute    │ sf-train        │
│ estimators,   │ buffers, own     │ tensors, op set, │ device        │ datasets,       │
│ QC detectors, │ codecs, colour,  │ IR, validation,  │ abstraction + │ training loop,  │
│ full-ref      │ resampling,      │ analyses, memory │ CPU backend   │ losses, SF-Net  │
│ metrics       │ summary builder  │ plan, autodiff,  ├───────┬───────┤ definition,     │
│               │                  │ .sfm / .sfck     │ CUDA  │Vulkan │ export, eval    │
│               │                  │                  │       │       ├─────────────────┤
│               │                  │                  │       │       │ sf-degrade      │
├───────────────┴──────────────────┴──────────────────┴───────┴───────┴─────────────────┤
│ sf-core: errors, limits, geometry, dtypes, JSON, cancellation, progress, logging        │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

| Crate | Responsibility | Why it is a separate crate |
|-------|----------------|---------------------------|
| `sf-core` | Error taxonomy, `Limits`, checked geometry, dtypes, own strict JSON reader/writer, deterministic RNG, cancellation, progress (a logging trait is added when first needed) | Shared by every crate; no dependencies |
| `sf-graph` | **Tensor and graph system**: tensor descriptors, operator set (forward and gradient), graph IR, role-based validation, shape inference, locality and required-region analysis, subgraph selection, memory planning, autodiff transform, `.sfm` model and `.sfck` checkpoint containers | Pure logic with no device. Used by the engine, backends and training |
| `sf-compute` | Device abstraction + **CPU reference backend** (strict mode, f64 test path) | The CPU backend is not optional; it is the reference for every other backend |
| `sf-compute-cuda`, `sf-compute-vulkan` | GPU backends | Optional features that isolate hardware interfaces |
| `sf-image` | Pixel buffers, region sources and sinks, own codecs, colour, resampling, analysis-summary builder | Used by the engine, analysis, training and evaluation |
| `sf-analysis` | No-reference estimators (analysis), QC detectors, full-reference metrics | Shared measurement toolkit for runtime analysis, QC and evaluation |
| `sf-degrade` | Degradation grammar and operators | Used by training, by evaluation-set generation, **and** by estimator calibration and tests |
| `sf-train` | Dataset manifests and validation, SF-Net and discriminator definitions, losses, training loop, checkpoints, tracking, export, regression evaluation | Training is a separate product surface. The engine only reads `.sfm` files |
| `scaleforge` | Engine and public API | One crate: its modules are coupled through plans and budgets and have one consumer |
| `scaleforge-cli` | CLI | Presentation only |

---

## 4. Processing pipeline (§4, §27)

```
Input ─► Validation ─► Decode ─► Colour mgmt ─► Summary pass ─► Analysis ─► Strategy
      ─► Predictive QC ─► Preprocess ─► Tiling ─► AI inference ─► Reconstruction (core placement)
      ─► QC accumulation ─► Post stages (tone/colour, sharpening) ─► Colour conversion ─► Encode ─► Output
```

| Stage | Component | Kind (ADR-0004) | Independent test |
|-------|-----------|-----------------|------------------|
| Validation | `sf-image` probe, job planner | global, header only | malformed headers, limit tests |
| Decode | `RegionSource` per codec | streaming where the format allows | round-trips, differential tests vs. oracles, fuzzing |
| Colour mgmt | `sf-image::color` | local, halo 0 | round-trip ≤ 1 LSB |
| Summary pass | `sf-image::summary` | one bounded streaming pass | deterministic summaries |
| Analysis | `sf-analysis` | global over the summary | estimator accuracy on synthetic data |
| Strategy | `scaleforge::strategy` | global, pure function | decision tables and provenance |
| Predictive QC | engine + `sf-analysis::qc` | runs on summary patches | QC detector tests |
| Preprocess | pack tensors, alpha split, canonical padding | local | fixtures |
| Tiling | `scaleforge::tiling` | plan | property tests |
| AI inference | runtime, `main` graph | local, halo = derived radius | seam criterion, reference outputs |
| Reconstruction | core placement | local | seam criterion |
| QC accumulation | `sf-analysis::qc` per tile | local, statistics merged | detector tests |
| Post stages | tone/colour, sharpening | analysis → local | known-value tests |
| Colour conversion | inverse working encoding | local | round-trip |
| Encode | `RegionSink` | streaming where possible | round-trip |

---

## 5. Tensor and graph system (`sf-graph`) (§17, D-1)

### 5.1 Tensors
`TensorDesc { shape: [N, C, H, W] or [N, C], dtype: F32 | F16 | F64 (CPU test only), layout }`.
Storage belongs to backends (`sf-compute`). The graph layer handles only
descriptors. The canonical layout is NCHW, and backends may choose internal
layouts (§6).

### 5.2 Operator set v1 (provisional; frozen at the end of Phase 13)

| Group | Operators |
|-------|-----------|
| Spatial, local | `conv2d` (k ∈ {1,3,5,7}; stride 1/2; groups 1 or C; zero padding) · `avg_pool2` · `upsample_nearest2` · `pixel_shuffle2` / `pixel_unshuffle2` · `fixed_filter` (separable kernel from a named, versioned **filter family** (`gaussian`, `windowed_sinc_lowpass`, `area`, `analytic_up2`) and a scalar parameter bound at plan time; optional ×2 up/down; the graph declares the maximum kernel radius) — the kernel is synthesised by the backend from family + parameter, so models stay pure data · `crop` (planner-inserted only) |
| Element-wise | `add` `sub` `mul` `affine_channel` (per-channel scale/shift from vectors) · `activation` {GELU-tanh, SiLU, sigmoid, leaky-ReLU, identity} · `clamp` · `scale_scalar` |
| Channel | `concat_channels` `slice_channels` |
| Vector | `linear` · `global_mean` (spatial → vector) · `reduce_mean` / `reduce_sum` |
| Training only | Gradient operators generated by autodiff (`conv2d_grad_input`, `conv2d_grad_weight`, activation gradients, and adjoints of pooling and resampling), losses built from the operators above, `adamw_update` |

### 5.3 Graph roles and validation
Every graph declares a role. The validator enforces:

| Role | Rule |
|------|------|
| `main` (per tile) | **No spatial reduction on any path that reaches a spatial output.** Reductions are allowed only on branches that end in *statistics outputs* (used by QC, §11), and those branches must start from a `crop` to the tile core, so that overlapping windows are not counted twice. Vector inputs are allowed. |
| `context` (analysis) | All inference operators, including spatial reductions. Input size is bounded. |
| `training` | Everything |

This path-based rule is exactly what tile exactness needs. A blanket ban on
reductions would also forbid per-tile QC statistics, which do not affect
pixels (review item R2-6).

Further checks: acyclic; all inputs defined; attributes within the operator
contract; shape inference succeeds; tensor and parameter limits respected.

### 5.4 Static analyses
- **Shape inference** for any conforming input.
- **Locality**: the receptive radius *r* and alignment *a* are derived by
  walking the graph. Kernel sizes set at plan time (e.g. the consistency
  filter) enter through their declared upper bound, and the exact value is
  computed at plan time.
- **Required regions** + `crop` insertion: each tensor is computed only over
  the region its consumers need. This keeps the halo cost in low-resolution
  compute.
- **Subgraph selection** for (scale, mode, enabled inputs). For example,
  Faithful mode drops the synthesis path.
- **Memory planning**: liveness analysis and offset assignment in one arena.
  Exact peak bytes as a function of (H, W, N, precision), affine in H·W for
  `main` graphs.
- **Autodiff** (training): reverse-mode transformation of a `training` graph
  into forward + backward + update graphs. It is checked by finite-difference
  tests in f64 on the CPU backend.

### 5.5 Containers (ADR-0002)
`.sfm` (model) and `.sfck` (checkpoint) share one layout: magic, version, a
length-prefixed JSON header parsed by our own strict parser (size and depth
limits), and a 64-byte-aligned tensor blob with a SHA-256 per tensor and for
the whole file. Everything is validated before any allocation proportional to
declared sizes. No executable content of any kind.

---

## 6. GPU execution layer (`sf-compute`) (§22, ADR-0003)

The abstraction sits at the **graph-execution level**. The engine hands a
backend a planned graph; the backend compiles it (choosing kernels, fusions
and layouts). The six concerns are separate:

```text
Backend     enumerate() / open(device)                               — device management
Device      info(), memory_status(), allocate(bytes, kind)           — memory allocation / buffers
            memory_requirement(graph, shape, precision)  (pure)
            compile(graph, precision) -> Executable                  — compute operations
Queue       upload / download                                        — transfers
            execute(executable, bindings)                            — execution
            signal() -> Event, wait(event), synchronize()            — synchronisation
```

- Everything on a `Queue` is asynchronous by contract. The **CPU backend
  follows the same contract**, with separate "device" allocations and
  explicit copies. Its **strict mode** (on in tests) detects host access
  before an event has signalled and freeing of in-flight buffers.
- **CPU backend**: our own kernels (direct and blocked convolution,
  depthwise, GEMM, element-wise), parallel over rows with `std::thread::scope`.
  Deterministic. f64 support is used only for gradient checking.
- **CUDA backend**: our own FFI to the **driver API** (loaded at run time),
  and our own CUDA C kernels compiled to PTX at build time and JIT-loaded by
  the driver. No CUDA runtime library, cuBLAS or cuDNN.
- **Vulkan backend**: Vulkan 1.2 through generated bindings, our own GLSL
  compute shaders compiled to SPIR-V at build time, and
  `VK_EXT_memory_budget` for VRAM budgets.
- GPU backends are **INCOMPLETE (unvalidated)** until run on hardware
  (requirements X-9).

---

## 7. Memory and VRAM (§23, ADR-0009)

**VRAM manager (per device).**
- Budget = min(device-reported budget, user limit) − safety reserve. The
  reserve is provisional and later calibrated from measurements.
- Tagged pools: `weights` (resident per model and precision), `activations`
  (one arena sized from the plan), `io` (staging, doubled when pipelined),
  `workspace` (reported by the executable), `training` (gradients and
  optimiser state).
- **Fragmentation** is prevented by design: a few large allocations
  sub-allocated at planned offsets. Arenas only grow during a job and shrink
  between jobs.
- **Pre-flight** `fits(plan) -> Fit | Shortfall(bytes)` before allocating.
  Runtime out-of-memory errors lead to a bounded shrink → re-plan → retry of
  the current band. This is safe mid-image because tiling is exact.

**Host memory manager.** A process-wide budget charged by pixel buffers, band
caches, spatial maps, variant caches and sink buffers. A job's peak host memory
is computed from its plan *before* decoding.

---

## 8. Image engine (`sf-image`)

### 8.1 Buffers, sources, sinks
`PixelBuffer` has checked construction and is charged to the host memory
manager. `RegionSource` (random access or sequential bands, `rewind`) and
`RegionSink` (in-order bands) allow streaming. Sequential sources are wrapped
in a band cache (tile height + 2 × halo rows). Formats that need a full decode
are checked against the budget before decoding.

### 8.2 Codecs (staged plan in `DEPENDENCIES.md`)
Each codec sits behind `Codec { probe, open_source, open_sink, capabilities,
limits }` in a `CodecRegistry`.

| Format | Implementation | Streaming |
|--------|---------------|-----------|
| PNG | **Own** (DEFLATE/zlib, filters, chunks, Adam7 decode, ICC/`gAMA`/`cHRM`/`sRGB`/`cICP` chunks) | Rows (non-interlaced) |
| TIFF | **Own** subset: strips and tiles; none/LZW/DEFLATE/PackBits; 8/16-bit integer and 32-bit float; BigTIFF write | Tiled: random access. Stripped: bands |
| JPEG encode | **Own** baseline encoder (also used by `sf-degrade`) | Rows (MCU bands) |
| JPEG decode | Own baseline first; progressive via the interim optional external decoder until our own reaches parity | Baseline: bands. Progressive: full |
| WebP | Interim optional external decoder; lossless encode | Full buffer; size limit 16383 px checked at validation |
| AVIF / JPEG XL / OpenEXR | Future `Codec` implementations | — |

Limits (dimensions, pixels, decoded bytes, chunk sizes, ICC size) are enforced
before any decoder allocates. All codecs are fuzzed and differentially tested
against development-only oracles.

### 8.3 Colour management (ADR-0005)
- Gamma-encoded RGB and grey are processed in their **native encoding**, and
  the ICC profile passes through byte for byte. This avoids gamut clipping.
- A minimal ICC reader *classifies* profiles (transfer: gamma-like, linear or
  unknown; primaries from `rXYZ/gXYZ/bXYZ`) for analysis and linear-light
  operations.
- Linear and HDR data (values > 1) go through a documented invertible
  working encoding (a log-type curve). The HDR path is experimental until
  evaluated.
- Operations that must happen in linear light (white balance, exposure) use
  the classified transfer function. If the transfer is unknown, those stages
  are refused with an explanation. Nothing is silently guessed.
- EXIF orientation is applied and then reset. Location metadata is stripped by
  default (MR-1). Alpha is split off, upscaled with the analytic resampler, and
  merged back. Colour under transparent pixels is filled before inference.
  CMYK is rejected in v1.

### 8.4 Resampling and filters
Our own separable windowed-sinc, area and Gaussian filters. They are used for
alpha, thumbnails, the analytic base upsample, consistency kernels, and the
analysis filters.

### 8.5 Summary pass (the only whole-image read before tiling)
One streaming pass builds the `AnalysisSummary`:
- a **patch mosaic**: K native-resolution patches on a deterministic grid (for
  noise, compression, blur and predictive QC);
- a **thumbnail**: area-downsampled to ≤ 512 px (for exposure, colour,
  composition, face detection at coarse scale);
- **exact whole-image statistics**: per-channel histograms, clipping counts,
  gradient-magnitude histogram;
- **format evidence**: JPEG quantisation tables, chroma subsampling, and
  gamma/ICC chunks read from the file header.

A sequential source is therefore decoded twice (summary pass, then tile
pass). This cost is reported. Non-rewindable inputs are spooled to a
temporary file, within the budget.

---

## 9. ScaleForge model: SF-Net (Phase 13; details in MODEL.md then)

```
AnalysisSummary.patches ─► context graph (learned degradation estimator) ─► d_learned
AnalysisReport (classical) ─► d_classical        user overrides ─► d_user
                    d = fuse(d_user ▷ d_classical, d_learned)   (fusion rule documented, reported)
                    c_b = embed(d)                      c_s = embed(d, s)

inputs per tile (all local): LR tile + halo · strength map m (Balanced/Reconstruction)
                             · consistency weight map w · model-declared spatial conditions (none in v1)

LR ─► stem ─► [Dual-Rate Block × N, modulated by c_b] ─► body features
                  │
     ┌────────────┴───────────────────────────────┐
     ▼ base path (always)                          ▼ synthesis path (Balanced / Reconstruction)
  ×1 head │ ×2 ─► ×2 ─► ×2 stages               texture trunk (modulated by c_s)
  residuals on the fixed analytic upsample       ─► matching ×1 / ×2 stages ─► R
     ▼                                              │
     B_k (k = scale)          Y = B + s · m ⊙ R ◄───┘
                                      ▼
            consistency:  Y ← Y + w ⊙ U( LP_fc( x − D_d(Y) ) )
   D_d = downsample ∘ blur(estimated blur width) · LP_fc = low-pass at cutoff fc · w = weight map ∈ [0,1]
```

- **The degradation descriptor `d` is physical** (U-3): noise σ and signal
  dependence, chroma noise ratio, blur width, compression strength, ringing
  and oversharpening amount, effective-resolution factor. During training the
  network is conditioned on the **true** parameters from `sf-degrade`, with
  controlled perturbation for robustness. So a user override such as "denoise
  strength" is a real, trained control.
- **Dual-Rate Block**: a full-rate local stream (depthwise 3×3 → gated
  pointwise expansion → projection) and a half-rate context stream in
  selected blocks, with pointwise exchange between them. Per-channel
  modulation comes from `c_b`. The half-rate blocks let us enforce a
  **receptive-radius budget**. The budget is provisional: ≤ 32 LR px for the
  network plus ≤ 16 LR px for the consistency step, 48 in total. The build
  fails if it is exceeded (R2-4).
- **Spatial conditions are declared by the model**, not built into the engine.
  SF-Net v1 declares none. A later face-aware version declares a `face_mask`
  input, and the engine supplies it through the same spatial-map mechanism
  used for `m` and `w` (R2-3).
- **Scales**: one shared body, a ×1 head and three ×2 stages (F-1'). Channel
  counts shrink at the higher-resolution stages. Lower scales skip the later
  stages.
- **Split conditioning**: `s` never reaches the body or the base path, so
  Faithful output cannot depend on it.
- **Staged training**: Stage A trains stem, body, base path and estimator
  with distortion losses. Stage B **freezes Stage A** and trains the synthesis
  path over a range of sampled `s`. Stage F (later) adds face conditioning.
- **Consistency step**: fixed operators whose kernels are derived at plan
  time from `d` and the mode. Its radius enters the locality analysis.
  - `fc` = min(noise limit, blur-conditioning limit, mode limit). The **noise
    limit** excludes bands where the measured noise dominates, so input noise
    is not forced back into the output. The **blur-conditioning limit**
    restricts correction to frequencies where the estimated blur's transfer is
    ≥ 0.5. Below that, correcting would amplify errors in the blur estimate:
    ringing when blur is overestimated, softening when it is underestimated
    (R2-1).
  - Correction is damped (`w ≤ 1`).
  - **The consistency step is part of the training graph**, with `fc` and
    `w` sampled over their ranges. The network therefore learns *with* it
    rather than having it bolted on afterwards (R2-2).
- **Unified vs. specialised (§7, MR-6)**: one conditioned architecture serves
  general, noisy, compressed, blurred and low-resolution inputs. A specialised
  model is created only if a defined experiment shows the unified model
  falling short on a category's evaluation set at equal budget.

---

## 10. Reconstruction modes (§9, F-3'/F-4'/F-4''/F-7)

| | Faithful | Balanced | Reconstruction |
|--|----------|----------|----------------|
| Synthesis path | **not executed** | executed | executed |
| Strength `s` | 0 | from policy, **capped** (cap provisional, calibrated) | user, 0…1 |
| Local strength map `m` | — | from predictive/per-tile QC | from QC (lenient thresholds) |
| Consistency band `fc` | widest band the noise allows | same as Faithful | lower band (colour and large structure only) |
| QC thresholds | strict | strict on consistency | lenient on detail, strict on colour shift |

Each row is a real difference in computation, and each is covered by a test.

---

## 11. Quality control (§11)

QC detectors are **graph branches** built by `sf-analysis::qc`. They are
appended to the `main` graph as statistics outputs (§5.3), run on the same
device as the model, and yield per-core statistics. The host merges these into
a coarse QC map and a report. The full-resolution output is never re-scanned
on the CPU (R2-6). Rule: **bounded-size data (the summary) is analysed on the
host in Rust; full-resolution per-tile data is analysed as graph operators.**

| Symptom | Detector |
|---------|----------|
| Hallucination / structure loss | Consistency residual ‖LP(x − D_d(Y))‖ at a band above `fc` |
| Colour shift | Difference of low-pass channel means (in linear light where the transfer is known) |
| Haloing / oversharpening | Overshoot beyond local extremes across strong edges, relative to the input's own overshoot |
| Repeated textures | Peaks of normalised autocorrelation of `R` outside the origin. Runs **on the host, on predictive-QC patches only**: large-lag correlation is not a local operator (R2-7) |
| Tile seams | Exact mode: guaranteed by construction and tested. Bounded mode: discontinuity statistics along core boundaries |
| Unnatural edges | Edge-width distribution anomalies (RES) |
| Facial distortion | Landmark drift between input and output (needs FA-1; INCOMPLETE until then) |

Automatic adjustment (QC-3), in two steps that preserve locality:
1. **Predictive QC**: before the full run, the planned configuration runs on
   the summary's native-resolution patches. Their QC scores adjust the global
   `s` (Balanced) and seed the strength map `m`.
2. **Per-tile QC** during the run is recorded and reported.
3. **Corrective re-render** of flagged regions (a locally lowered `m`, plus
   re-rendering of tiles whose halo overlaps the change) is **postponed to
   Phase 17 as an optional feature**. It works only with random-access sinks,
   and its complexity must first be justified by evidence that predictive QC
   is insufficient (R2-8).

Every adjustment appears in the job report.

---

## 12. Tiling engine (§24, ADR-0004)

- **Exact mode (default).** Halo = derived radius `r` (rounded up to the
  alignment `a`), using the model's own border semantics. The image is padded
  once, globally, to a multiple of `a`. The image is partitioned into
  **non-overlapping cores**, each written once. Each core has a **uniform
  compute window**, shifted inward at the edges. Tiles run in row-major band
  order. Tiled output equals whole-image output to within floating-point
  operation order. Seams cannot occur.
- **Bounded-error mode** (opt-in, or chosen by the auto-tuner under
  pressure): halo < `r` with cosine blending. The error is **measured** per
  model and halo, never assumed.
- Spatial maps (`m`, `w`, and model-declared conditions such as `face_mask`) are cropped per compute window, like the image.

---

## 13. Scheduler (§26, ADR-0010)

- **The synchronous executor is the reference**: fetch → preprocess → upload
  → execute → download → QC and post → write.
- A **pipelined executor** (three threads, bounded channels of depth 2,
  double-buffered staging, a reorder buffer before the sink) is enabled per
  device only when calibration measures a gain.
- One device executor per device. Jobs queue at tile granularity. Cancellation
  is checked between tiles. Progress events are emitted per tile.

---

## 14. Analysis, strategy, Auto mode and manual control (§5, §6, §14, §15)

**Analysis engine (`sf-analysis::estimate`)** produces an `AnalysisReport`.
Each field has a value, an uncertainty, the estimator's name and version, and
a validity flag. v1 estimators are classical and explainable:

| Quantity | Estimator (v1) |
|----------|----------------|
| Noise σ, signal dependence, chroma ratio | Robust dispersion of a fine high-pass residual in low-texture patch blocks, binned by intensity |
| Compression | JPEG quantisation tables when available; otherwise blockiness on the detected 8-px grid phase |
| Blur / sharpness / edge quality | Edge-profile width along strong edges; radial spectral fall-off |
| Effective resolution | Frequency at which the spectrum meets the noise floor → "already upsampled by ×k" |
| Motion vs. defocus | Directional anisotropy of edge widths and spectrum (RES; `unavailable` until validated) |
| Ringing / oversharpening | Overshoot and oscillation around edges |
| Texture density | Share of blocks with variance above the noise-adjusted threshold |
| Exposure / dynamic range / contrast | Exact histograms: percentiles, clipping, RMS contrast |
| Colour characteristics | Grey-world and bright-region white estimates, saturation statistics |
| Face presence | Our own detector (INCOMPLETE until trained) → `unavailable` |
| Severity | Calibrated combination per category (calibrated on `sf-degrade` data) |

The learned estimator (context graph) adds `d_learned`. Fusion is a documented
rule, and both inputs are reported.

**Strategy engine (`scaleforge::strategy`)** is a pure function:
`(AnalysisReport, JobRequest, ModelCatalog, DeviceInfo) → ProcessingPlan`.
Decisions follow a **versioned rule policy**. The rule logic is code; its
thresholds live in a versioned calibration file produced from synthetic
evaluations. Every decision records `{value, source, rule id, evidence}`.

**Manual controls → real parameters (U-5)**:

| Control | Parameter |
|---------|-----------|
| Model | model selection from the catalogue (validated against capabilities) |
| Scale | subgraph selection (1/2/4/8; > 8 by composition) |
| Mode | §10 |
| Reconstruction strength / texture reconstruction | `s`, strength map `m` |
| Denoise strength | noise components of `d` fed to `c_b` |
| Deblur strength | blur component of `d` (conditioning, and `D_d` in consistency) |
| Fidelity | consistency band `fc` and weight `w` |
| Face enhancement | `face_mask` condition and consistency weight `w` in face regions (INCOMPLETE until FA-1 and a face-aware model exist) |
| Sharpening | classical post-sharpening amount (with overshoot limit) |
| Colour processing | tone/colour stage enable and parameters |
| Precision / tile strategy | runtime and tiling overrides |

---

## 15. Auto-tuner (§25, ADR-0009)

1. **Analytic**: for each allowed precision, query `memory_requirement` at two
   shapes (memory is affine), solve for the largest tile that fits, compute the
   halo overhead, and rank candidates with a FLOP-based cost model.
2. **Measured**: `scaleforge benchmark --calibrate` times the candidates on the
   device. Results go to the **tuning cache**, keyed by (backend, device,
   driver, model hash, precision, scale, mode).
3. Measured data takes precedence. The decision and its reason are recorded in
   the report. All constants in step 1 are labelled provisional.

---

## 16. Region processing, previews and variants (§12)

- `Session::open(input)` runs the summary pass and analysis once.
  `Session::render(region, controls)` runs exact tiling restricted to the
  region, using the **whole-image** analysis context, so previews match the
  final render (P-1).
- **Source access**: a session over a sequential source larger than the
  budget spills decoded pixels once into a temporary raw tile cache, so that
  repeated region renders do not re-decode from the start (R2-9).
- **Variant cache**: for a region, `B` (base output) and `R` (synthesis
  residual) are cached as f16, charged to the host budget. The region size is
  limited so that the cache fits. Changing `s`, `m`, or switching between Balanced and
  Reconstruction only recomputes `Y = B + s·m⊙R` and the consistency step
  (cheap and local). Faithful ↔ Balanced reuses `B`. Changing the model or `d`
  recomputes. Before/after is the source crop plus the output crop.
- Face-region preview uses the face regions as preset regions (depends on
  FA-1).

---

## 17. Face-aware subsystem (§10) — INCOMPLETE until trained

- **Detection**: our own small convolutional detector, a `context`-role graph
  run on the thumbnail pyramid and, when faces are small, on native patches.
  Candidate boxes are merged by non-maximum suppression (global, over a sparse
  list). This yields regions, confidence and landmarks.
- **Integration**: regions become a smooth soft **face mask** at reduced
  resolution. It is supplied to face-aware model versions as their declared
  `face_mask` spatial condition (local, tile-exact), and it raises the
  consistency weight `w` inside faces. There is no pasting and no reference
  faces (FA-2, FA-3). No engine change is needed when the face-aware model
  arrives; it is a new `.sfm` version.
- **QC**: landmark drift between input and output crops (FA-4).
- **Data and ethics**: consented, licensed face data only. Evaluation across
  demographic groups is mandatory before release (FA-5).
- The spatial-map mechanism is built with QC (§11) before any face model
  exists. The detector and face training come after the core model
  (feasibility #10).

---

## 18. Model ecosystem and runtime (§16)

`.sfm` metadata: architecture ID and hash, version, capabilities (tasks),
scales, modes, precisions with measured fp16 error bounds, **derived**
receptive field and alignment (re-derived on load; a mismatch is rejected),
memory coefficients per precision (re-derived on load), training run ID /
steps / configuration hash, dataset-manifest hash and licence summary, model
licence, and integrity hashes.

```text
ModelCatalog::scan(dirs) → validated entries (bad files are reported, not fatal)
ModelHandle::load(path, &Limits) · metadata() · capabilities()
ModelHandle::prepare(&Device, Variant{scale, mode, precision, inputs}, TileShape) → PreparedModel
PreparedModel::memory() · run(queue, bindings, scalars)
```

Weights are uploaded once per (device, precision) and shared by variants. A
new model version or family needs **no engine change** if it uses the
operator set.

---

## 19. Training system (`sf-train`, `sf-degrade`) (§30, ADR-0011)

```
manifest (JSONL: path, sha256, source, licence, attribution, consent (faces), split)
 → validation (licence allow-list, decode, minimum size, exact and perceptual-hash
   duplicates, evaluation-set exclusion MR-5)
 → content-aware crop sampler inside a larger context window
 → degradation program (sf-degrade; seeded; parameters logged)
 → (LR, HR, true d) → training graph (SF-Net + losses) → autodiff → AdamW
 → validation with the real inference engine → checkpoints (.sfck) → tracking → export (.sfm)
```

- **Degradation grammar (our own)**: *capture* (optical blur: defocus disc,
  Gaussian, anisotropic, motion path; sensor-resolution sampling; Poisson–
  Gaussian noise in linear light; optional mosaic and demosaic) →
  *in-camera* (tone curve, noise reduction, sharpening and oversharpening,
  quantisation) → *distribution* (one or more rounds of resize with various
  kernels including aliasing ones, our own JPEG encoder with chroma
  subsampling, re-sharpening, band-limit ringing). Every sampled parameter is
  logged and becomes the true `d`.
- **Context windows**: the summary operator runs on a degraded window larger
  than the crop, which mirrors inference.
- **Dataset paths** in manifests are resolved inside a declared dataset root.
  Absolute paths and `..` segments are rejected.
- **Losses**: Stage A uses Charbonnier, gradient, band-decomposition
  (Laplacian-pyramid bands through fixed filters, so no FFT operator is
  needed), consistency, and descriptor regression. Stage B uses our own
  discriminator (trained from scratch), hinge adversarial loss, feature
  matching and band statistics. **No pretrained networks anywhere.**
- **Reproducibility**: seeds derive from (global seed, epoch, index). Each run
  directory holds the resolved configuration, git commit, environment report,
  manifest hash, JSONL metrics and checkpoints. The CPU backend is
  deterministic.
- **Versioning**: `sf-<size>-<major>.<minor>`; exports link to their run and
  manifest.
- Models trained without GPU compute are labelled **pipeline-validation only**
  in their metadata.

---

## 20. Quality evaluation (§32)

- Full-reference metrics (`sf-analysis::metrics`): PSNR (RGB and Y), SSIM,
  MS-SSIM, gradient fidelity, and the consistency residual. No single metric
  decides.
- Perceptual metric: a learned metric of our own needs human-judgement data
  (RES). LPIPS is excluded (requirements X-1).
- Human evaluation: `scaleforge eval ab` creates blinded, randomised pairs and
  records ratings. The protocol is documented in BENCHMARKS.md.
- **Regression**: governed evaluation sets (manifests plus fixed degradation
  seeds) per capability category. Metrics are stored per model version, and
  comparison uses per-metric tolerances.

## 21. Benchmarking (§33)

Warm-up plus N repetitions; medians and percentiles; per-stage timings from
engine instrumentation; peak VRAM from tagged accounting plus the
device-reported figure when available; transfer bytes and times from the
`Queue`; CPU utilisation from process CPU time ÷ wall time; GPU utilisation
from NVML when present, otherwise `null`. Reports are JSON and include the
environment fingerprint. **Only measured values are reported.**

## 22. Public API, CLI, future GUI (§36, §37)

```text
Engine::new(EngineConfig) · devices() · models() · load_model(path)
Session::open(input) → analysis report · render(region, controls) · variants(...)
Engine::plan(JobRequest) → JobPlan (dry run: decisions, memory, estimated tiles)
Engine::run(JobRequest, &ProgressSink, &CancelToken) → JobReport
```

The API is versioned with a stability policy (MR-3). CLI commands: `upscale`,
`batch`, `analyze`, `models`, `devices`, `benchmark`, `doctor`, `eval`,
`train`. Each is a thin client of the API. A GUI later uses the same API
(`Session` covers previews and variants).

## 23. Plugin system (§38, ADR-0008)

v1 uses compile-time registries (`CodecRegistry`, `BackendRegistry`,
`StageRegistry`). An estimator registry was removed in review: there is no
second provider to justify it (R2-10). Stages must declare `LocalOp{halo}` or
`GlobalAnalysis → LocalOp`. Models are data plugins (validated `.sfm`). There
is no native dynamic loading. The future path is out-of-process plugins with a
versioned protocol.

## 24. Errors, security, privacy (§35)

- Typed errors: `InvalidInput`, `Unsupported`, `LimitExceeded`, `Io`,
  `ModelInvalid`, `Device{Oom, Lost, Other}`, `Cancelled`, `Internal`. The CLI
  maps them to distinct exit codes.
- One `Limits` configuration enforced by every parser: codecs, ICC, JSON,
  `.sfm`, `.sfck`, manifests.
- Fuzz targets for every parser. Codecs are also differentially tested against
  development-only oracles.
- Batch output confinement, no overwrite by default, sanitised names, explicit
  symlink policy.
- GPU failures: an out-of-memory error leads to shrink and retry. Device loss
  gives a typed error, with optional CPU fallback.
- Privacy: no telemetry; location metadata stripped by default; consent
  tracking for face data (MR-1).

## 25. Determinism statement (MR-4)

The CPU backend is bit-deterministic for a fixed thread count and plan. GPU
backends use no atomics in reductions by default, so they are deterministic
per device and driver. A documented fast mode may relax this.

## 26. What is explicitly out of v1

Video; multi-GPU execution of a single image; generative "creative" models;
scratch/dust inpainting; semantic segmentation; native dynamic plugins; lossy
WebP output.

## 27. Implementation status

| Subsystem | Status |
|-----------|--------|
| Requirements, feasibility, dependency audit, architecture, review, roadmap | Written |
| `sf-core` (Phase 6) | **Implemented and tested** |
| `sf-graph` (Phase 7): operator set v1, IR, validation, shape inference, locality, memory planning | **Implemented and tested.** Required-region analysis and crop insertion: moved to Phase 10 |
| `sf-compute` (Phase 7): device abstraction, CPU backend (f32, strict mode, emulated capacity) | **Implemented and tested.** f16: not supported on CPU |
| GPU backends, CUDA and Vulkan (Phase 8) | **INCOMPLETE** — postponed until hardware is installed |
| `vram`, `hostmem`, tiling (Phases 9–10) | **Implemented and tested.** Exact tiling bit-identical to whole-image execution. Required-region cropping: not done |
| `sf-image`, `sf-analysis` (Phase 11) | **Implemented and tested.** Missing: WebP, streaming sources and sinks for images larger than RAM, fuzz campaigns |
| `sf-classic` (ADR-0015 primary path) | **Implemented and tested** |
| `.sfm` runtime and `sf-import` (Phase 12, ADR-0015) | **Implemented and tested** with synthetic files. Not yet validated on a real `.pth` |
| SF-Net and training (Phases 13–14) | **INCOMPLETE — deliberately postponed** (see `training/`) |
| Modes, strategy policy/1, QC, Adobe Stock export (Phases 15, 17, ADR-0016) | **Implemented.** Thresholds provisional. QC runs on the host (not as graph branches). No learned descriptor, predictive QC or variant cache yet |
| Faces, old-photo repair (Phase 16) | **INCOMPLETE** |
| CLI, benchmark (Phases 18, 20) | **Implemented** |
