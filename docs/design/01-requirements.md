# Phase 1 — Requirements Analysis (revision 2)

Status: **complete (design phase)**. No production code exists.

Source: the *ScaleForge Master Specification* (sections referenced as §N).
It supersedes the first brief. Revision 1 of this document analysed that
brief; its requirement IDs are kept where they still apply, and new ones are
added.

On the product reference (§2): the capability list in §3 is the only input
taken from it. No attempt was made to learn how any existing product works
internally, and none will be.

---

## 1. What changed from revision 1

| Area | Revision 1 | Master specification | Effect |
|------|-----------|----------------------|--------|
| Modes | Faithful, Reconstruction | Faithful, **Balanced**, Reconstruction (§9) | A third mode with its own processing behaviour |
| Intelligence | Degradation estimate only | Analysis → strategy → reconstruction → **quality control** (§4–6, §11, §14) | New subsystems: analysis engine, strategy engine, QC engine |
| Faces | Non-goal | Dedicated face-aware subsystem (§10) | New subsystem, with data, privacy and compute implications |
| Scope | Upscaling + restoration | Also colour/exposure/contrast correction, old-photo restoration, deblurring, extreme upscaling (§3) | Feasibility matrix required (§43) |
| API | Full image + region preview | Also crop, face-region preview, before/after, strength and strategy variants (§12) | Variant-evaluation API |
| Training framework | PyTorch (research only) | Runtime must not depend on it; **feasibility of our own tensor/autodiff system** required (§31) | Re-decided: see §5 and ADR-0011 |
| Dependencies | Mature codec crates, serde, clap | Minimal core dependencies; four-way classification; no cuDNN/cuBLAS (§18–20) | Dependency audit redone (`DEPENDENCIES.md`) |

---

## 2. Requirements

IDs from revision 1 (F-, I-, C-, S-, E-, G-, M-, T-, A-, Q-, N-) remain valid
unless listed as changed. The full revision-1 list is in git history
(commit `cf50ab6`). New and changed requirements:

### 2.1 Unified image intelligence (§4–6, §14)

| ID | Requirement | Acceptance criterion |
|----|-------------|----------------------|
| U-1 | The pipeline analyses the image before choosing how to process it | Every job report contains an `AnalysisReport`. Processing parameters are traceable to it. |
| U-2 | The analysis engine estimates: resolution and effective resolution, noise (level and signal dependence), compression, blur, motion vs. defocus, sharpness, edge quality, texture density, dynamic range, exposure, contrast, colour cast, face presence, subject characteristics, overall severity | Each estimator has a documented algorithm, an accuracy test on synthetic degradations with known parameters, and a stated validity range. Estimators that do not exist yet are reported as `unavailable`, never guessed. |
| U-3 | Degradation analysis produces a descriptor in **physical units** (e.g. noise σ in code values, blur width in pixels, compression quality) | The same quantities are used as training conditions, so analysis results genuinely drive the network (§6). |
| U-4 | Auto mode chooses the processing path, model, scale (when a target size is given), mode, strength, precision, tiling, face processing and colour processing | Each decision in the report records its value, its source (`user`, `auto`, `default`), the rule that produced it, and the evidence used (§14). |
| U-5 | Manual control over model, scale, strength, denoise, deblur, face enhancement, texture reconstruction, fidelity, sharpening, colour processing, precision and tile strategy | Each control maps to a documented parameter of the model or pipeline. A test checks that changing each control changes the computation (§15). |

### 2.2 Modes (§9) — replaces F-3/F-4

| ID | Requirement |
|----|-------------|
| F-3' | **Faithful**: the synthesis path is not executed. Consistency with the source is enforced over the widest frequency band the measured noise allows. |
| F-4' | **Balanced**: the synthesis path runs at a strength chosen by analysis and capped. Consistency is as strict as in Faithful. QC can reduce strength locally. |
| F-4'' | **Reconstruction**: the synthesis path runs at a user strength `s ∈ [0,1]`. Consistency is limited to a lower frequency band. Colour consistency is still enforced. |
| F-7 | The modes differ in executed subgraph, synthesis strength, consistency band and QC thresholds. A test proves each difference. |

### 2.3 Face-aware processing (§10)

| ID | Requirement |
|----|-------------|
| FA-1 | Detect face regions (bounding box, confidence, landmarks where available) with our own trained detector. |
| FA-2 | Face regions receive specialised processing *inside* the main reconstruction, through spatial conditioning. They are not pasted in from a separate generator. |
| FA-3 | No generic face replacement. There are no reference-face dictionaries and no identity-agnostic face priors that overwrite the input. Consistency is enforced more strongly inside face regions. |
| FA-4 | Identity drift is measured by QC. The measurement method must itself be our own; see feasibility. |
| FA-5 | Face data is biometric data. Dataset consent and licensing, and the handling of processed user images, must be documented (privacy). |

