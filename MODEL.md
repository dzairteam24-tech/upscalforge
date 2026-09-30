# Models

## 1. ScaleForge's own model (SF-Net) — INCOMPLETE

Not trained yet. See [`TRAINING.md`](TRAINING.md). No ScaleForge weights exist,
and the program never presents any model as a ScaleForge model.

## 2. The classical engine (default)

With no model, `scaleforge` restores and enlarges using `sf-classic`:

- wavelet denoising calibrated to the measured noise σ;
- JPEG deblocking;
- Lanczos-3 enlargement with an anti-ringing clamp;
- halo-limited sharpening;
- tone correction.

Faithful mode always uses this path.

## 3. External models (optional, ADR-0015)

These are openly licensed pretrained weights, run by **our own** engine and
never by an external inference engine. Supported architectures:

| Architecture | Examples | Licence | Scope |
|--------------|----------|---------|-------|
| RRDBNet (x4; x2/x1 via pixel-unshuffle input) | `RealESRGAN_x4plus`, `RealESRGAN_x2plus` | BSD-3-Clause | commercial |
| SRVGG compact | `realesr-general-x4v3`, `realesr-animevideov3` | BSD-3-Clause | commercial |

Other candidates are recorded in `docs/design/06-external-models.md`: SwinIR,
HAT, CodeFormer and GFPGAN. They need operators we do not have yet
(attention and window shifting) or face processing. They are **INCOMPLETE**.

### Getting a model

You must download the weights yourself from the official Real-ESRGAN
releases (for example `RealESRGAN_x4plus.pth`). ScaleForge never downloads
anything.

```sh
scaleforge convert-model RealESRGAN_x4plus.pth -o models/realesrgan-x4.sfm
scaleforge models                     # lists ./models
scaleforge upscale in.jpg -o out.png --scale 4 --mode balanced --model models/realesrgan-x4.sfm
```

The converter:

- reads the `.pth` file with our own ZIP reader and a **restricted pickle
  interpreter**, which executes nothing and accepts only a whitelist of
  weights-only globals;
- recognises the architecture from the tensor shapes;
- writes a `.sfm` recording `provenance: "external"`, the licence, the
  `licence_scope`, and the SHA-256 of the source file.

**Validation status:** the converter is tested on format-conformant
synthetic files. It has not yet been run on a real downloaded `.pth` in the
development environment, so the first real conversion is also its first
real validation. Please report the result of `scaleforge convert-model`.

### Rules

- Faithful mode never runs a model.
- Balanced mode blends model and classical output at weight 0.5, then applies
  full consistency correction.
- Reconstruction mode uses `--strength`.
- A model whose `licence_scope` is `non-commercial` is blocked by the Adobe
  Stock export profile.
- Reports and the AI disclosure always name the external model.

## 4. The `.sfm` format

- Magic `SFMODEL\0`, a version, a JSON header (graph, metadata, tensor
  directory), and a 64-byte-aligned blob.
- SHA-256 per tensor and for the whole blob; values must be finite.
- Operators must be on the whitelist.
- On load, locality and scale are derived again from the graph and checked
  against the metadata.

The format carries data only. Loading a model never executes code.
