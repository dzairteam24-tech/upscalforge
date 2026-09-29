# ADR-0014: Faithful, Balanced and Reconstruction as distinct computations

## Context
§9 requires three modes that differ in real processing behaviour.

## Decision
| | Faithful | Balanced | Reconstruction |
|--|---|---|---|
| Synthesis subgraph | pruned | executed | executed |
| Strength `s` | 0 | policy-chosen, capped | user 0…1 |
| Strength map `m` | — | from QC | from QC (lenient) |
| Consistency cutoff `fc` | widest safe band | widest safe band | lower band |
| QC thresholds | strict | strict on consistency | lenient on detail, strict on colour |

The body and base path never see `s` (split conditioning). The consistency step
is trained in-graph with `fc` and `w` sampled.

## Consequences
Structural tests can verify each difference. Faithful output is bit-identical
regardless of synthesis weights.