### 2.4 Quality control (§11)

| ID | Requirement |
|----|-------------|
| QC-1 | Output is checked for: consistency loss (hallucination or structure loss), colour shift, haloing, oversharpening, repeated textures, tile seams, unnatural edges, and facial distortion (when faces are processed). |
| QC-2 | QC results are reported per job and as a coarse spatial map. |
| QC-3 | In Balanced and Reconstruction modes, QC findings can **automatically lower the local synthesis strength**. Every such adjustment is reported. |
| QC-4 | QC does not break tiling exactness or streaming. |

### 2.5 Preview and region processing (§12)

| ID | Requirement |
|----|-------------|
| P-1 | Process a full image, a region, or a crop. A region's output equals the corresponding region of the full-image output, because it uses the full-image analysis context. |
| P-2 | Face-region preview (depends on FA-1). |
| P-3 | Before/after and variant comparison (strengths, modes, models) without recomputing shared work. |

### 2.6 Scales

| ID | Requirement |
|----|-------------|
| F-1' | Native 1x (restoration without upscaling), 2x, 4x and 8x. Revision 1 missed 1x, but denoising, deblurring and artefact removal at the original size are listed capabilities. |
| F-8 | Extreme upscaling (> 8x) is done by composing passes. The quality of composed passes is a research item. |

### 2.7 Engine independence (§17–19, §22, §31)

| ID | Requirement |
|----|-------------|
| D-1 | Our own tensor representation, operators, graph execution, memory planning, serialisation and validation. |
| D-2 | Our own GPU compute kernels. The lowest reasonable interface to the hardware: the CUDA driver API and the Vulkan API. No cuDNN, cuBLAS, TensorRT, ONNX Runtime, OpenVINO or similar. |
| D-3 | The production runtime has no dependency on any AI framework. |
| D-4 | Every dependency is classified (core / hardware-system interface / build tooling / optional) and audited before use (§19–20). |
| D-5 | Mature security primitives are not rewritten without need (§35). |

### 2.8 Model metadata (§16) — extends M-*

Every `.sfm` declares its architecture ID and hash, version, capabilities
(tasks), scales, modes, precisions (with measured error bounds), receptive
field (derived and verified), memory-requirement coefficients, training
information (run ID, steps, configuration hash), dataset provenance (manifest
hash and licence summary), licence, and an integrity hash.

### 2.9 Testing additions (§34)

Large-image tests and failure-recovery tests are required categories, alongside
those already listed.

---

## 3. Contradictions and tensions in the specification

Each tension is stated with the resolution that the architecture adopts.

| # | Tension | Resolution |
|---|---------|------------|
| X-1 | "No external model weights" (§8), but face detection, identity checks and perceptual metrics usually rely on pretrained networks. | Every learned component (face detector, landmarks, any identity or perceptual measure) must be trained by us. Where no licensed data exists, the capability is marked INCOMPLETE rather than filled with external weights. LPIPS as usually defined depends on pretrained networks, so it is **excluded**. A perceptual metric of our own needs human-judgement data (research item). |
| X-2 | "Our own autodiff/training framework" (§31) vs. "do not produce technically inferior code" (§19, §41). | A feasibility study (§5 below) concludes that our own framework is feasible **because our operator set is small and static**. It is adopted (ADR-0011). The cost is recorded: training throughput will lag vendor-library frameworks until our kernels are optimised. |
| X-3 | Minimal external dependencies (§18, §21) vs. "do not sacrifice security" and "do not rewrite mature security primitives" (§35). | Codecs are *format interfaces* (§21 category B), not product logic. In **safe Rust**, a decoder bug is a denial-of-service risk rather than a memory-corruption risk, and our resource limits bound that. So our own codecs are acceptable where fuzzing and differential testing against mature implementations (as development-only test oracles) are in place. Cryptographic hashing (SHA-256) stays a mature dependency (D-5). |
| X-4 | "Creative reconstruction" and "extreme upscaling" (§3) are capabilities typically served by large generative models, but the model must be trained from scratch by us. | Reconstruction mode covers controlled detail synthesis. A large generative model trained from scratch needs data and compute far beyond this project's current means. It is classified *requires significant GPU compute; postponed*. |
| X-5 | "Every automatic decision explainable" (§14) vs. learned estimators, which are opaque. | Decisions are made by a documented rule policy over **physical measurements**. Learned estimators contribute measurements whose values are reported. They never make decisions directly. |
| X-6 | Face-specific processing and QC-driven local corrections vs. seam-free tiling. | Both are expressed as **spatial maps** (face mask, strength map) that are local inputs to the per-tile computation. Maps are computed from global analysis *before* tiling, so all tiles see consistent values (ADR-0012). |
| X-7 | "Remove external dependencies" vs. "PNG/JPEG/WebP/TIFF support now". | Our own PNG, TIFF and baseline-JPEG encoder come first. JPEG decoding (progressive included) and WebP decoding start as optional, feature-gated external crates. They are replaced by our own implementations once differential fuzzing shows parity. This is a staged plan; the decision is the owner's (DEPENDENCIES.md). |
| X-8 | The phase order puts GPU execution (Phase 8) before the model (Phase 13), but the operator set is only final once the model exists. | Phase 8 builds the GPU execution layer and kernels for the operator set known by then. Kernels for operators added in Phase 13 are added in Phase 13, each with parity tests. |
| X-9 | GPU execution and GPU tests are required, but the development environment has **no GPU**. | GPU code can be written but not validated here. It remains **INCOMPLETE (unvalidated)** until GPU hardware is available. See open question Q-A. |

