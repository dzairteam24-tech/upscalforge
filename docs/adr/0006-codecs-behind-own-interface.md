# ADR-0006: Third-party codecs behind our own interface

## Context
We need PNG, JPEG, WebP and TIFF now, and AVIF, JPEG XL and OpenEXR later.
Decoders are the largest attack surface in the system.

## Decision (revised for the master specification)
Define `Codec`, `RegionSource` and `RegionSink` in `sf-image`. Implementation
is staged (DEPENDENCIES.md):
- **Our own** PNG, TIFF subset, baseline JPEG encoder (also used for
  degradation synthesis) and baseline JPEG decoder, in safe Rust with limits,
  fuzzing, and differential tests against development-only oracle crates.
- **Interim optional** external decoders (progressive JPEG, WebP) behind
  features, replaced once our own implementations reach differential parity.
Our own limits run before any decoder allocates.

## Alternatives considered
- **External decoders only.** Revision 1 chose this. The master specification
  asks for minimal external code (§18, §21). In safe Rust, a bug in our own
  decoder is a denial-of-service risk bounded by our limits, not a
  memory-corruption risk, so our own codecs are acceptable with fuzzing and
  differential testing.
- **The umbrella `image` crate.** Couples the engine to one library's
  abstractions and pulls in unused formats.

## Consequences
Lossy WebP *encoding* is unavailable without a C dependency. v1 offers
lossless WebP output and states this limitation.

## Update (2026-09-30)
No interim external decoder was needed. WebP decoding (lossless VP8L and
lossy VP8 key frames, with alpha) is our own, written from RFC 9649 and
RFC 6386 and compared with libwebp outside the repository. WebP output,
including the lossless output planned above, is still INCOMPLETE.
