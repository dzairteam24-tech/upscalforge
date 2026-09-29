# ScaleForge

ScaleForge is an independently designed platform for AI image upscaling
(2x/4x/8x) and restoration. Its main parts are a Rust inference engine with
pluggable CPU/CUDA/Vulkan backends, exact seam-free tiling for images larger
than memory, its own neural architecture (SF-Net), and a training system with
a documented dataset-provenance model.

## Status

**Design phase. No functional software exists yet.**

| Phase | State |
|-------|-------|
| 1 Requirements | Complete — [`docs/design/01-requirements.md`](docs/design/01-requirements.md) |
| 2 Architecture | Complete — [`ARCHITECTURE.md`](ARCHITECTURE.md), [`docs/adr/`](docs/adr/) |
| 3 Architecture review | Complete — [`docs/design/03-architecture-review.md`](docs/design/03-architecture-review.md) |
| 4 Repository design and plan | Complete — [`docs/design/04-repository-and-plan.md`](docs/design/04-repository-and-plan.md) |
| 5+ Implementation | Not started. Waiting for architecture acceptance and dependency approval ([`DEPENDENCIES.md`](DEPENDENCIES.md)) |

No model weights exist. ScaleForge does not use pretrained external models;
every model will be trained by the ScaleForge training system.

## Licence

Apache-2.0. See [`LICENSE`](LICENSE).
