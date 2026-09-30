# Benchmarks

Only measured numbers appear here. Anything that cannot be measured is
`null`.

## Method

```sh
scaleforge benchmark --size 1024x768 --scale 2 --repeat 3 --json bench.json
```

The benchmark:

1. writes a synthetic RGB PNG;
2. runs the complete pipeline (decode → analysis → strategy → restore →
   enlarge → postprocess → encode → write) `--repeat` times;
3. reports the median and every run, per-stage medians, output megapixels
   per second, and CPU utilisation.

CPU utilisation is process CPU time divided by wall time, so 1.0 means one
fully busy core. It is read from `/proc/self/stat`, so it is Linux only.

## Results

### 2026-09-30 — classical engine, CPU

| | |
|---|---|
| Machine | Intel Xeon @ 2.80 GHz, 4 threads (cloud container) |
| Build | release, rustc 1.94.1 |
| Input | 1024x768 synthetic RGB → x2 (2048x1536), Faithful mode, PNG output |
| Total (median of 3) | **1855 ms** (runs: 1973, 1833, 1855) |
| Throughput | **1.70 output MP/s** |
| CPU utilisation | 1.37 |
| GPU utilisation | `null` (no GPU backend) |
| Model load | `null` (no model) |

Stage medians (ms):

| decode | analysis | strategy | restore | enlarge | postprocess | encode | write |
|--------|----------|----------|---------|---------|-------------|--------|-------|
| 29.5 | 57.4 | 0.01 | 5.4 | 251.2 | 569.2 | 920.6 | 5.6 |

### 2026-09-30 — real external model (RealESRGAN_x4plus), CPU

First run of a real downloaded `.pth` (ADR-0015, labelled `external`).

| | |
|---|---|
| Machine | AMD Ryzen 9 5900X (12 cores / 24 threads), 64 GB, Windows 11 |
| Build | release, rustc 1.98.1 |
| Model | `RealESRGAN_x4plus.pth` → `.sfm`: rrdbnet x4, 16 697 987 parameters, receptive radius 349 px |
| `convert-model` | succeeded unchanged; 1.6 s wall |

**Numerical correctness.** A 128x96 and a 256x192 image were run through
our engine as a single whole-image window and compared with an independent
reference (PyTorch 2.11 + spandrel 0.4.2, float32, CPU; used only as a
measuring instrument, not part of ScaleForge):

| Input | max abs diff | mean abs diff |
|-------|--------------|---------------|
| 128x96 → 512x384, vs reference clamped to [0, 1] | 6.9e-6 | 2.2e-7 |

The only other difference: our graph clamps the output to [0, 1], while
the reference leaves values outside that range (min −0.185, max 1.098 on
this image). After 8-bit rounding, 0.005 % of samples differ by one level.

**Blended tiling error** (halo 16 px < receptive radius 349 px, what the
pipeline uses for this model), measured against the whole-image run on the
256x192 input:

| Tile core | Tiles | PSNR vs whole image | mean abs diff |
|-----------|-------|---------------------|---------------|
| 64 px | 12 | 44.91 dB | 2.9e-3 |
| 128 px | 4 | 53.18 dB | 9.2e-4 |

**Quality vs ground truth.** Ground truth: a 1024x768 crop of one of the
owner's photos (downsized with Lanczos; note the source photo was itself an
earlier AI upscale, so this is only an indicative measurement). Input:
ground truth downscaled x4 with bicubic (256x192). Luma SSIM uses 8x8
windows.

| Method | PSNR | SSIM |
|--------|------|------|
| Bicubic (PIL, reference) | 28.83 dB | 0.9032 |
| ScaleForge Faithful (classical) | 29.14 dB | 0.9087 |
| Real-ESRGAN x4plus, raw output of our engine | 27.89 dB | 0.8785 |
| ScaleForge Reconstruction, strength 1 (model + consistency 0.5) | 28.31 dB | 0.8827 |

A GAN model scoring below bicubic on PSNR/SSIM is expected: it invents
plausible texture instead of minimising pixel error. These numbers say
nothing about perceived sharpness; no perceptual metric was measured.

**Speed** (`scaleforge benchmark --size 256x192 --scale 4 --repeat 3
--model models/realesrgan-x4plus.sfm --mode reconstruction`):

| | |
|---|---|
| Total (median of 3) | **15 916 ms** (runs: 15 916, 15 976, 15 866) |
| Throughput | **0.049 output MP/s** |
| Model load | 485 ms |
| Peak tracked device memory | 457 MiB |
| CPU utilisation | `null` (only measured on Linux) |

