# ADR-0011: One Rust runtime for training and inference; our own autodiff

## Context
The master specification (§31) forbids AI-framework dependencies in the
product and asks for a feasibility study of our own tensor, autodiff and
training system. Revision 1 used PyTorch for training, which meant two
implementations of every operator and cross-language parity tests.

## Decision
- Training uses the same graph IR, operator set, backends and memory planner
  as inference.
- Reverse-mode autodiff is a transformation on our static graphs, emitting
  gradient operators. Every gradient rule is verified by f64 finite
  differences on the CPU backend.
- The optimiser (AdamW), checkpoints (`.sfck`), the data pipeline (our own
  decoders and `sf-degrade`) and experiment tracking are ours.
- Multi-GPU data parallelism and mixed-precision training are postponed.

## Alternatives considered
- **PyTorch for research, our runtime for inference** (revision 1). Violates
  §31's intent, duplicates operators, and needs parity tests.
- **A general-purpose deep-learning framework of our own.** Unrealistic. The
  restriction to our own small, static operator set is what makes this
  feasible.

## Consequences
One implementation per operator, and training-time validation runs the real
engine. The cost: GPU training throughput depends on our own kernels (review
item R2-13), and gradient kernels must be written for every backend.
