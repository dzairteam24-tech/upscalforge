# ScaleForge

ScaleForge is an independently engineered platform for AI image restoration,
enhancement and upscaling (1x/2x/4x/8x). It is planned around:

- our own Rust engine, tensor/graph system and GPU kernels (CPU, CUDA driver
  API, Vulkan);
- exact seam-free tiling for images larger than VRAM or RAM;
- an analysis engine that measures degradations before deciding how to
  process;
- three reconstruction modes (Faithful, Balanced, Reconstruction) with quality
  control;
- our own neural architecture (SF-Net), trained by our own training framework
  on data with documented provenance.

## Status

**Design phase. No functional software exists yet.**

| Specification phase | State |
|---------------------|-------|
| 1 Requirements analysis | Complete — [`docs/design/01-requirements.md`](docs/design/01-requirements.md), [`docs/design/02-capability-feasibility.md`](docs/design/02-capability-feasibility.md) |
| 2 Dependency audit | Complete — [`DEPENDENCIES.md`](DEPENDENCIES.md). **No dependency approved or installed.** |
| 3 Architecture | Complete — [`ARCHITECTURE.md`](ARCHITECTURE.md), [`docs/adr/`](docs/adr/) |
| 4 Critical review | Complete — [`docs/design/04-architecture-review.md`](docs/design/04-architecture-review.md) |
| 5 Repository design and roadmap | Complete — [`docs/design/05-repository-and-roadmap.md`](docs/design/05-repository-and-roadmap.md) |
| 6+ Implementation | Not started |

No model weights exist. ScaleForge uses no external models or weights. Every
model will be trained by ScaleForge's own training system.

## Licence

Apache-2.0. See [`LICENSE`](LICENSE).
