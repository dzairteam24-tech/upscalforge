# Changelog

## Unreleased

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