---

## 4. Unrealistic assumptions (made explicit)

1. **"Professional quality" for every §3 capability.** Quality comes from
   training data and compute. With no pretrained weights and no GPU in this
   environment, models trained here can only **validate pipelines**. The
   capability-feasibility matrix
   (`docs/design/02-capability-feasibility.md`) classifies each capability
   honestly.
2. **Face processing without external models.** It needs our own face
   detector and a face-aware restoration model trained on consented, licensed
   face data. Such datasets exist but are rarer. Many common face datasets
   were scraped without consent or carry non-commercial terms.
3. **Automatic QC that "fixes" problems.** QC can detect measurable
   symptoms (consistency loss, colour shift, overshoot, periodicity) and reduce
   synthesis strength. It cannot guarantee aesthetic correctness. Human
   evaluation remains necessary.
4. **Our own GPU kernels competitive with vendor libraries immediately.**
   This is realistic only after focused optimisation, and it must be measured
   (§41).

---

## 5. Feasibility analysis: our own tensor, autodiff and training system (§31)

| Component | Work | Risk | Verdict |
|-----------|------|------|---------|
| Tensor representation and graph IR | Already required by the inference runtime | Low | Shared with inference |
| Reverse-mode autodiff | A transformation on our **static** graph IR: for each op, emit its gradient ops. About 20 ops, each needing derivative rules. | Medium. Checked mechanically with finite-difference gradient tests in f64 on the CPU backend. | **Feasible** |
| Backward kernels | For convolution: the input gradient is a transposed correlation, and the weight gradient is a correlation of input and output gradient. The others are element-wise or data movement. Needed on CPU and later GPU. | Medium. GPU performance is the main cost. | Feasible; performance tuned in Phase 21 |
| Optimiser (AdamW), schedules, gradient clipping | Element-wise update ops | Low | Feasible |
| Memory for training | The static planner handles forward + backward graphs. Rematerialisation can be added if needed. | Medium | Feasible |
| Mixed precision | fp16/bf16 compute with fp32 master weights and loss scaling | Medium | Later optimisation |
| Multi-GPU data parallelism | Gradient all-reduce between devices | High | Postponed |
| Data pipeline | Our own decoders, our own degradation library, worker threads | Low–medium | Feasible |
| Checkpoints | Our own container (same parser infrastructure as `.sfm`) | Low | Feasible |

**Conclusion.** A complete, general-purpose deep-learning framework would be
unrealistic. A framework restricted to **our** static graphs and **our** small
operator set is realistic. It also removes a structural weakness of
revision 1: training and inference implementing every operator twice (review
item R-11). Training and inference now run the same operators on the same
runtime. Accepted cost: GPU training throughput will be lower than with
vendor-optimised frameworks until our kernels mature. More GPU time is
therefore needed per experiment. Decision recorded in ADR-0011.

---

## 6. Missing requirements (added)

| ID | Requirement | Reason |
|----|-------------|--------|
| MR-1 | Privacy: no telemetry. Metadata policy strips location data by default. Face data in datasets is documented with consent status. | Faces and user photos are personal data |
| MR-2 | Model authenticity (signatures) in addition to integrity (hashes) | Model files are distributed; a hash inside the file proves nothing about who made it. Postponed; would use a mature signature primitive (D-5). |
| MR-3 | Public API versioning and stability policy | Needed by the GUI and future bindings |
| MR-4 | Determinism statement per backend | Needed for regression testing and reproducibility |
| MR-5 | Evaluation-set governance: evaluation images must never enter training (hash-checked) | Metric validity |
| MR-6 | Unified-vs-specialised model experiment defined before any specialised model is built (§7) | Avoids unnecessary model duplication |

---

## 7. Open questions for the project owner

| ID | Question |
|----|----------|
| Q-A | Can a GPU environment (NVIDIA and/or Vulkan-capable) be made available for validation? Without one, Phase 8 stays unvalidated. |
| Q-B | Approve the staged codec plan and each dependency in `DEPENDENCIES.md`. |
| Q-C | Training data: which sources, with which licences, can be used? Any face data must have documented consent. |
| Q-D | Is training compute planned (GPU hours)? This determines whether production-quality models are achievable at all. |
