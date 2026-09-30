# Changelog

## Unreleased

### Phase 11 (continued) — own WebP decoder
- `sf_image::webp`, written from RFC 9649 (container, lossless) and
  RFC 6386 (VP8 lossy):
  - RIFF container, simple and extended (`VP8X`) layouts, `ICCP` and
    `EXIF` orientation;
  - lossless VP8L: all four transforms, colour cache, meta prefix codes,
    LZ77 with the 2-D distance map;
  - lossy VP8 key frames: boolean decoder, segmentation, all intra modes,
    token partitions, both loop filters;
  - `ALPH` alpha: raw or lossless-compressed, all prediction filters.
- VP8 constant tables were extracted from the RFC text by a script (they
  are normative data). Where RFC 6386 contradicts itself
  (`segment_feature_mode`, the §13.3 pseudocode), the annex and prose are
  followed; this is documented in the code.
- Animated WebP is refused (`unsupported`). WebP *output* is INCOMPLETE:
  `batch` writes PNG for WebP inputs unless `--ext` says otherwise.
- Checked against libwebp 1.6.0:
  - lossless: identical pixels;
  - lossy: at most 2 levels difference, coming from the RGB conversion;
  - alpha: identical;
  - a 17 MP photo decodes in 480 ms (libwebp 195 ms). See `BENCHMARKS.md`.
- 9 new tests: 11 reference files from libwebp (lossless incl. palettes
  of 2/3/12/200 colours; lossy q10/q80/q98; alpha), truncation and
  bit-flip robustness, extended format, animation and size-limit
  rejection, raw alpha with every filter, CLI end to end. Test count: 193.
- Not covered by reference files: the simple loop filter and multiple
  token partitions (Pillow cannot request them). They follow the RFC but
  are not yet verified against libwebp.

### Phase 21 — first measured optimisation
- PNG encoding is parallel:
  - DEFLATE cuts the data into fixed 256 KiB segments and compresses them
    on separate threads. Each segment's match search is primed with the
    previous 32 KiB. Non-final segments end with an empty stored block, so
    every segment starts byte-aligned. The output does not depend on the
    thread count (tested). The size changes by less than 0.1 %.
  - Row filtering runs in bands of rows.
- Postprocessing is parallel: the Gaussian blur, sharpening, the QC halo
  check and the classical upscale clamp run over row bands.
- All of these give bit-identical pixels. This was checked against the
  previous build on three real jobs, including a 17 MP TIFF.
- Measured on a Ryzen 9 5900X (`BENCHMARKS.md`):
  - 1024x768 → x2: 951 → 321 ms;
  - 2048x1536 → x2: 3772 → 1044 ms.
- 5 new tests: multi-segment DEFLATE round trips, matches across segment
  boundaries, identical output for 1/3/64 threads, large PNG round trips,
  row-band coverage. Test count: 184.

### Phase 12 — first real model validation
- `scaleforge convert-model` on the real `RealESRGAN_x4plus.pth` works
  without changes (rrdbnet x4, 16 697 987 parameters).
- Our engine's output matches an independent PyTorch reference to 6.9e-6.
  Our graph clamps its output to [0, 1]; the reference does not.
- Measured and added to `BENCHMARKS.md`:
  - blended-tiling error: 44.9 dB (64 px tiles) and 53.2 dB (128 px tiles)
    PSNR against a whole-image run;
  - PSNR/SSIM against a ground truth;
  - speed on a Ryzen 9 5900X. Our CPU convolution is about 3–4x slower
    than PyTorch on CPU.
- `realesr-general-x4v3.pth` (SRVGG) was not available: still validated
  only on synthetic files.
- Toolchain: code adjusted for clippy 1.98 (`as_chunks`, `checked_div`), no
  behaviour change. `models/` is git-ignored (weights are never committed).

### Owner decision: own-model training postponed
- `training/` is an empty placeholder with a note: ScaleForge's own model
  (SF-Net) and its training system will be built later, once the GPUs are
  installed and a dataset is assembled. `TRAINING.md` and `MODEL.md` say
  INCOMPLETE.

### Phase 18/20 — CLI and benchmark (implemented)
- `scaleforge` commands: `upscale`, `batch`, `analyze`, `models`,
  `convert-model`, `devices`, `doctor`, `benchmark`, `help`, `version`.
- Our own strict argument parser.
- Stable exit codes (9 = export profile not met).
- Batch mode:
  - skips symbolic links;
  - keeps outputs inside the chosen directory;
  - continues past failures unless `--fail-fast` is given.
- The benchmark reports the median, all runs, per-stage times, MP/s and CPU
  utilisation. GPU utilisation is `null`. Results are in `BENCHMARKS.md`.
