# ADR-0002: Own data-only model format `.sfm`

## Context
A model file must carry a graph, weights and metadata (scales, modes,
precision safety, provenance). It must also be safe to load when it comes
from an untrusted source.

## Decision
A binary container: magic, version, a length-prefixed JSON header (metadata,
graphs, tensor directory with SHA-256 per tensor), then a 64-byte-aligned
tensor blob. Loading validates every offset, size and hash, and checks the
graph against the operator-set whitelist and the locality rule, before any
allocation proportional to the file's declared sizes.

## Alternatives considered
- **Pickle-based checkpoints.** Rejected: loading one executes code.
- **An existing interchange format for graphs.** Its operator surface is far
  larger than we need, so every backend would face a huge implementation
  burden. It would also tempt us to delegate to external runtimes (O-3).
- **A tensor-only container plus a separate graph file.** Two files can go out
  of sync. The size saving is negligible.

## Consequences
We own the reader, the writer and the fuzzing of the format. The format is
versioned independently of the operator set.
