# ScaleForge Architecture

Status: **Phase 2 proposal, revised after the Phase 3 review.** The review and
its resulting changes are in
[`docs/design/03-architecture-review.md`](docs/design/03-architecture-review.md).
Requirement IDs (F-1, Q-3, …) refer to
[`docs/design/01-requirements.md`](docs/design/01-requirements.md).
Major decisions are recorded as ADRs in [`docs/adr/`](docs/adr/).

Nothing described here is implemented yet, unless the implementation status
table at the end says so.

---

## 1. Overview

```
             ┌──────────────┐   ┌──────────────┐   ┌─────────────────┐
             │  scaleforge  │   │  future GUI  │   │ future C ABI /  │
             │     CLI      │   │              │   │ other bindings  │
             └──────┬───────┘   └──────┬───────┘   └───────┬─────────┘
                    └──────────────────┼───────────────────┘
                                       ▼
┌──────────────────────────── Public API (crate `scaleforge`) ─────────────────────────┐
│  Engine · ModelHandle · JobRequest · Progress · CancelToken · Report                  │
├───────────────────────────────── Engine internals ────────────────────────────────────┤
│  Job Planner ─► Auto-Tuner ─► Tile Planner ─► Scheduler ─► Region Executor            │
│        │             │             │               │                                  │
│        │       Tuning Cache   Memory Manager (host budget)   VRAM Manager (device)    │
│        ▼                                                                              │
│  Model Runtime: load/validate .sfm ─► select subgraph (mode, scale) ─► memory plan    │
│                 ─► compile for device ─► execute                                      │
├──────────────────────────────┬─────────────────────────────┬─────────────────────────┤
│ sf-model                     │ sf-compute (abstraction)    │ sf-image                │
│ .sfm format, graph IR,       │ Backend/Device/Buffer/Queue │ pixel buffers, region   │
│ validation, shape inference, │ Event/Executable traits     │ sources and sinks,      │
│ receptive-field analysis,    │ + CPU reference backend     │ codecs, colour mgmt,    │
│ memory planner               ├─────────────┬───────────────┤ analytic resampling     │
│                              │ sf-compute- │ sf-compute-   │                         │
│                              │ cuda        │ vulkan        │                         │
├──────────────────────────────┴─────────────┴───────────────┴─────────────────────────┤
│ sf-core: errors, limits, geometry, dtypes, cancellation, progress, logging facade     │
└───────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────── training/ (Python, separate process, not linked) ──────────────────┐
│ manifests → validation → degradation programs → pairs → training loop → evaluation →  │
│ export (.sfm) ── parity tests against the Rust runtime (via the CLI) ─────────────────│
└───────────────────────────────────────────────────────────────────────────────────────┘
```

**Key idea.** The system rests on three invariants. Most of the other design
decisions follow from them.

1. **Locality invariant.** Every operation that runs per tile is *local*, with
   a receptive field known ahead of time. Every *global* operation is split
   into a cheap analysis pass over a bounded-size summary of the image, which
   produces parameters, and a local application step. This one rule makes three
   things possible: exact seam-free tiling, streaming of images larger than
   RAM, and exact memory prediction.
2. **Model-as-data invariant.** A model is a declarative graph over a small,
   versioned operator set, plus weights. It is never code. This makes the
   engine model-agnostic (M-2), lets many backends execute models
   (only the operator set has to be implemented per backend), makes memory
   estimates exact (static planning), and makes model files safe to load.
3. **Budget invariant.** Nothing large is allocated without first asking a
   budget: the host memory manager or the VRAM manager. Plans are computed and
   checked against the budgets before execution starts.

---

## 2. Language and process structure (ADR-0001)

- **Engine, runtime, backends, CLI: Rust.** Reasons: memory safety for the
  large attack surface of image decoding and model loading; no GC pauses;
  zero-cost abstraction over backends; good C/C++ FFI for CUDA and Vulkan;
  a single static binary; a strong test and fuzzing story.
- **Training: Python + PyTorch.** Training needs automatic differentiation,
  optimisers, mixed precision and multi-GPU data parallelism. Writing an
  autodiff framework would take years and would be technically worse (N-6 says
  independence must not be bought with inferior engineering). PyTorch is a
  general tensor library, not an upscaling engine, so O-3 is not violated. It
  is used **only** in the training process. The engine never links it.
- The two sides share a **single-source model definition** (§7.4) and a
  **file format** (`.sfm`), and are joined by **parity tests** (T-7).

---

## 3. Crate and module responsibilities

