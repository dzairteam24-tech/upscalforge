# Phase 3 — Critical Architecture Review

Status: **complete**. This review examined the first Phase 2 proposal.
Findings marked **Fixed** have already been applied to `ARCHITECTURE.md`.
**Accepted** means the risk is understood and consciously carried.
**Deferred** means it is scheduled for a named phase.

Review lenses: correctness, image quality, memory, concurrency, GPU
synchronisation, numerical stability, performance, complexity, security,
testability, originality, and project risk.

---

## A. Defects found in the first proposal

### R-1 — Strength `s` leaked into the base path — **Fixed** (severity: high)
The first diagram built a single condition vector `c = embed(d, g, s)` and
used it to modulate *every* body block. The shared body, and therefore the
base output, would then have depended on `s`. That contradicts F-3/F-4
("Faithful is unaffected by synthesis; `s = 0` ≡ Faithful") and would make
the "structural guarantee" false.
**Fix:** split the conditions. `c_b = embed(d, g)` drives the body and base
path. `c_s = embed(d, g, s)` drives only the synthesis trunk. A test asserts
that Faithful output is bit-identical for any value of `s` and any synthesis
weights.

### R-2 — The degradation estimator was blind to degradation — **Fixed** (high)
The context graph originally saw only a ≤ 256 px downscaled thumbnail.
Downscaling averages away the evidence the estimator needs: sensor grain,
8×8 compression blocking, ringing and sharpening halos. On a large image the
estimate would have been close to meaningless.
**Fix:** the analysis summary now contains a **mosaic of native-resolution
patches** on a deterministic grid (for degradation) and a thumbnail (for
global colour and tone). Both can be collected in a single streaming pass.

### R-3 — The GPU abstraction could drift towards CPU semantics — **Fixed** (high)
Only the CPU backend can be executed in this environment. An abstraction
that is exercised only by a CPU implementation tends to acquire hidden
assumptions: synchronous completion, host-visible buffers, free
reallocation.
**Fix:** the CPU backend follows the asynchronous contract, with separate
"device" allocations and explicit copies. A **strict mode** (on in tests)
detects host access before an event has signalled, and freeing of in-flight
buffers.

### R-4 — High-resolution stages would process the body's halo — **Fixed** (high, performance)
With exact tiling, the halo `r` is needed only for the body. Running the ×2,
×4 and ×8 stages over the whole halo-extended window would multiply
high-resolution compute, where most FLOPs and memory are, by
`((T + 2r)/T)²`. For T = 128 and r = 32 that is ×2.25.
**Fix:** a required-region analysis and planner-inserted `crop` nodes, so
that every tensor is computed only over the region its consumers need.

### R-5 — Exact memory prediction conflicted with backend freedom — **Fixed** (medium)
The engine planned memory generically, but backends are expected to choose
their own layouts and fusions, which changes real memory use.
**Fix:** `Device::memory_requirement(graph, shape, precision)` is a pure query
that each backend implements; the generic planner is the default
implementation. The VRAM manager uses only backend-reported figures. The
auto-tuner still solves analytically by querying at two shapes (memory is
affine in H·W). A test checks the affine assumption for every backend.

### R-6 — "Shift edge tiles inward" created overlapping output writes — **Fixed** (medium)
Shifting edge tiles to keep one uniform shape made output regions overlap.
That makes write ownership ambiguous and breaks streaming sinks.
**Fix:** a strict separation between **non-overlapping cores** (written
exactly once) and **uniform compute windows**.

### R-7 — Pipelined executor ordering — **Fixed** (medium, concurrency)
Streaming encoders need rows in order. Any executor that allows out-of-order
completion would corrupt output.
**Fix:** cores are delivered to sinks in plan order, through a reorder buffer
in the pipelined executor. A test injects artificial delays per tile.

### R-8 — The analysis pass needs a second read of streamed input — **Accepted, made explicit** (low)
The global analysis must finish before the first tile runs, so a sequential
source is decoded twice. The alternative (buffering the whole image) breaks
S-3. The cost is reported in job timings. Non-rewindable inputs are spooled
to a temporary file, charged against the budget.

### R-9 — Train/inference mismatch of the context input — **Fixed in design, residual risk accepted** (medium, quality)
At inference the context graph sees a summary of the whole image. In training
it would only have seen the crop.
**Fix:** degrade a larger *context window*, build the summary from it with the
inference summary operator, and crop inside it. Residual risk: a whole
image is not the same as a window. Mitigation: a sensitivity evaluation of `d`
across summary sources (Phase 13).

---

## B. Risks and weaknesses carried forward

### R-10 — Exact tiling cost depends on the receptive radius (quality vs. speed)
The theoretical receptive radius of a deep convolutional network grows with
depth. Exact tiling pays for the whole theoretical radius, even though the
*effective* field is much smaller.
**Mitigations:** (1) a radius **budget** is enforced at model build time;
(2) the half-rate stream gives cheap context without extra depth;
(3) R-4 confines the halo cost to low-resolution compute; (4) the
bounded-error mode uses a smaller halo, with its **measured** maximum
deviation reported. The radius budget itself is provisional until Phase 12
measures the trade-off.

### R-11 — Two implementations of every operator — **Accepted**
The DSL (PyTorch), the CPU backend, CUDA and Vulkan all implement the operator
set. **Mitigations:** keep the operator set small (§7.2); parity tests for
every operator on every backend against the CPU reference; the operator set is
versioned, and a model declares which version it needs.

