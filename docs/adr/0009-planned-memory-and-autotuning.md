# ADR-0009: Planned memory, arenas, analytic-then-measured tuning

## Context
VRAM exhaustion is the main runtime failure. Fragmentation from per-tensor
allocation is hard to predict. Fixed tile sizes are wrong on most hardware.

## Decision
- Activation memory comes from a static liveness plan, laid out in one arena.
  Weights, I/O and workspace get their own tagged pools. A pre-flight `fits`
  check runs before any allocation.
- Memory for a convolutional graph is affine in H·W, so the auto-tuner
  *solves* for the largest fitting tile, then ranks candidates with a cost
  model.
- Measured timings (calibration) are stored in a tuning cache keyed by
  device, driver, model and variant. Measurements override the analytic
  ranking.
- On an out-of-memory error at run time: shrink, re-plan, retry the current
  band, within a bounded number of attempts.

## Consequences
Memory predictions are exact for our own allocations. Driver overhead is
covered by a safety reserve that is later calibrated from measurements.