| Crate | Responsibility | Depends on |
|-------|----------------|------------|
| `sf-core` | Error taxonomy, resource limits, geometry (`Rect`, `Size`, `Scale`), dtypes, cancellation token, progress events, logging facade | — |
| `sf-image` | `PixelBuffer`, `RegionSource`/`RegionSink` traits, codecs (feature-gated per format), colour management, analytic resampling | `sf-core`, codec crates |
| `sf-model` | `.sfm` reader/writer, graph IR, operator set, validation, shape inference, receptive-field analysis, memory planner | `sf-core` |
| `sf-compute` | Backend abstraction traits + CPU reference backend | `sf-core`, `sf-model` (operator definitions) |
| `sf-compute-cuda` | CUDA backend (optional feature) | `sf-compute` |
| `sf-compute-vulkan` | Vulkan backend (optional feature) | `sf-compute` |
| `sf-quality` | Metrics (PSNR, SSIM, MS-SSIM, gradient fidelity), regression comparison | `sf-core`, `sf-image` |
| `scaleforge` | **Public API** and engine: model runtime, VRAM and memory managers, tiling, scheduler, auto-tuner, pipeline, instrumentation | all of the above except backends (those are registered) |
| `scaleforge-cli` | CLI binary: argument parsing and presentation only | `scaleforge`, `sf-quality` |

Why these boundaries:

- **Backends are separate crates** so that CUDA and Vulkan bindings and SDK
  requirements are optional and isolated. A CPU-only build links neither. The
  engine sees only the traits (G-1).
- **The CPU backend lives inside `sf-compute`** because it is not optional: it
  is the reference implementation that every other backend is tested against,
  and the fallback of last resort.
- **`sf-model` has no device dependency.** Validation, shape inference and
  memory planning are pure functions. They are tested exhaustively on the host,
  and tools like `scaleforge models inspect` use them without touching a
  device.
- **`sf-quality` is separate from the engine** because both the benchmark and
  regression tools and the CLI `eval` command use it. It is the *canonical*
  metric implementation. The Python training code computes metrics only for
  monitoring (see review item R-12).
- **The engine is one crate** (`scaleforge`), not split into
  runtime/tiling/scheduler crates. Those parts are tightly coupled through
  plans and budgets and have a single consumer. Splitting them would add
  public interfaces with no second user. They are separate *modules* with
  their own tests.

---

## 4. Processing pipeline

The pipeline from the brief, mapped onto concrete components:

```
Input ─► Validation ─► Decode ─► Colour mgmt ─► Preprocess ─► Tiling ─► AI inference
      ─► Reconstruction (tile assembly) ─► Postprocess ─► Colour conversion ─► Encode ─► Output
```

| Stage | Component | Local/global | Testable alone via |
|-------|-----------|--------------|--------------------|
| Validation | `sf-image::probe` + job planner | global (header only) | header fixtures, malformed files |
| Decode | `RegionSource` implementation per codec | streaming where the format allows | codec round-trip and fuzz tests |
| Colour management | `sf-image::color` | per-pixel (local, halo 0) | known-value transforms, round-trip ≤ 1 LSB |
| Preprocess | pack to model tensor, alpha split, border padding | local | tensor fixtures |
| Analysis pass | context graph on a downsampled summary | **global, bounded size** | deterministic outputs |
| Tiling | tile planner | plan only | property tests on plans |
| AI inference | model runtime, main graph | local, halo = receptive radius | parity tests vs. training |
| Reconstruction | crop-and-place (exact mode) or weighted blend (bounded mode) | local | seam criterion Q-3 |
| Postprocess | clamp, alpha merge, dither if reducing bit depth | local | fixtures |
| Colour conversion | inverse of preprocess colour step | per-pixel | round-trip |
| Encode | `RegionSink` implementation per codec | streaming where the format allows | round-trip |

**Pipeline stages are not an arbitrary DAG.** Every extension stage must
declare which kind it is (ADR-0004):

- `LocalOp { halo, scale }` — applied per tile; the tile planner adds its halo.
- `GlobalAnalysis { summary_size } → Params` followed by a `LocalOp` that
  consumes those params.

A stage that needs arbitrary access to the whole image cannot be expressed.
That limit is deliberate: such a stage would break tiling and streaming.

---

## 5. Image engine (`sf-image`)

### 5.1 Buffers

`PixelBuffer { width, height, channels, sample: U8|U16|F16|F32, stride, data }`
with checked construction. Allocation goes through the host memory manager, so
buffers count against the budget. Processing converts to f32 (or f16 on
device) at the tensor boundary and converts back at the end.

### 5.2 Region sources and sinks (streaming)

