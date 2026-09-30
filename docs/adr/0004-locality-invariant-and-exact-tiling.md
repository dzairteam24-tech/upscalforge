# ADR-0004: Locality invariant and exact tiling

## Context
Images can exceed both VRAM and RAM. Tiles must produce no seams (E-2, Q-3).
Blending overlaps only hides seams approximately. Any global operation inside
the network makes tile results depend on the tile.

## Decision
- The per-tile graph (`main`) may have no spatial reduction on any path to a
  spatial output. Reductions are allowed only on statistics branches (QC)
  that start from a crop to the tile core. The receptive radius and alignment
  are derived by static analysis.
- Locally varying behaviour (strength, consistency weight, face regions) is
  supplied as spatial maps computed before tiling (ADR-0012).
- Global information comes from a separate analysis pass over a bounded
  summary (a native-resolution patch mosaic plus a thumbnail). The pass
  produces a condition vector that is identical for every tile.
- Default tiling is exact: halo = derived radius, the same border semantics
  as whole-image inference, cores written once, uniform compute windows. A
  bounded-error mode with a smaller halo and blending exists. Its error is
  measured, not assumed.
- Processing-stage plugins must be either `LocalOp{halo}` or
  `GlobalAnalysis → LocalOp`.

## Alternatives considered
- **Overlap + feathered blending as the primary method.** Hides seams without
  removing them. Quality depends on the content.
- **Global attention / global normalisation inside the network.** Breaks
  tiling exactness and streaming.

## Consequences
The model design is constrained: a radius budget, no in-graph global ops.
Halo compute overhead is minimised by required-region cropping. Tile size can
change mid-image without seams, which makes out-of-memory recovery safe.
