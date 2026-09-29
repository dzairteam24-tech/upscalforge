# ADR-0006: Third-party codecs behind our own interface

## Context
We need PNG, JPEG, WebP and TIFF now, and AVIF, JPEG XL and OpenEXR later.
Decoders are the largest attack surface in the system.

## Decision
Define `Codec`, `RegionSource` and `RegionSink` in `sf-image`. Implement them
with memory-safe, fuzzed, format-specific Rust crates (see DEPENDENCIES.md),
each behind a cargo feature. Our own limits run before any decoder allocates.

## Alternatives considered
- **Own decoders.** Adds security-critical parsing code without improving the
  product. The originality requirement concerns the upscaling system, not
  re-implementing standard file formats.
- **The umbrella `image` crate.** Couples the engine to one library's
  abstractions and pulls in unused formats.

## Consequences
Lossy WebP *encoding* is unavailable without a C dependency. v1 offers
lossless WebP output and states this limitation.