```text
trait RegionSource { fn info(&self) -> ImageInfo;
                     fn access(&self) -> AccessPattern;   // Random | Sequential{band_rows}
                     fn read(&mut self, rect, &mut PixelBuffer) -> Result<()>;
                     fn rewind(&mut self) -> Result<()>; }
trait RegionSink   { fn write(&mut self, rect, &PixelBuffer) -> Result<()>;
                     fn finish(self) -> Result<()>; }
```

- **Random access**: in-memory images, tiled TIFF.
- **Sequential**: PNG (non-interlaced), baseline JPEG, and stripped TIFF can
  decode row bands. A sequential source is wrapped in a **band cache** that
  holds only the rows the current tile row needs (tile height + 2 × halo).
- **Formats that need a full decode** (interlaced PNG, progressive JPEG, WebP)
  decode fully into memory. The job planner checks the host memory budget
  *before* decoding, using the dimensions from the header.
- Sinks likewise stream (PNG, JPEG and TIFF write row bands; TIFF uses BigTIFF
  above 4 GiB) or buffer (WebP). An output that would exceed the budget or
  the format's limits is rejected during validation (I-7).
- The tile planner orders tiles in **row-major bands**, which matches both
  streaming sources and streaming sinks. Peak host memory is
  O(width × band height), not O(width × height).

### 5.3 Codecs

Each format sits behind `trait Codec { probe, open_source, open_sink,
capabilities }` and is registered in a `CodecRegistry`. The engine does not
depend on any specific image library (I-2). Initial implementations wrap
established, memory-safe, fuzzed Rust decoders and encoders (listed in
`DEPENDENCIES.md`). Writing our own inflate/DCT/LZW decoders would add
security-critical surface with no benefit to the product (ADR-0006).

### 5.4 Colour management (ADR-0005)

Principle: **process in the image's native encoded space whenever that is
valid, and carry the profile through unchanged.**

- The model is trained on gamma-encoded RGB (sRGB-like transfer). Its
  behaviour does not depend strongly on the exact primaries. Processing a
  Display P3 image in its own encoded values and re-attaching the P3 profile
  therefore causes **no gamut clipping and no conversion error**. A convert →
  process → convert back approach would clip wide-gamut colours at the sRGB
  step.
- A minimal ICC reader (header, tag table, `rXYZ/gXYZ/bXYZ`, `rTRC/gTRC/bTRC`,
  `wtpt`, `desc`) *classifies* profiles (RGB/grey, transfer class: gamma-like,
  linear, or unknown). Full LUT-based colour transforms are not needed on the
  common path. Profiles are passed through byte for byte.
- **Linear-light inputs** (linear TIFF, float, future EXR) are encoded with a
  documented invertible transfer into the model's working range, and decoded
  after processing.
- **HDR (values > 1.0)**: an invertible range-compressing encoding (a
  logarithmic curve with a known inverse) maps the values into the working
  range. This path is marked **experimental** until it has been evaluated.
- Grey images are processed as three identical channels and converted back
  using the mean, so no colour is introduced. CMYK is rejected in v1 with a
  clear error.
- EXIF orientation is applied before processing, and the tag is reset in the
  output. Associated (premultiplied) alpha is un-premultiplied only where
  alpha exceeds a threshold, so near-zero alpha does not amplify quantisation
  noise.
- Alpha is split off before processing. It is upscaled with the analytic
  resampler and merged back. Colour under fully transparent pixels is filled
  from neighbours before inference, so garbage colour does not bleed into
  visible edges.

### 5.5 Analytic resampling

A separable windowed-sinc resampler, together with area (box) downsampling.
It is used for alpha, for the analysis-pass summary, as a comparison baseline
(F-6), and for the fixed operators inside the consistency step. It is
implemented in-house: the mathematics is standard, and we need exact control
over kernel support to account for its receptive field.

---

## 6. GPU abstraction (`sf-compute`, ADR-0003)

### 6.1 Level of abstraction

The abstraction sits **at the graph-execution level, not the kernel level.**
The engine hands a backend a *memory-planned graph*. The backend compiles it
into an `Executable`, choosing kernels, fusing element-wise ops and picking
layouts. The engine never names a kernel. This keeps vendor-specific
optimisation inside backends while keeping the interface small.

```text
trait Backend      { fn id(); fn enumerate() -> Vec<DeviceInfo>; fn open(DeviceId) -> Box<dyn Device>; }
trait Device       { fn info() -> DeviceInfo;               // name, vendor, driver, capabilities
                     fn memory_status() -> MemoryStatus;     // total, budget, in-use (if queryable)
                     fn allocate(bytes, MemoryKind) -> Result<Buffer>;   // Device | HostStaging
                     fn create_queue() -> Box<dyn Queue>;
                     fn memory_requirement(&PlannedGraph, Shape, Precision) -> MemoryRequirement; // pure, no allocation
                     fn compile(&PlannedGraph, Precision) -> Result<Box<dyn Executable>>; }
trait Queue        { fn upload(&HostSlice, &Buffer, offset) -> Result<()>;
                     fn download(&Buffer, offset, &mut HostSlice) -> Result<()>;
                     fn execute(&dyn Executable, &Bindings) -> Result<()>;
                     fn signal() -> Event;  fn wait(&Event); fn synchronize(); }
trait Executable   { fn workspace_bytes() -> u64; fn io_signature() -> IoSignature; }
```