Stage medians (ms):

| decode | analysis | strategy | restore | enlarge | postprocess | encode | write |
|--------|----------|----------|---------|---------|-------------|--------|-------|
| 1.8 | 2.0 | 0.1 | 0.04 | 15 710 | 33.1 | 153.6 | 15.1 |

For comparison on the same machine, whole-image inference only:

| Input | ScaleForge CPU (24 threads) | PyTorch CPU (12 threads) |
|-------|-----------------------------|--------------------------|
| 128x96 | 4 304 ms | 1 013 ms |
| 256x192 | 18 316 ms | 5 713 ms |

Our CPU convolution is about 3–4x slower than PyTorch's on this model.

### 2026-09-30 — Phase 21: parallel PNG encoding and postprocess, CPU

Same machine as above (Ryzen 9 5900X, 24 threads, Windows 11, rustc
1.98.1). "Before" is the build just before this change, run on the same
machine in the same session.

`scaleforge benchmark --size 1024x768 --scale 2 --repeat 5`:

| | Before | After |
|---|---|---|
| Total (median of 5) | **951 ms** (949, 938, 973, 951, 988) | **321 ms** (324, 314, 321, 335, 298) |
| Throughput | 3.31 output MP/s | 9.79 output MP/s |

| Stage (ms) | decode | analysis | restore | enlarge | postprocess | encode | write |
|------------|--------|----------|---------|---------|-------------|--------|-------|
| Before | 23.2 | 39.2 | 4.2 | 69.5 | 227.8 | 577.6 | 8.7 |
| After | 24.7 | 40.0 | 4.5 | 17.6 | 103.9 | 113.1 | 11.8 |

`scaleforge benchmark --size 2048x1536 --scale 2 --repeat 3`:

| | Before | After |
|---|---|---|
| Total (median of 3) | **3772 ms** | **1044 ms** |
| Throughput | 3.34 output MP/s | 12.05 output MP/s |
| postprocess / encode (ms) | 914 / 2300 | 282 / 386 |

Output: decoded pixels are bit-identical to the previous build on three
real jobs (x2 PNG; x4 PNG with sharpening and auto-tone; x1 17 MP TIFF with
sharpening). PNG files differ in bytes only, and their size changed by less
than 0.1 % (for example 6 278 141 → 6 280 033 bytes for a 2048x1536 PNG).

### 2026-09-30 — WebP decoder vs libwebp, CPU

Same machine. Two of the owner's photos were encoded with libwebp 1.6.0
(through Pillow). Each file was decoded by libwebp and by ScaleForge, and
the outputs compared. Times are one run each, decode only. ScaleForge's
decoder is single-threaded and uses no SIMD.

| File | Size | ScaleForge | libwebp | Max diff | Mean diff |
|------|------|-----------|---------|----------|-----------|
| lossy q80 (photo 1) | 5504x3072 | 487 ms | 195 ms | 2 | 0.113 |
| lossy q80 (photo 2) | 5504x3072 | 477 ms | 196 ms | 2 | 0.113 |
| lossy q30 | 1834x1024 | 54 ms | 28 ms | 2 | 0.125 / 0.160 |
| lossy q75 + alpha | 1834x1024 | 60 ms | 30 ms | 2 (alpha exact) | 0.129 / 0.165 |
| lossless | 1376x768 | 25–28 ms | 20 ms | **0** | 0 |

Differences are in 8-bit levels. For lossy files they come from converting
Y'CbCr to RGB (floating-point Rec. 601 here, libwebp's fixed-point
formula there): at most 0.003 % of samples differ by more than 1.

### Observations

- The first classical measurement found PNG encoding and postprocessing
  single-threaded. Both are now parallel (see Phase 21 above).
- Remaining sequential parts of the classical path: analysis, decoding,
  the consistency residual's per-channel steps, JPEG encoding, and the TIFF
  strip loop (a TIFF Deflate strip larger than 256 KiB does use the
  parallel DEFLATE).
- With a model, inference dominates everything (99 % of the time); the CPU
  convolution is 3–4x slower than PyTorch on CPU. That is the next target,
  before or together with the GPU backend.

## Not measured

- **SRVGG (`realesr-general-x4v3.pth`)**: the file was not available, so the
  compact architecture is still validated only on synthetic files.
- **Model inference on 1024x768 and larger**: not measured yet (a 256x192 input
  already takes about 16 s on CPU).
- **GPU**: the GPU backends are INCOMPLETE (Phase 8, waiting for hardware).
