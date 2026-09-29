# Architecture Decision Records

Each ADR records one significant decision: its context, the decision itself,
the alternatives considered, and the consequences. Status values:
Proposed, Accepted, Superseded by ADR-XXXX.

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-language-and-process-split.md) | Rust engine, Python/PyTorch training | Superseded by 0011 |
| [0002](0002-model-file-format.md) | Own data-only model format `.sfm` | Proposed |
| [0003](0003-gpu-abstraction-at-graph-level.md) | GPU abstraction at graph-execution level | Proposed |
| [0004](0004-locality-invariant-and-exact-tiling.md) | Locality invariant and exact tiling | Proposed |
| [0005](0005-native-encoding-colour-processing.md) | Process colour in native encoding | Proposed |
| [0006](0006-codecs-behind-own-interface.md) | Codecs behind our own interface, own implementations staged | Proposed (revised) |
| [0007](0007-single-source-model-definition.md) | Single-source model definition with parity tests | Superseded by 0011 |
| [0008](0008-no-native-dynamic-plugins-in-v1.md) | No native dynamic plugins in v1 | Proposed |
| [0009](0009-planned-memory-and-autotuning.md) | Planned memory, arenas, analytic-then-measured tuning | Proposed |
| [0010](0010-threads-not-async-scheduler.md) | Synchronous-first scheduler on threads | Proposed |
| [0011](0011-own-training-framework.md) | One Rust runtime for training and inference; our own autodiff | Proposed |
| [0012](0012-spatial-maps-for-local-variation.md) | Spatially varying behaviour through precomputed spatial maps | Proposed |
| [0013](0013-explainable-rule-based-strategy.md) | Explainable, rule-based strategy over physical measurements | Proposed |
| [0014](0014-reconstruction-modes.md) | Faithful, Balanced and Reconstruction as distinct computations | Proposed |
| [0015](0015-classical-engine-and-optional-external-models.md) | Classical engine primary; external pretrained models as optional, labelled add-on | **Accepted** |

All ADRs stay **Proposed** until the project owner accepts the architecture.