- **Device management**: `Backend`/`Device`. **Memory allocation and
  buffers**: `allocate`/`Buffer` (opaque, sized, typed by `MemoryKind`).
  **Operations**: `compile`/`Executable`. **Transfers**: `upload`/`download`.
  **Synchronisation**: `Event`. **Execution**: `Queue::execute`. These are the
  six concerns G-3 requires to be separate.
- Everything on a `Queue` is asynchronous by contract. Host memory used by an
  `upload` must not be reused until its event has signalled.
- **The CPU backend obeys the same contract.** It has its own "device"
  allocations (distinct from host buffers) and explicit copies. In a
  **strict mode** used in tests, it checks that no host access happens before
  the corresponding event and that no buffer is freed while in flight. This
  prevents the abstraction from quietly taking on CPU-only semantics before the
  GPU backends exist (review item R-3).

### 6.2 Backends

| Backend | API access | Kernels | Status target |
|---------|------------|---------|---------------|
| CPU | — | Own Rust kernels: direct and blocked convolution, depthwise, GEMM, element-wise; multithreaded by rows | Reference; deterministic; CI-validated |
| CUDA | Driver API loaded at run time (no link-time CUDA dependency); kernels compiled with NVRTC at first use and cached | Own CUDA C kernels | Written against the abstraction; **unvalidated until run on NVIDIA hardware** |
| Vulkan | Vulkan 1.2 via a thin binding; `VK_EXT_memory_budget` for budgets | Own compute shaders, compiled to SPIR-V at build time | Same as CUDA |

Vendor libraries (cuDNN, cuBLAS) are **not** used initially. If measurements
later show that our kernels are far slower, their use will be proposed in an
ADR with the measurements attached (N-5). They would be optional kernel
providers inside the CUDA backend, never a requirement.

---

## 7. Model system

### 7.1 Model file format `.sfm` (ADR-0002)

```
[magic "SFMODEL\0"][format version u32][header length u64][header JSON (UTF-8)]
[padding to 64-byte alignment][tensor data blob]
```

The header holds `metadata` (name, version, architecture ID and hash,
training-run ID, dataset-manifest hash, licence, scales, modes,
precisions with their measured fp16 error bound, colour working space) plus
`graphs` (`context`, `main`) and a `tensors` directory (name, dtype, shape,
offset, length, SHA-256).

Loading validates: the magic and version; header length ≤ 16 MiB; well-formed
JSON; every tensor range in bounds, aligned and non-overlapping; hashes
matching; every node's op in the operator-set version's whitelist; the graph
acyclic; every input defined; shape inference succeeding for the declared
input constraints; the parameter count and the largest tensor within limits.
**No code, no pickle, no dynamic dispatch on strings beyond the whitelist.**

### 7.2 Graph IR and operator set (versioned)

Operator set v1 (deliberately small, so every backend can implement all of it):
`conv2d` (k ∈ {1,3,5,7}, groups ∈ {1, C} (depthwise), stride ∈ {1,2}, zero
padding), `add`, `mul`, `affine_channel` (per-channel scale and shift from a
vector), `activation` (GELU-tanh, SiLU, sigmoid, identity), `pixel_shuffle`
(r=2), `avg_pool` (2×2, stride 2), `upsample_nearest` (×2),
`resample_fixed` (fixed separable kernel, used for the analytic base and
consistency), `concat_channels`, `split_channels`, `global_mean` (context
graph only), `linear` (context graph only), `scale_scalar` (runtime scalar
such as the strength `s`).

`global_mean` and `linear` over spatial dimensions are **forbidden in the
`main` graph**. The validator enforces this, and this is what the locality
invariant rests on.

### 7.3 Static analyses in `sf-model`

- **Shape inference** for any input (H, W) that meets the alignment
  constraint.
- **Receptive-field analysis**: walks the graph and computes, for each output,
  the input halo radius (in LR pixels) and the **spatial alignment** (the
  product of strides on the deepest path). These values are *derived* from the
  graph, never hand-declared. A model's metadata is checked against them.
- **Subgraph selection**: given (scale, mode), prunes the graph to the nodes
  needed. For example, Faithful mode drops the synthesis path, and scale 2
  drops the ×4 and ×8 stages.