- The Adobe Stock profile refuses inputs that cannot reach 4 MP even at x8
  before doing any work.
- New docs: `SECURITY.md`, `BENCHMARKS.md`, `MODEL.md`, `TRAINING.md`,
  `CONTRIBUTING.md`. README, BUILD, DEVELOPMENT, ARCHITECTURE and
  DEPENDENCIES are reconciled with the code.
- CLI integration tests run the real binary. Test count: 179 in total.

### Engine pipeline (Phases 15/17 partial, ADR-0015/0016)
- Engine, job requests and reports:
  - EXIF orientation, alpha handling, bit-depth preservation;
  - atomic writes that never overwrite silently;
  - tiled model enlargement with an out-of-memory retry at smaller tiles.
- Strategy policy/1 (provisional thresholds). Each decision records its
  source, rule and evidence.
- Modes:
  - Faithful is classical only;
  - Balanced blends the model at 0.5;
  - Reconstruction uses the requested strength.
- QC: consistency correction; checks for consistency residual, colour shift
  and halo overshoot.
- Adobe Stock export (ADR-0016):
  - the rules are data;
  - scale choice;
  - JPEG quality search under the size limit;
  - sRGB conversion;
  - non-commercial models blocked;
  - compliance verdict and AI disclosure.
- Fix: the noise estimator was biased about 20 % low. It is now within 12 %
  for σ 2–20.

### Phase 12 — Model runtime and external model import
- Our own SHA-256 (FIPS vectors); `sha2` is not needed.
- `.sfm` container:
  - data only;
  - whitelisted operators;
  - SHA-256 per tensor and for the whole blob;
  - locality and scale re-derived on load.
- `sf-import`:
  - ZIP reader;
  - restricted pickle interpreter (an `os.system` payload is refused);
  - `.pth` loader (f32/f16/bf16/f64);
  - graph builders for RRDBNet (x4/x2/x1) and SRVGG.
- Tested with synthetic files only; no real weights were available.

### Phases 9–10 — Memory and tiling
- VRAM manager:
  - pools and pre-flight checks;
  - current and peak accounting;
  - release on drop.
- Host memory budget.
- Tiling:
  - planner with disjoint cores, aligned windows and a guaranteed halo;
  - exact mode, bit-identical to whole-image execution;
  - cross-faded bounded-error mode;
  - out-of-memory recovery with smaller tiles.
- Strict mode caught a missing upload → execute dependency. The API now
  requires ready events.

### Phase 11 — Image engine, analysis, classical engine
- Our own zlib/DEFLATE and PNG. Checked against independent decoders
  outside the repository: bit-exact with Go on 49 files.
- JPEG:
  - baseline and progressive decoding;
  - baseline encoding with optimised Huffman tables;
  - within 3 levels of Go on 25 files.
- TIFF and BigTIFF: LZW, Deflate and PackBits; strips and tiles; 8/16/32f.
- ICC → sRGB (Bradford), with our own sRGB profile.
- Lanczos, area, bilinear and nearest resampling.
- Analysis:
  - noise;
  - blockiness and JPEG quality taken from the quantisation tables;
  - edge width;
  - exposure, contrast and colour balance;
  - texture;
  - PSNR/SSIM.
- Classical engine: wavelet denoise, deblock, anti-ringing upscale,
  halo-limited sharpen, tone.

### Phase 8 — GPU execution: INCOMPLETE (postponed by the owner until the GPUs are installed)

### Phase 7 — Tensor and compute system (implemented)
- `sf-graph`:
  - operator set v1 (provisional);
  - graph IR with builder;
  - validation, including the Main-role rule that no spatial reduction may
    reach a tensor output;
  - shape inference;
  - derived locality (receptive radius and alignment);
  - liveness-based arena memory planner.
- `sf-compute`:
  - device abstraction separating device management, allocation and
    buffers, compiled executables, transfers, execution and events;
  - CPU reference backend: deterministic multithreaded kernels,
    graph-level executor using the static memory plan, **strict mode**
    detecting read-after-write, write-after-read and write-after-write
    hazards between queues, and emulated device capacity with recoverable
    out-of-memory errors.
- Tests (28 new):
  - every kernel against independently written naive references (120
    convolution configurations);
  - bit-identical results across thread counts;
  - exact arena sizing;
  - binding validation;
  - hazard detection;
  - OOM with accounting back to zero;
  - **tiled execution with the derived halo is bit-identical to
    whole-image execution** (a control case with an insufficient halo is
    detected).
- Self-review fixes: strict mode recorded accesses for submissions that
  were later rejected by binding validation. Validation now happens first
  (test added). Clippy suggestions applied. Minimum Rust raised to 1.88
  (let-chains).
