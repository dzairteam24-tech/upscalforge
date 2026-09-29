# ADR-0015: Classical engine as the primary path; external pretrained models as an optional, labelled add-on

**Status: Accepted by the project owner (2026-09-29).**

## Context
No GPU is installed yet, and the owner wants the strongest result that is
possible **without any training**. Two paths need no training:
1. Classical (non-learned) restoration algorithms, designed and written by us.
2. Complete, openly licensed pretrained models from other projects.

"Taking a part from each model" was examined and rejected on technical
grounds. Learned weights only work together with the rest of the network they
were trained with. Parts of different networks cannot be combined into a
stronger one.

## Decision (owner's choice "ج")
- The **classical engine** (`sf-classic`) is the primary processing path. It
  is ours, needs no training, and is always available.
- **External pretrained models** are an **optional, separately labelled
  add-on**. This is an explicit, owner-approved exception to master
  specification §8/§18, which otherwise forbid external architectures and
  weights. The exception is limited to this add-on:
  - they run in **our** engine (our runtime, operators, tiling and memory
    management). No external inference engine or framework is used;
  - they are converted offline into `.sfm` with `provenance: external`, plus
    their original licence, source and attribution in the metadata;
  - they are never called "ScaleForge models". Reports and the CLI show their
    origin;
  - only models whose licence **permits commercial use** are admitted (see
    `docs/design/06-external-models.md`);
  - they are replaced by ScaleForge-trained models once training hardware
    exists. The engine does not depend on them.
- Weight files (PyTorch `.pth`, a pickle format) are **never unpickled**. The
  converter implements a restricted reader that accepts only tensor-storage
  records and rejects everything else.

## Consequences
- The operator set gains the operators these architectures need (e.g.
  per-channel PReLU; attention operators later). Each addition is reviewed for
  locality.
- Architectures with very large theoretical receptive fields run in
  **bounded-error tiling** mode. The error is measured per model, never
  assumed.
- Residual legal risk: most published super-resolution weights were trained
  on research datasets whose own terms are restrictive. A permissive *code*
  licence does not settle the status of the *weights*. The owner accepts and
  reviews this risk per model before distribution.