- **Required-region analysis and crop insertion**: a backward pass computes,
  for every node, the spatial region actually needed to produce the tile core.
  The planner then inserts internal `crop` nodes (a planner-only op that is
  never stored in files) so that each tensor is computed only over its needed
  region. Without this, the ×2/×4/×8 stages would process the body's full halo
  at high resolution. The halo exists for the body's benefit, but the
  high-resolution stages hold most of the pixels (review item R-4).
- **Memory planning**: liveness analysis plus offset assignment in one arena,
  giving `peak_activation_bytes(H, W, batch, precision)` exactly. For a
  convolutional graph this is affine in H·W, so the auto-tuner can *solve*
  for the largest tile that fits instead of searching for it. This generic
  plan is the default. A backend that changes layouts or fuses ops reports its
  own figures through `Device::memory_requirement` (§6.1). The VRAM manager
  always uses the backend's figures (review item R-5).

### 7.4 Single-source model definition (ADR-0007)

The ScaleForge architecture is defined once, in Python, with a small builder
DSL whose layers each know (a) their PyTorch implementation for training and
(b) their IR emission for export. The exporter writes the IR and weights to
`.sfm`. **Parity tests**: export with fixed random weights, run the same
inputs through PyTorch and the Rust CPU runtime, and require a maximum
absolute error ≤ 1e-4 (fp32). The operator set is the contract. Adding an op
means implementing it in the DSL, in the CPU backend, and in each GPU backend,
with parity tests for each.

---

## 8. ScaleForge neural architecture ("SF-Net", details in MODEL.md at Phase 12)

Design goals, in order: tile-exact locality; a bounded receptive field;
scale-flexible output; a clear faithful/synthesis separation; good use of
compute at high output resolutions.

```
 analysis summary (streaming-compatible, bounded size):
   • patch mosaic: K native-resolution patches (e.g. 64×64) on a deterministic grid
   • thumbnail: area-downsampled whole image (≤ 256 px)
                       ┌──────────────────────── context graph ─────────────────────────────────┐
 patch mosaic ────────►│ conv stem → blocks → global_mean → degradation descriptor d            │
 thumbnail    ────────►│ small conv net → global_mean → global colour/tone statistics g         │
                       └───────────────────────────────┬────────────────────────────────────────┘
                     user overrides (noise level, …) ──┤
                                                       ▼
                                 base condition  c_b = embed(d, g)      (never depends on s)
LR tile (+halo) ─► stem conv ─► [Dual-Rate Block × N, modulated by c_b] ─► body features F
                                              │
                ┌─────────────────────────────┴──────────────────────────────┐
                ▼  base path (always)                                          ▼ synthesis path (Reconstruction only)
    ×2 stage ─► ×2 stage ─► ×2 stage                              c_s = embed(d, g, s)
    each: conv→pixel_shuffle→refine; emits a residual on        texture trunk (modulated by c_s)
    top of the fixed analytic upsample                             ─► ×2 stages ─► residual R
                ▼                                                               │
          base output B_k at scale 2^k                                           │
                └─────────────────────── Y = B + s·R ◄───────────────────────────┘
                                             ▼
                         consistency step: Y ← Y + U(LP(x) − LP(D(Y)))
                  (D: fixed area downsample, LP: fixed low-pass, U: fixed upsample)
```

Degradation evidence (noise grain, compression blocks, ringing) lives at
native resolution and is destroyed by downscaling. So the degradation
estimator sees **native-resolution patches**, and only the colour/tone
statistics use the thumbnail (review item R-2).

The strength `s` enters **only** the synthesis path. The body and base path
see only `c_b`, so Faithful output cannot depend on `s` (review item R-1).

**Dual-Rate Block (DRB).** The block keeps a full-rate stream (LR resolution)
and a half-rate stream. The full-rate stream does local detail work
(depthwise 3×3 → pointwise expansion with a multiplicative gate → pointwise
projection). The half-rate stream gives cheap context: a depthwise conv at half
resolution doubles the effective radius for the same cost. At the end of each
block the two streams exchange information (average-pool into half-rate,
nearest-upsample into full-rate, each through a pointwise mix). Per-channel
affine modulation from `c` conditions every block on the estimated degradation.
Half-rate streams appear only in a configurable subset of blocks. This is how
the **receptive-radius budget** is enforced: the build fails if the derived
radius exceeds the configured budget (target ≤ 32 LR px for the base
configuration; the final value will be measured and justified in Phase 12).

**Scale flexibility.** The body is shared. There are three ×2 reconstruction
stages, each emitting an output, so 2x, 4x and 8x come from one model and a
lower scale simply skips the later stages (F-1). The channel count halves at
each stage so that 8x memory stays bounded: most of the output pixels live in
the cheapest stages.