### R-12 — Metrics implemented twice (Rust and Python) — **Accepted with rule**
Training monitors PSNR/SSIM in Python.
**Rule:** only `sf-quality` numbers are used for regression gating, release
decisions and published results. The Python metrics are for monitoring only.
A cross-check test on shared fixtures keeps them honest.

### R-13 — GPU backends cannot be validated in this environment — **Accepted, stated plainly**
No GPU is available. Backends written here remain labelled **unvalidated**
until their parity and memory tests pass on real hardware. No GPU
performance figure will be published without a real measurement.

### R-14 — Model quality depends on compute we do not have here — **Accepted, stated plainly**
No pretrained weights are allowed (O-2), and there is no GPU. Any model
trained in this environment is a **pipeline-validation model**, not a
product-quality model. MODEL.md and the model metadata will say so.

### R-15 — Synthetic degradations do not match real-world images — **Accepted**
This is a domain gap. **Mitigations:** a physically motivated capture →
process → distribution grammar; logged parameters; an evaluation track on
*real* degraded images with human A/B evaluation (no ground truth exists
there); release gating that does not rely on synthetic PSNR alone.

### R-16 — JPEG and WebP artefact fidelity in the degradation pipeline — **Deferred to Phase 13**
Our own block-DCT JPEG simulation (standard baseline JPEG: colour conversion,
chroma subsampling, 8×8 DCT, quantisation with quality-scaled tables) is
independent and deterministic. It may still differ from real encoders in
detail. WebP artefacts are harder to simulate faithfully. **Plan:** use the
own simulation first. Cross-validate against a real encoder only if the
user approves that optional dependency, and measure the difference.

### R-17 — fp16 numerical safety — **Deferred to Phases 11 and 14**
Activations can overflow in fp16. **Plan:** export measures the fp16-vs-fp32
error on a validation set and stores the bound in metadata. The runtime allows
fp16 only when the model declares it. A debug validation mode scans for
non-finite values. The fallback is fp32.

### R-18 — Adversarial training instability and hallucination — **Accepted**
Stage B (synthesis) is inherently less stable and can hallucinate structure,
especially on text and faces. **Mitigations:** Stage A weights are frozen; the
synthesis contribution is scaled by the user (`s`); the consistency step
bounds low frequencies; human evaluation gates releases; Faithful mode is
unaffected by construction.

### R-19 — Format constraints on huge outputs — **Fixed in design**
WebP is limited to 16383 px per side and needs a full buffer for encoding.
JPEG is limited to 65535 px. Classic TIFF is limited to 4 GiB. Validation
checks every one of these **before** processing. TIFF switches to BigTIFF.
Very large outputs need a streaming-capable format, and the error message
names one.

### R-20 — Scope and breadth risk (project level)
The brief covers roughly the scope of a small team's multi-year product. The
main risk is many shallow subsystems. **Mitigation:** each phase ends with
executable validation (exit criteria in `04-repository-and-plan.md`).
Incomplete subsystems are labelled as incomplete. The CPU path is made
correct end to end before GPU performance work begins.

### R-21 — Premature numbers
Several constants in the architecture are provisional: the radius budget ≤ 32,
the summary sizes, the queue depth of 2, the safety reserve. Each is marked
provisional, and the phase that must measure and justify it is named.

---

## C. Checks that found no defect (and why)

| Concern | Conclusion |
|---------|------------|
| Seams in exact mode | Every output pixel is computed from the same inputs, with the same border semantics, as in whole-image inference. Alignment and canonical padding make stride positions match. The remaining difference is floating-point operation order, bounded by Q-3's tolerance. For the CPU backend, reduction order depends only on the kernel, not on the pixel position, so results are expected to be bit-identical. This will be tested, not assumed. |
| Tile-size change mid-image (OOM recovery) | Safe in exact mode for the same reason as above. In bounded-error mode the planner re-plans from the next band boundary, which keeps the deviation bound. |
| Memory leaks on error paths | Device memory is owned by RAII arena handles in the VRAM manager. Error paths drop the handles. Tests allocate, fail and check that accounting returns to baseline. |
| GPU synchronisation | All cross-queue and host dependencies are explicit `Event`s. Strict mode (R-3) tests the discipline on CPU. Staging buffers are recycled only after their event has signalled. |
| Race conditions | Shared mutable state is limited to: the VRAM manager (mutex-protected accounting), the tuning cache (file write-then-rename), and executor channels. There are no lock-ordering cycles: the VRAM manager never calls out while holding its lock. |
| Malicious model files | The format is pure data. Every size and offset is validated before allocation. Ops are whitelisted. The locality rule is enforced by the validator. The parser will be fuzzed. |
| Plugin code execution | No native dynamic loading in v1 (ADR-0008). |
| Originality | The components are general techniques: residual convolution, gating, pixel shuffle, per-channel modulation, staged training, adversarial losses. Their composition (Dual-Rate Block, split conditioning, fixed consistency step, patch-mosaic analysis, exact halo tiling with required-region cropping, degradation grammar) is designed here from requirements. No published architecture or degradation recipe is reproduced. Pretrained perceptual networks are avoided in training entirely. |

---

## D. Result

The revised architecture meets every Phase 1 requirement in design. The
carried risks (R-10 to R-21) are ones that measurement, hardware or compute
must resolve; further design work cannot. The next step is Phase 4:
repository and module design, interfaces, and the implementation plan with
exit criteria.
