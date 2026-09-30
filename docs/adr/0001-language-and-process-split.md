# ADR-0001: Rust engine, Python/PyTorch training

**Status: Superseded by [ADR-0011](0011-own-training-framework.md).** The
master specification (§31) requires that no AI framework be a product
dependency, and a feasibility study showed that our own training framework is
realistic.

## Context
The engine parses untrusted images and model files, manages device memory,
and must run on Linux, Windows and macOS. Training needs automatic
differentiation, optimisers and multi-GPU training.

## Decision
- The engine, runtime, backends and CLI are written in Rust.
- Training is written in Python with PyTorch, in a separate process. The
  engine never links PyTorch.

## Alternatives considered
- **C++ for everything.** Mature GPU ecosystem, but memory-unsafe on exactly
  the attack surface we have: decoders and model parsing.
- **Python + PyTorch for everything.** Fastest to build, but it ties
  inference to one framework's device model (CUDA-centric; no path to
  Vulkan). It also makes the engine a thin layer over a large framework and
  complicates distribution.
- **Our own autodiff in Rust for training.** Realistic only as a toy.
  Technically much worse than PyTorch for mixed precision, multi-GPU
  training and optimiser maturity.

## Consequences
- Two languages. The model is defined once (ADR-0007), and parity tests
  keep the two sides in agreement.
- Training cannot run until the PyTorch dependency is approved.