**Faithful vs. Reconstruction (F-3/F-4).** Training is staged. Stage A trains
stem, body, base path and context graph with distortion losses only. Stage B
**freezes all Stage-A weights** and trains the synthesis path with texture,
frequency and adversarial objectives. Consequences: Faithful output is
unaffected by synthesis training (this is tested); `s = 0` equals Faithful
exactly; and the synthesis path is pruned at run time in Faithful mode.

**Consistency step.** A fixed (non-learned) operator. It forces the low
frequencies of the re-downsampled output to match the input, which bounds
colour and brightness shifts and large-structure fabrication in both modes.
The low-pass keeps input noise out of the output. Its kernel support counts
towards the receptive radius, like any other op.

**Deterministic synthesis.** If stochastic texture inputs are ever added, they
will be generated from a hash of *absolute image coordinates* and a seed, so
that they are tile-invariant.

---

## 9. Model runtime (in `scaleforge::runtime`)

```text
ModelRuntime::load(path, &Limits) -> ModelHandle           // parse + validate, host only
ModelHandle::metadata() / supported_scales() / modes() / precisions()
ModelHandle::prepare(&Device, Variant{scale, mode, precision}, TileShape{h, w, batch})
      -> PreparedModel                                      // subgraph, plan, compile, upload weights
PreparedModel::memory() -> MemoryRequirement { weights, activations, workspace, io }
PreparedModel::run(&Queue, inputs, outputs, scalars)
ModelHandle::unload / drop                                  // releases device memory via VRAM manager
```

Weights are uploaded once per (device, precision) and shared by all prepared
variants. Changing tile shape re-plans activations; it never re-uploads
weights.

---

## 10. VRAM manager and memory manager (ADR-0009)

### 10.1 VRAM manager (per device)

- **Budget** = min(device-reported budget, user limit) − safety reserve. The
  reserve starts conservative and is later calibrated from measurements
  (reported vs. actually allocatable).
