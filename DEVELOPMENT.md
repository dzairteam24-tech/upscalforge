# Development Guide

## Principles
- Read `ARCHITECTURE.md` and the ADRs before changing a subsystem. Record
  significant decisions as a new ADR.
- **Originality:** no copied or translated code, tests, documentation or
  comments from other projects. External pretrained models are allowed only
  under ADR-0015's rules.
- **Dependencies:** none may be added without an entry in `DEPENDENCIES.md`
  and owner approval.
- **No `unsafe`:** forbidden workspace-wide (`unsafe_code = "forbid"`). The
  only planned exceptions are the GPU backend crates' FFI layers, each with a
  documented justification.
- **Honesty:** incomplete functionality is labelled `INCOMPLETE` in docs and
  errors. No placeholder implementations are presented as working.

## Repository layout
See `docs/design/05-repository-and-roadmap.md`. Crates appear only in the
phase that fills them.

| Crate | State |
|-------|-------|
| `crates/sf-core` | Foundation types, JSON, RNG (Phase 6) |

## Before every commit
```sh
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```

## Tests
- Unit tests live next to the code (`#[cfg(test)]`).
- Property tests use `sf_core::Rng` with a fixed seed, so failures reproduce
  exactly.
- Robustness tests feed mutated input to parsers. Coverage-guided fuzz
  targets are added with the first binary parsers (Phase 11).

## Phase workflow
Each phase ends with a self-review (§42 of the specification) and a
`CHANGELOG.md` entry listing what was reviewed and fixed.
