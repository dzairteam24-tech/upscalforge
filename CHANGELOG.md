# Changelog

## Unreleased

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