- **Pools with ownership accounting**: `weights` (resident per loaded model),
  `activations` (a single arena sized from the memory plan), `io` (input and
  output staging, ×2 when double-buffered), `workspace` (reported by the
  backend's `Executable`). Every allocation is tagged, so the peak for each
  category is reported exactly.
- **Fragmentation** is avoided by design. Each category is one or a few large
  allocations, sub-allocated at statically planned offsets. Arenas grow
  monotonically during a job (re-allocated only when a larger plan is needed)
  and shrink between jobs on request.
- **Pre-flight**: `fits(plan) -> Fit | Shortfall{bytes}` before any
  allocation. The auto-tuner uses `Shortfall` to shrink the tile or batch.
- **Runtime OOM** (the estimate was wrong, or another process took memory):
  release arenas, shrink the tile shape by a factor, re-plan, retry the
  current band. Bounded to N attempts. Because tiling is exact, a tile-size
  change in the middle of an image cannot create seams (see §11).

### 10.2 Host memory manager

A process-wide budget (default: a fraction of physical RAM, overridable) is
charged by pixel buffers, band caches, tile staging and sink buffers. The job
planner calculates a job's peak host memory from the tile plan *before*
decoding and refuses or adapts (e.g. smaller bands, streaming sinks) if it
will not fit.

---

## 11. Tile engine (ADR-0004)

**Exact mode (default).** Let `r` be the derived receptive radius and `a` the
alignment. For each tile, the planner reads the core region plus a halo of `r`
(rounded up to `a`), clamped to the image. It runs the main graph on this
region with the model's own border semantics (zero padding at every conv),
then crops the output to the core × scale. At the image border the tile's
border *is* the image border, so the computation is identical to whole-image
inference. Inside the image, the halo contains real pixels, so every output
pixel sees exactly the inputs it would see in a whole-image run. **No blending
is needed. Seams cannot exist**, up to floating-point operation order. This is
verified by Q-3.

- **Canonical padding**: an image whose size is not a multiple of `a` is padded
  once, globally, to a multiple of `a` (reflection padding). Whole-image and
  tiled runs use the same canonical image, and the output is cropped at the
  end.
- **Cores vs. compute windows**: the image is partitioned into
  **non-overlapping core rectangles**. Each core is written exactly once. Its
  *compute window* is the core, enlarged to the uniform tile shape by shifting
  inward at image edges, plus the halo. Every compute window therefore has the
  same shape: there is one compiled plan, tiles batch naturally, and no small
  ragged tiles occur. The overlap between compute windows is redundant
  computation of identical values. Only the core part of each window's output
  is written (review item R-6).
- **Ordering**: row-major bands, for streaming (§5.2).

**Bounded-error mode (opt-in, or chosen by the auto-tuner under memory
pressure).** Uses a halo `h < r`, with cosine-weighted blending in the overlap.
Its maximum deviation from exact mode is **measured** per model and halo during
calibration and reported, never assumed. This is useful because the
*effective* receptive field of trained convolutional networks is much smaller
than the theoretical one.

---

## 12. Scheduler (ADR-0010)

The per-tile path is **fetch → preprocess → upload → execute → download →
postprocess → write**.

- **v1: synchronous executor.** One thread drives the stages in order. This is
  the correctness reference and the baseline for measurement.
- **Pipelined executor**: three stages (CPU pre-work → device → CPU post-work)
  on dedicated threads connected by bounded channels (depth 2), with double-
  buffered staging. It is enabled **only when benchmarks on the target show a
  measurable gain**. The auto-tuner records this per device in the tuning
  cache.
- There is no async runtime (tokio etc.). Plain threads and channels are
  enough, and the concurrency is easy to reason about.
- Sinks receive cores in plan order. The pipelined executor keeps a small
  reorder buffer so that out-of-order completion (possible in future
  multi-queue backends) never reaches a streaming encoder (review item R-7).
- **Analysis pass first**: the summary (§8) is built in one pass over the
  source before any tile runs. For a sequential streaming source this means
  decoding it twice (`RegionSource::rewind`). This cost is accepted and
  reported in the job timings. Non-rewindable inputs (stdin) are spooled to
  a temporary file, within the budget (review item R-8).
- **One device executor per device.** Multiple jobs (e.g. a batch, or a GUI
  preview) queue on it. The job-level scheduler assigns files to devices.
- Cancellation is checked between tiles. Progress events are emitted per tile.

---

## 13. Auto-tuner (ADR-0009)

Inputs: device info and memory status, model (receptive radius, alignment,
memory function), image size, scale, mode, available precisions, and the
tuning cache.

1. **Analytic phase** (always): for each precision the model declares safe and
   the device supports, solve the memory plan for the largest square tile that
   fits the budget at batch 1. Then compute the halo overhead
   `((T + 2r)/T)²` and a cost estimate from graph FLOPs, and generate candidate
   (tile, batch, precision, executor) tuples. Small images get a single tile
   covering the whole image (S-1).
2. **Measured phase** (`scaleforge benchmark --calibrate`, or opportunistically
   on first use if enabled): time each candidate on the real device and store
   the medians in the **tuning cache**, keyed by (backend, device, driver,
   model hash, precision, scale, mode).
3. **Decision**: use measured data when present, otherwise the analytic
   ranking. Every run records the decision and its reason in the job report.

The fixed numbers in the analytic phase (safety reserve, default candidates)
are starting points, labelled as such, and are superseded by measurements.

---

## 14. Public API (`scaleforge` crate)

```text
Engine::new(EngineConfig) -> Engine                  // backends, budgets, tuning cache path
Engine::devices() -> Vec<DeviceInfo>
Engine::load_model(path) -> ModelHandle
Engine::plan(&JobRequest) -> JobPlan                  // validation + tuning, no heavy work (dry run)
Engine::run(JobRequest, &dyn ProgressSink, &CancelToken) -> JobReport
Engine::run_region(...)                               // preview a crop for GUIs
JobRequest { source: Input(path|memory), sink: Output(path|memory), model, scale,
             mode: Faithful | Reconstruction{strength}, overrides, tiling, precision, device }
JobReport  { timings per stage, memory peaks, tile plan, decisions, warnings }
```

The GUI (future) and the CLI are clients of exactly this surface. `plan()`
gives front-ends a way to show memory and time expectations before a job is
committed.

---

## 15. Plugin system (ADR-0008)

- **v1: compile-time registries** (`CodecRegistry`, `BackendRegistry`,
  `StageRegistry`) populated by feature-gated crates. Extension traits carry
  their validation contracts (e.g. `LocalOp` must declare a halo; codecs must
  declare limits).
- **Models are data plugins**: dropping a validated `.sfm` into a model
  directory is enough (M-2).
- **Not in v1: loading native dynamic libraries.** They run arbitrary code with
  full privileges and have no stable Rust ABI. The future path for third-party
  code is out-of-process plugins speaking a versioned message protocol, which
  gives isolation and crash containment.

---

## 16. Training system (`training/`, details in TRAINING.md at Phase 13)

```
manifest (JSONL: path, sha256, source, licence, attribution, split)
  → validate (licence whitelist, decode, min size, exact and near-duplicate hashing, split leakage)
  → crop sampler (content-aware: rejects flat crops)
  → degradation program (sampled, seeded, parameters logged)
  → (LR, HR, parameters) pairs → training loop → validation → checkpoints → export .sfm
```

**Degradation programs.** These are our own design, modelled on the physical
life of an image rather than on a fixed operator list. A program is sampled
from a grammar of three phases, each optional and randomised:

1. **Capture**: optical blur (defocus disc, Gaussian, anisotropic, motion
   path) → sensor sampling at a lower resolution → **sensor noise in linear
   light** (signal-dependent shot noise + read noise, Poisson-Gaussian) →
   optional colour-filter mosaic and a simple demosaic.
2. **In-camera processing**: tone curve / gamma → noise reduction (smoothing)
   → sharpening (unsharp mask, including **oversharpening** with halos) →
   quantisation.
3. **Distribution**: one or more rounds of resize (various kernels, including
   ones that alias), JPEG/WebP-style compression (optionally with chroma
   subsampling), re-sharpening, and ringing from band-limiting filters.

**Context without whole images.** At inference, the context graph sees a
summary of the *whole* image. At training time, the degradation program is
applied to a **context window** several times larger than the training crop.
The analysis summary is built from that window using the same summary
operator as inference, and the training crop is taken from inside it. The
descriptor `d` describes largely stationary properties (noise level,
compression strength), so a large window approximates the whole image. The
remaining gap is measured by an evaluation of `d`'s sensitivity to the
summary's source region (review item R-9).

The LR/HR relationship is fixed by the total resize factor. Every sampled
parameter is logged and also used as a *supervised target* for the context
graph's degradation estimator. Seeds derive from (global seed, epoch, sample
index) (T-4).

