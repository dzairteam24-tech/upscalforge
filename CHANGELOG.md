# Changelog

## Unreleased

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
