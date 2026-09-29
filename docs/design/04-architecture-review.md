# Phase 4 — Critical Architecture Review (revision 2)

Status: **complete**. Round 2 reviews the revision-2 architecture written for
the master specification. Round 1 (the revision-1 review) is summarised in
§A. Items marked **Fixed** are already applied to `ARCHITECTURE.md`.

Review lenses (§42): architectural weaknesses, unnecessary complexity,
impossible requirements, performance, memory, training, dependencies,
numerical stability, concurrency and GPU synchronisation, security, testing.

---

## A. Round 1 findings — status under revision 2

| ID | Finding | Status now |
|----|---------|------------|
| R-1 | Strength `s` leaked into the base path | Fixed; still enforced (split conditioning `c_b` / `c_s`) |
| R-2 | Degradation estimator only saw a thumbnail | Fixed; native-resolution patch mosaic in the summary |
| R-3 | Abstraction drifting towards CPU semantics | Fixed; CPU strict mode |
| R-4 | High-resolution stages processed the full halo | Fixed; required-region analysis + `crop` |
| R-5 | Memory prediction vs. backend freedom | Fixed; `memory_requirement` per backend |
| R-6 | Overlapping writes from edge-tile shifting | Fixed; cores vs. compute windows |
| R-7 | Out-of-order completion vs. streaming sinks | Fixed; reorder buffer |
| R-8 | Second decode of streamed input | Accepted, reported |
| R-9 | Context-input mismatch between training and inference | Fixed in design; sensitivity evaluation planned |
| R-10 | Tiling cost vs. receptive radius | Carried; see R2-4 |
| R-11 | Every operator implemented twice (PyTorch + Rust) | **Resolved by ADR-0011** (single runtime) |
| R-12 | Metrics implemented twice | **Resolved**: one implementation (`sf-analysis::metrics`) |
| R-13 | GPU unvalidated here | Carried (requirements X-9, open question Q-A) |
| R-14 | Model quality needs compute we lack | Carried (Q-D) |
| R-15 | Synthetic vs. real degradation gap | Carried; also affects policy calibration (R2-12) |
| R-16 | JPEG simulation fidelity | **Improved**: our own real baseline JPEG encoder (not a simulation) now serves both output and degradation |
| R-17 | fp16 safety | Carried (measured bounds in metadata) |
| R-18 | Adversarial instability, hallucination | Carried |
| R-19 | Format limits on huge outputs | Fixed (validated up front) |
| R-20 | Breadth over depth | Carried, and larger under the master specification (R2-11) |
| R-21 | Provisional constants | Carried; every constant is labelled |

---

## B. Round 2 findings

### R2-1 — Consistency step amplified blur-estimate errors — **Fixed** (high: quality, numerical stability)
Revision 2 put the estimated blur inside the re-degradation operator `D_d`, so
that Faithful mode would not pull output back towards a blurry input. But
correcting at frequencies where the estimated blur strongly attenuates is an
ill-conditioned inversion. An overestimated blur would create ringing, and an
underestimated blur would soften the output.
**Fix:** the cutoff `fc` is also capped at the **blur-conditioning limit**
(estimated blur transfer ≥ 0.5), and correction is damped by `w ≤ 1`. **Test:**
deliberately misestimated blur (±50 %) must not increase the overshoot measure
beyond a threshold.

### R2-2 — Consistency step bolted on after training — **Fixed** (high: quality)
A fixed post-network correction that the network never saw during training
changes the output distribution in untrained ways. **Fix:** the consistency
step is part of the training graph, with `fc` and `w` sampled over their
inference ranges.

### R2-3 — Face mask input built into v1 before any face model exists — **Fixed** (medium: dead abstraction)
A face-mask input path in SF-Net v1 would be untrained dead code (§39).
**Fix:** models *declare* spatial condition inputs in their metadata. v1
declares none. The engine's generic spatial-map mechanism (needed anyway for
`m` and `w`) supplies `face_mask` to a later face-aware model version, with no
engine change.

### R2-4 — Consistency radius was outside the radius budget — **Fixed** (medium: performance)
The low-pass filter of the consistency step, and the blur inside `D_d`, have
wide kernels at low cutoffs. They add directly to the halo. **Fix:** the budget
is explicit: network ≤ 32 + consistency ≤ 16 = 48 LR px. `fc` has a lower bound
that keeps the kernel within 16. The halo cost is confined to low-resolution
compute by required-region cropping. Halo overhead is measured in Phase 10 and
Phase 13, and the budget is revised with those numbers.

### R2-5 — Condition-source mismatch (true `d` in training, estimated `d` at inference) — **Fixed in design** (high: quality)
Training on exact degradation parameters teaches the network to trust `d`
completely. At inference, `d` comes from estimators with real errors.
**Fix:** the estimator error distribution is measured on synthetic evaluation
data in Phase 11 and Phase 13. Training perturbs `d` with that **measured**
error distribution, not an arbitrary one. **Test:** restoration quality with
estimated `d` stays within tolerance of quality with true `d`.

