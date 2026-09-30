# ADR-0003: GPU abstraction at graph-execution level

## Context
The engine must not depend on a vendor (G-1). Backends differ in which kernels
are best, which layouts they prefer, and which fusions are possible.

## Decision
Backends receive a planned graph and return an `Executable`. Device
management, allocation, buffers, queues, events and transfers are separate
traits. The engine never selects kernels. Backends also answer
`memory_requirement` as a pure query. The CPU backend implements the same
asynchronous contract, with a strict mode that detects misuse.

## Alternatives considered
- **Kernel-level abstraction** (the engine calls `conv2d(...)` on a device).
  Simple, but it prevents backend fusion and layout choice, and it leaks
  scheduling decisions into the engine.
- **A single cross-vendor API only** (e.g. only Vulkan). Gives up the best
  path on NVIDIA hardware, and memory-budget reporting varies by
  implementation.

## Consequences
Each backend implements the whole operator set. Keeping that set small is
therefore a design constraint on the model (ADR-0007).
