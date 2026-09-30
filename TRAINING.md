# Training — INCOMPLETE (not started)

ScaleForge's own model (SF-Net, ARCHITECTURE §9) **has not been trained, and
the training system has not been written**. This is a deliberate decision by
the owner: training starts once the GPUs are installed and data is ready.
The placeholder is [`training/`](training/README.md).

## Prerequisites

| Item | State |
|------|-------|
| GPU backend (Phase 8: CUDA driver API) | INCOMPLETE — no GPU in the development environment |
| Autodiff, losses, optimiser (`sf-train`) | Not started |
| Degradation synthesis (`sf-degrade`) | Not started. Our own JPEG encoder, noise model and resampling already exist and will be reused |
| Dataset with documented licences (manifests) | Not assembled |
| Evaluation set, kept separate from training data | Not assembled |

## Planned design (summary; details in ARCHITECTURE §§9, 18–20 and ADR-0011)

- Training is written in Rust on our own graph and compute system. There is
  no PyTorch, cuDNN or cuBLAS. Every gradient rule is checked with f64 finite
  differences on the CPU backend.
- Training pairs are synthesised from clean photographs: blur, sensor noise
  in linear light, resampling, and JPEG with our own encoder. The degradation
  parameters become the model's conditioning input. During training they are
  perturbed by the **measured** error of our estimators (review finding R2-5).
- The consistency step is part of the training graph (R2-2).
- Everything is reproducible: a seed produces identical pairs and identical
  first steps, and a resumed run matches an uninterrupted one.
- Export writes a `.sfm` with `provenance: "scaleforge"` and the training
  manifest's hash.

## Compute estimate

Unmeasured. The two RTX 3090s (24 GB each) are enough to train SF-Net-sized
models (tens of millions of parameters at most). Real time depends on our own
kernels, which do not exist yet (review R2-13). No duration is claimed until
it is measured.
