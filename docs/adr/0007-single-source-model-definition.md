# ADR-0007: Single-source model definition with parity tests

## Context
Training (PyTorch) and inference (Rust runtime) both need the architecture. Two
hand-written definitions would drift apart.

## Decision
A small Python builder DSL defines SF-Net. Each DSL layer has both a PyTorch
implementation and an IR emitter. Export writes `.sfm`. Parity tests run the
same random-weight model in both runtimes and require a maximum absolute error
≤ 1e-4 in fp32. The versioned operator set is the contract.

## Alternatives considered
- **Tracing PyTorch graphs into our IR.** Couples us to framework tracing
  internals, and traced graphs contain far more ops than the whitelist allows.
- **Defining the model in Rust and generating Python.** Training-side
  researchers work in Python, and the DSL is simpler to keep there.

## Consequences
A new operator needs work in the DSL, the CPU backend and every GPU backend,
plus a parity test. That cost is deliberate: it keeps the operator set small.
