# External Pretrained Models — Candidate Register (ADR-0015)

Licences were read on 2026-09-29 from each project's own `LICENSE` file (raw
file on GitHub). "Admitted" means the licence permits commercial use. It is
not legal advice: the owner confirms each model before distribution.

**Common caveat.** These weights were trained on public research datasets.
Some of those datasets carry non-commercial or research-only terms. Whether
such terms bind the trained weights is legally unsettled.

| Project | Code licence (verified) | Capability | Architecture needs in our engine | Verdict |
|---------|------------------------|------------|----------------------------------|---------|
| Real-ESRGAN (x4plus, x2plus, general-x4v3) | BSD-3-Clause | Real-world upscaling 2x/4x, mild denoise | conv, leaky-ReLU, PReLU, nearest upsample, pixel (un)shuffle, add — almost all already in our operator set | **Admitted — first target** |
| HAT (real-world GAN variant) | Apache-2.0 | High-quality 4x upscaling | Window attention, channel attention, layer norm | **Admitted — second target** (heavy on CPU) |
| SwinIR (real-world variant) | Apache-2.0 | 4x upscaling, denoise, JPEG artefact removal | Window attention, layer norm | Admitted |
| SCUNet | Apache-2.0 | Real-world denoising | Window attention + conv | Admitted |
| NAFNet | MIT | Denoising, deblurring | Layer norm, simple gate, global channel attention (non-local → bounded-error tiling) | Admitted |
| facexlib (face detection) | MIT | Face detection for face-aware processing | Conv detector + box post-processing | Admitted (training-data caveat applies) |
| GFPGAN | Apache-2.0, **but** lists third-party components under an NVIDIA licence and CC BY-NC-SA 4.0 | Face restoration | StyleGAN2-type decoder | **Needs legal review before use** |
| CodeFormer | S-Lab License 1.0 (non-commercial) | Face restoration | — | **Excluded** |
| SPAN | No LICENSE file found | — | — | **Excluded until a licence is found** |
| Restormer | Not verified in this session | — | — | Pending verification |

## Delivery order
1. Real-ESRGAN family: the smallest operator gap, and practical on CPU.
2. SCUNet / NAFNet for dedicated denoising and deblurring.
3. HAT / SwinIR for maximum upscaling quality (attention operators).
4. Faces: detector first; restoration only after legal review.

## Weight acquisition
Weights must be downloaded by the owner, or with explicit permission, from each
project's official release page. The SHA-256 of each file is recorded in the
register when the file is converted.
