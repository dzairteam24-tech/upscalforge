# training/ — ScaleForge's own model (SF-Net)

> **NOT IMPLEMENTED — planned for later.**
>
> This folder is deliberately empty. Training ScaleForge's own model will be
> done later, once the GPUs (2x RTX 3090) are installed and a training
> dataset with documented licences and provenance has been assembled.

What exists today:

- the classical engine (`sf-classic`), which is the primary processing path;
- optional external models (ADR-0015) imported with
  `scaleforge convert-model`. These are always labelled `external` and are
  never presented as ScaleForge models.

What will live here: training configurations, dataset manifests, and run
records. The training code itself will be Rust crates under `crates/` (see
[`../TRAINING.md`](../TRAINING.md)).

No file in this folder is used by the program.
