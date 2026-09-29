# Capability Feasibility (§43)

Every capability from §3 is analysed below. Related capabilities are grouped
where they share one approach.

Classification labels:
**IMPL** immediately implementable ·
**RES** requires research ·
**DATA** requires training data ·
**GPU** requires significant GPU compute ·
**SPEC** requires a specialised model ·
**POST** should be postponed.

"Immediately implementable" means the *mechanism* can be built and tested now.
For learned capabilities, production quality additionally needs DATA and GPU.
Nothing here is implemented yet.

---

### 1. AI upscaling 2x/4x/8x · low-resolution restoration · fine-detail recovery · natural-detail preservation
- **User problem:** small images lack pixels, and naive resizing is soft or aliased.
- **Approach:** SF-Net base path (distortion-trained) with degradation conditioning, progressive ×2 stages, and a consistency step.
- **Model/algorithm:** SF-Net (ARCHITECTURE §9).
- **Data:** licensed high-quality photographs (tens of thousands of images for a general model). Synthetic degradation creates the pairs.
- **Compute:** pipeline validation on CPU is possible now. A competitive model needs on the order of GPU-days to GPU-weeks (to be measured, not assumed).
- **Quality test:** PSNR/SSIM/MS-SSIM on a governed evaluation set per scale; comparison with an analytic-resampling baseline; human A/B tests.
- **Failure modes:** over-smoothing (the conditional-mean effect); texture loss on fine repetitive patterns; wrong conditioning after estimator error.
- **Classification:** IMPL (mechanism) · DATA · GPU.

### 2. Extreme upscaling (> 8x)
- **Problem:** very small sources that must reach large output sizes.
- **Approach:** compose passes (e.g. 8x then 2x). The second pass re-analyses the intermediate image.
- **Failure modes:** accumulated synthesis artefacts; the second pass sees "clean but synthetic" input, which is outside its training distribution.
- **Quality test:** the same evaluation protocol with 16x ground truth.
- **Classification:** RES · GPU. The mechanism is IMPL once 8x exists.

### 3. JPEG / compression artefact removal
- **Problem:** blocking, ringing and chroma bleeding from lossy compression.
- **Approach:** SF-Net conditioned on compression strength. Analysis measures blockiness on the detected 8-px grid phase and, when the source is a JPEG, **reads the actual quantisation tables from the file**, which gives exact evidence.
- **Data:** the same photographs, degraded with our own JPEG encoder (dual use: we need it as an output codec anyway).
- **Quality test:** evaluation at fixed quality levels; blockiness measure before and after.
- **Failure modes:** removing real texture that looks like blocking; re-compressed images with misaligned grids.
- **Classification:** IMPL (analysis + mechanism) · DATA · GPU.

### 4. Denoising / noise reduction
- **Problem:** sensor and low-light noise.
- **Approach:** a classical, signal-dependent noise estimate (robust statistics of a high-pass residual in low-texture blocks, binned by intensity). SF-Net conditioned on noise σ. The "denoise strength" control scales the σ condition, which is a real trained behaviour because the network is trained with true σ as its condition.
- **Data:** a sensor-noise model in linear light (Poisson–Gaussian) applied to clean images.
- **Quality test:** estimator accuracy against known σ; restoration PSNR at fixed σ.
- **Failure modes:** removing fine texture when noise is overestimated; colour-noise blotches when the chroma noise model is wrong.
- **Classification:** IMPL (estimator is classical and testable now) · DATA · GPU.

### 5. Sharpening
- **Problem:** soft images.
- **Approach:** learned reconstruction first. An optional classical post-sharpening stage (our own unsharp/band-boost with overshoot limiting) is controlled by a sharpening parameter. QC checks for halos.
- **Classification:** IMPL.

### 6. Deblurring — general, defocus, motion
- **Problem:** optical and camera-shake blur.
- **Approach:** mild isotropic and defocus blur are handled by SF-Net conditioned on blur width. Motion blur needs a direction and length estimate: spectral anisotropy analysis (research), then conditioning on a blur-kernel descriptor.
- **Data:** synthetic defocus discs and motion paths.
- **Failure modes:** ringing when blur is overestimated; hallucinated edges; spatially varying blur is not modelled.
- **Classification:** mild blur IMPL · DATA · GPU. Motion blur RES · DATA · GPU · possibly SPEC.

### 7. Edge reconstruction · texture reconstruction · texture enhancement
- **Problem:** lost edges and textures that cannot be recovered by deconvolution alone.
- **Approach:** the SF-Net synthesis path (adversarially trained against our own discriminator), controlled by strength `s` and a local strength map from QC.
- **Failure modes:** repeated or tiled-looking textures (detected by QC autocorrelation); texture where there should be none (flat skies).
- **Classification:** IMPL (mechanism) · DATA · GPU · RES (stability of adversarial training).

### 8. Faithful / Balanced / Reconstruction modes
- **Approach:** ARCHITECTURE §10. The modes differ in subgraph, strength, consistency band and QC thresholds.
- **Quality test:** structural tests (Faithful is independent of synthesis weights; Balanced consistency residual ≤ Faithful threshold); consistency residual as a function of mode.
- **Classification:** IMPL (mechanism). Quality depends on #1 and #7.

