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
- our own neural architecture (SF-Net), to be trained later by our own
  training framework (INCOMPLETE);
- optional, clearly labelled external models (ADR-0015).

## Status

**Usable on the CPU with the classical engine.** Optional external
Real-ESRGAN models can be converted and run. GPU backends and ScaleForge's own
model are **INCOMPLETE**.

| Area | State |
|------|-------|
| Design (phases 1–5) | Complete — `docs/design/`, `ARCHITECTURE.md`, `docs/adr/` |
| Core, graph and CPU compute (6–7) | Implemented and tested |
| GPU backends (8) | **INCOMPLETE** — postponed until the GPUs are installed |
| Memory, VRAM accounting, exact tiling (9–10) | Implemented and tested |
| Image engine: own PNG, JPEG, TIFF/BigTIFF, ICC→sRGB, resampling, analysis (11) | Implemented and tested |
| Model runtime (`.sfm`) and safe `.pth` import (12) | Implemented; validated on the real `RealESRGAN_x4plus.pth` (SRVGG not yet on a real file) |
| Own model SF-Net and training (13–14) | **INCOMPLETE — planned for later** (see [`training/`](training/README.md)) |
| Modes, strategy, QC, Adobe Stock export (15, 17) | Implemented (policy thresholds provisional) |
| CLI and benchmark (18, 20) | Implemented |
| Optimisation (21) | Started: PNG encoding and postprocessing are parallel (about 3x faster end to end, see [BENCHMARKS.md](BENCHMARKS.md)) |
| WebP input (4) | Implemented: own lossless and lossy decoder; WebP output is INCOMPLETE |
| Images larger than memory (4) | Classical path processed band by band, bit-identical to whole-image processing; PNG read in bands; PNG/TIFF written in bands. `--stream`, `--band-rows`, `--memory` |
| Not yet supported | WebP output, animated WebP, face restoration, SwinIR/HAT; band-by-band processing with AI models, export profiles or JPEG output |

Zero third-party crates; see [`DEPENDENCIES.md`](DEPENDENCIES.md).

## Quick start

```sh
cargo build --release
B=target/release/scaleforge

$B doctor                                   # self-check
$B analyze photo.jpg                        # what is wrong with this image?
$B upscale photo.jpg -o big.png --scale 4   # faithful x4, classical engine
$B upscale photo.jpg -o stock.jpg --export adobe-stock --report stock.json
$B batch in/ -o out/ --scale 2 --ext jpg
$B help
```

- **Faithful** (the default) never invents detail.
- **Balanced** and **Reconstruction** can use an external model
  (`--model`); see [`MODEL.md`](MODEL.md).
- Every run can write a JSON report that explains each decision.

More documents:

- [`BENCHMARKS.md`](BENCHMARKS.md)
- [`SECURITY.md`](SECURITY.md)
- [`BUILD.md`](BUILD.md)
- [`CONTRIBUTING.md`](CONTRIBUTING.md)

### Adobe Stock profile

`--export adobe-stock`:

- chooses the scale that reaches the 4 MP minimum;
- stays within 100 MP;
- writes sRGB JPEG under 45 MB;
- refuses non-commercial models;
- prints a compliance verdict and an AI-use disclosure.

Inputs that cannot reach 4 MP even at x8 are refused. The rules are data in
`policy/export/adobe-stock-photo.json`. Re-check them against Adobe's current
contributor rules.

## Licence

Apache-2.0. See [`LICENSE`](LICENSE).