### R2-6 — QC on full-resolution output on the host — **Fixed** (high: performance)
Scanning 8x output on the CPU after every tile would dominate run time, and it
would duplicate filters that already exist as graph operators. **Fix:** QC
detectors are graph branches that produce statistics outputs on the device.
The validator rule changes from a role-level ban on reductions to a **path
rule**: no spatial reduction on any path to a spatial output, and statistics
branches start from a core crop.

### R2-7 — Repeated-texture detection is not local — **Fixed** (medium)
Autocorrelation at large lags is neither local nor cheap. **Fix:** it runs
only on the host, on predictive-QC patches of bounded size.

### R2-8 — Automatic corrective re-render was premature complexity — **Fixed** (medium: complexity)
Re-rendering flagged regions requires random-access sinks, dependency tracking
across halos, and a second full QC cycle. **Fix:** v1 relies on *predictive*
QC (cheap, streaming-compatible) plus reporting. Corrective re-render is
postponed to Phase 17 as an optional feature, conditional on evidence.

### R2-9 — Region previews over huge sequential sources — **Fixed** (medium: performance)
Each region render would re-decode a large PNG from its first row. **Fix:** a
session spills decoded pixels once into a temporary raw tile cache when the
source is sequential and larger than the budget. The variant cache is stored
as f16, charged to the budget, with a limited region size.

### R2-10 — Estimator plugin registry without a second provider — **Fixed** (low: unused abstraction)
Removed.

### R2-11 — Scope versus capacity (project level) — **Accepted; the plan responds**
The master specification roughly doubles the scope of revision 1: analysis,
strategy, QC, faces, our own codecs, our own training framework. The risk is
many shallow subsystems. **Responses:** (1) the feasibility matrix limits v1
to capabilities whose mechanism can be validated; (2) every phase has
executable exit criteria (roadmap); (3) incomplete work is labelled
INCOMPLETE; (4) the CPU path is made correct end to end before GPU
performance work.

### R2-12 — Policy calibration on synthetic data — **Accepted** (medium: quality)
Auto-mode thresholds calibrated on synthetic degradations may misjudge real
photographs. **Mitigations:** every estimate carries uncertainty and a
validity flag; the policy falls back to conservative choices (Balanced with a
low cap) when evidence is weak or conflicting; decisions are reviewed on real
images through human evaluation.

### R2-13 — Our own training framework will be slower than vendor-library frameworks — **Accepted** (medium: training cost)
Without cuDNN/cuBLAS (§18), GPU convolution speed depends entirely on our own
kernels. **Mitigations:** implicit-GEMM convolution kernels; tensor-core
instructions through our own CUDA C (allowed: compiler intrinsics are
toolchain, not libraries); measured optimisation in Phase 21. The cost is
counted in GPU hours (Q-D).

### R2-14 — Our own codecs: correctness and security — **Accepted with controls** (medium: dependencies/security)
Our own PNG, TIFF and JPEG code is new parsing surface. **Controls:** safe Rust
only (no `unsafe` in codec crates, enforced by a lint); limits before
allocation; fuzzing; differential testing against development-only oracles;
interim external decoders stay optional until parity is shown.

### R2-15 — GPU training and inference unvalidated in this environment — **Accepted, stated** (high: testing gap)
GPU forward and backward kernels can be written but not executed here. The
CPU f64 gradient checks and CPU reference parity tests are ready to run on
hardware; until they do, GPU backends are INCOMPLETE.

### R2-16 — Face data is personal data — **Accepted, governed** (high: legal/ethical)
Manifests record consent. Face-capable models ship only after a demographic
evaluation. No processed user images are retained.

---

## C. Checks that found no defect

| Concern | Conclusion |
|---------|------------|
| Tile exactness with spatial maps | Maps are computed before tiling, from global analysis. They are cropped per window like the image and enter only local operators, so the Round-1 exactness argument still holds. |
| Autodiff correctness | Every gradient rule is checked by f64 finite differences on the CPU backend. The static graph lets the planner cover training memory too. |
| Mode separation | Faithful executes no synthesis node. Balanced vs. Reconstruction differ in `s`, `fc` and thresholds. All of this is testable structurally. |
| Explainability | Estimators report value, uncertainty and version. Strategy is a pure function with rule IDs. The report assembles both. |
| Concurrency | Unchanged from Round 1: executor channels, a mutex-protected VRAM accounting without callbacks, and write-then-rename caches. Training data workers feed a bounded queue. |
| Security of containers | `.sfm` and `.sfck` share one validated parser. Our own JSON parser has depth and size limits and is fuzzed. |
| Dependency independence | The default runtime has at most one third-party crate (`sha2`, pending decision). GPU access uses only hardware interfaces. |
| Originality | Components are general techniques. Their composition and all implementations are designed here. No pretrained network is used anywhere, including losses and metrics. |

---

## D. Result

The revised architecture covers every subsystem required by §44 Phase 3. The
remaining risks (R2-11 to R2-16, plus the carried Round-1 risks) are resolved
by hardware, data, compute or measurement, not by further design. The next
step is the revised roadmap (`05-repository-and-roadmap.md`).