### 9. Creative reconstruction
- **Problem:** heavily degraded images where plausible invention is wanted.
- **Approach (v1):** Reconstruction mode at high strength. A dedicated large generative model trained from scratch would need very large data and compute.
- **Classification:** v1 via Reconstruction mode. Generative approach: GPU · DATA · RES · **POST**.

### 10. Face restoration · portrait enhancement · face-aware processing
- **Problem:** faces are the most perceptually sensitive content, and generic restoration distorts them.
- **Approach:** our own face detector gives regions and landmarks. A soft face mask enters SF-Net as a spatial condition. Consistency is stronger inside the mask (identity preservation by construction: detail must agree with the source). QC measures geometric drift between input and output landmarks.
- **Model:** a face detector (small convolutional detector trained by us) and face-conditioned SF-Net training. Very small faces (< ~24 px) would need a SPEC model with a strong prior. That prior risks identity change, so it is weighed carefully.
- **Data:** face images with documented **consent** and licence (biometric data), plus annotation (boxes, landmarks), which we may have to create ourselves.
- **Quality test:** detector precision/recall on a held-out annotated set; landmark drift; human evaluation of identity similarity (no external identity network is allowed).
- **Failure modes:** missed detections (the face gets generic processing); false positives; identity drift; demographic performance gaps (must be evaluated across groups).
- **Classification:** DATA · GPU · SPEC · RES · **POST** until the core model exists. The integration mechanism (spatial conditioning maps) is built early because it is shared with QC.

### 11. Subject-aware processing · subject characteristics
- **Approach:** classical texture/edge/saliency maps are IMPL. Semantic subject understanding (people, text, sky, foliage) needs a segmentation model trained by us.
- **Classification:** classical parts IMPL; semantic parts DATA · GPU · SPEC · POST.

### 12. Old-photo restoration · photo cleanup
- **Problem:** scratches, dust, tears, fading, film grain, halftone patterns.
- **Approach:** fading → colour/contrast correction (#13). Grain → noise conditioning. Scratches and dust → detection plus inpainting. That is a different task: inpainting is *non-local*, which conflicts with tiling locality, so it needs a dedicated, bounded-radius design.
- **Data:** a synthetic scratch/dust simulator plus real scans with a consented licence.
- **Classification:** fading/grain IMPL (via #4, #13); scratch/dust removal SPEC · DATA · GPU · RES · **POST**.

### 13. Colour correction · exposure correction · contrast correction · dynamic-range enhancement
- **Problem:** colour casts, under- or over-exposure, flat contrast.
- **Approach:** a classical global analysis (grey-world and bright-region white estimates, histogram percentiles, clipping fractions, RMS contrast) produces parameters. A local per-pixel application follows: white balance in linear light, exposure gain, a monotone tone curve, and a global dynamic-range curve. Local tone mapping comes later (RES). Off by default in Faithful mode; suggestions are always reported.
- **Quality test:** recovery of synthetic casts and exposure shifts; C-1 identity when the stage is disabled.
- **Failure modes:** "correcting" intentional artistic looks (so it is never on silently).
- **Classification:** IMPL.

### 14. Automatic image analysis · degradation detection · processing selection · strength selection
- **Approach:** the analysis engine (classical estimators first, a learned descriptor later), then a documented rule policy (ADR-0013). Thresholds are calibrated on synthetic data with known parameters and stored as a versioned policy file.
- **Quality test:** estimator accuracy on synthetic sets; policy decision tests on synthetic cases; human review on real images.
- **Failure modes:** out-of-distribution real degradations; conflicting evidence (e.g. noise vs. texture).
- **Classification:** IMPL (classical estimators and policy) · DATA (learned descriptor).

### 15. Intelligent tiling · VRAM-aware processing · very-large-image processing · batch processing
- **Approach:** ARCHITECTURE §§12–16.
- **Quality test:** seam criterion Q-3; memory accounting; large-image and failure-recovery tests.
- **Classification:** IMPL (CPU-validated). GPU paths need hardware (Q-A).

### 16. Quality control
- **Approach:** ARCHITECTURE §11. Consistency residual, colour-shift, overshoot and periodicity detectors. Predictive QC on analysis patches before the full run.
- **Classification:** IMPL for the listed detectors. "Unnatural edges" and "facial distortion" need RES and #10.

---

## Summary

| Classification | Capabilities |
|----------------|-------------|
| Mechanism implementable now (CPU-validated) | Engine, tiling, memory, analysis estimators, strategy policy, QC detectors, colour/exposure/contrast, sharpening, modes, 1x–8x SF-Net *mechanism*, training framework |
| Needs our own training data + GPU compute for real quality | Every learned capability: upscaling, denoising, deblurring, artefact removal, texture synthesis |
| Research | Motion-blur estimation, extreme upscaling, adversarial training stability, perceptual metric, local tone mapping |
| Postponed (specialised model + data) | Faces, semantic subject awareness, scratch/dust inpainting, generative creative reconstruction |