**Losses.** Stage A: Charbonnier pixel loss, gradient loss, frequency-magnitude
loss, consistency loss, and degradation-estimation loss. Stage B: our own
discriminator (trained from scratch), adversarial and feature-matching losses,
and frequency/texture statistics. **No pretrained perceptual networks** are
used in training, which keeps O-2 intact without special pleading.

**Tracking and reproducibility.** Each run directory holds the resolved config,
git commit, environment report, seeds, manifest hash, JSONL metrics, and
checkpoints. Checkpoints contain weights in our format plus optimizer state
loaded with safe (weights-only) deserialisation. Exported `.sfm` files record
the run ID and manifest hash. Model versions follow
`sf-<size>-<major>.<minor>`.

**Dataset licensing.** No dataset ships with the repository. The manifest
requires a licence identifier per image, and the validator enforces a
configurable allow-list. TRAINING.md will document sourcing guidance and warn
that many common super-resolution research datasets are licensed for
non-commercial research only.

---

## 17. Quality evaluation and benchmarking

- **`sf-quality`** (canonical): PSNR (RGB and Y), SSIM, MS-SSIM, and a gradient
  fidelity metric. LPIPS is available only through an **optional external
  evaluator script** that the user runs with separately obtained weights. It is
  never a dependency and never used in training.
- **Human evaluation**: `scaleforge eval ab` builds randomised, blinded pairs
  and a simple rating record (CSV). The protocol is documented in BENCHMARKS.md.
- **Regression**: a fixed evaluation set (defined by a manifest) with fixed
  degradation seeds. Metrics are stored per model version, and new versions
  are compared with per-metric tolerances. No single metric decides a release.
- **Benchmark harness**: warm-up runs, N repetitions, medians and percentiles.
  Per-stage timings come from the engine's own instrumentation. Peak VRAM
  comes from the VRAM manager's tagged accounting, plus device-reported usage
  when available. Transfer bytes and times come from the `Queue` API. CPU
  utilisation is process CPU time ÷ wall time. GPU utilisation comes from
  vendor telemetry if it is present at run time, otherwise it is `null`.
  Reports are JSON and include the full environment fingerprint (Q-5, Q-6).

---

## 18. Error handling and security (details in SECURITY.md at Phase 16)

- A typed error taxonomy in `sf-core`: `InvalidInput`, `Unsupported`,
  `LimitExceeded`, `Io`, `ModelInvalid`, `Device{Oom, Lost, Other}`,
  `Cancelled`, `Internal`. The CLI maps these to distinct exit codes.
- `Limits` (max dimensions, pixels, decoded bytes, ICC size, header size,
  tensor count and size) are configured once and enforced in every parser.
- Fuzz targets for: every codec wrapper, the ICC reader, and the `.sfm`
  parser and validator.
- Output path policy for batches (confinement, no overwrite by default,
  sanitised derived names, explicit symlink handling).

---

## 19. Implementation status

| Subsystem | Status |
|-----------|--------|
| Requirements, architecture, review, plan | Written (this document and `docs/`) |
| Everything else | **Not started** |