- Known limitations (to be measured before optimising): no in-place
  operator execution; graph outputs are copied out of the arena; small
  element-wise kernels are single-threaded; convolution parallelises over
  output planes only.
- Scope move: required-region analysis and crop insertion → Phase 10.

### Owner request: Adobe Stock export profile (design, ADR-0016)
- Export profiles designed, with rules as versioned data, a compliance check
  and an AI-disclosure report. The Adobe Stock photo rules (JPEG + sRGB,
  4–100 MP, ≤ 45 MB, no enlargement degradation, AI labelling, rights to AI
  output) come from Adobe help pages via search results. They must be
  re-verified against the live pages.
- `non-commercial` models are blocked for images that will be sold.

### Phase 6 — Core foundation (implemented)
- Cargo workspace (edition 2024, `unsafe_code = "forbid"`, clippy clean);
  zero third-party dependencies.
- `sf-core`:
  - error taxonomy with device error kinds;
  - `Limits` with validation and image and decoded-size checks;
  - overflow-checked `Size`/`Rect` and alignment helpers;
  - `Scale` (1/2/4/8x) and `DType`;
  - our own strict JSON reader/writer (UTF-8 validated, duplicate keys
    rejected, size and depth limits, exact 64-bit integers);
  - deterministic RNG with derivable streams;
  - `CancelToken`, `ProgressSink`.
- 39 tests: unit tests, seeded property tests (geometry, JSON round-trip), and
  30,000 mutated-input robustness cases for the JSON parser.
- Self-review: fixed two doc gaps (`Rect::relative_to` for empty rectangles;
  the meaning of zero ICC/metadata limits). The logging trait is deferred
  until a consumer exists, to avoid an unused abstraction. Known limitation:
  the JSON *writer* recurses without a depth bound, which is safe for parsed
  values (already depth-limited) but not for adversarially constructed
  in-memory values (none exist in the codebase).
- Added BUILD.md and DEVELOPMENT.md.

### Owner decision: classical engine + optional external models (ADR-0015)
- The classical engine becomes the primary processing path (new `sf-classic`).
- Openly licensed pretrained models are admitted as an optional, labelled
  add-on running in our own engine. Licences were verified from source, and
  the candidates are registered in `docs/design/06-external-models.md`.
- Usage scope set by the owner: local, personal use only. Non-commercial
  licences (CodeFormer, GFPGAN) are admitted with a `non-commercial` tag.

### Design revision 2 — Master Specification (Phases 1–5)
- Requirements re-analysed against the master specification: Balanced mode,
  analysis/strategy/QC, faces, 1x restoration, engine independence.
  Contradictions (X-1 to X-9), unrealistic assumptions, missing requirements
  and open questions are documented.
- Capability feasibility matrix (§43) for every listed capability.
- Feasibility study of our own tensor/autodiff/training system. Adopted:
  ADR-0011 supersedes ADR-0001 and ADR-0007, and PyTorch is removed from the
  plan.
- Dependency audit with the four-way classification. Removed or replaced:
  PyTorch, NumPy, Pillow, cudarc, libloading, rayon, serde/serde_json, clap,
  proptest, criterion, jpeg-encoder. Our own PNG/TIFF/JPEG with a staged plan.
- Architecture revision 2: analysis engine, strategy engine with decision
  provenance, three modes, spatial maps, QC as device-side graph branches,
  sessions and variants, face subsystem design, training in Rust.
- Critical review round 2. Findings R2-1 to R2-10 fixed, among them:
  consistency ill-conditioning under blur-estimate error, the consistency step
  missing from training, dead face-mask input, host-side QC cost, and
  train/inference condition mismatch.
- Revised roadmap for phases 6–23 with exit criteria.
- ADRs 0011–0014 added; ADR-0004 and ADR-0006 revised.

### Design revision 1 (superseded in part)

### Design (Phases 1–4)
- Requirements analysis with testable IDs, constraints and threat model.
- Architecture proposal: locality invariant, model-as-data, budget invariant;
  crate structure; pipeline; GPU abstraction; SF-Net design; training design.
- Critical review. It found and fixed four high-severity defects in the first
  proposal:
  - R-1: strength `s` leaked into the Faithful path.
  - R-2: the degradation estimator only saw a downscaled thumbnail.
  - R-3: risk of the GPU abstraction taking on CPU semantics.
  - R-4: high-resolution stages would have computed over the whole halo.
  It also found three medium-severity defects (R-5 to R-7).
- Ten ADRs (Proposed).
- Repository layout, interface catalogue, and phase plan with exit criteria.
  The deviations from the requested phase order are explained.
- Dependency proposal (nothing approved or installed).
