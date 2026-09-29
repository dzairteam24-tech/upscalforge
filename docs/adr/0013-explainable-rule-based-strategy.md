# ADR-0013: Explainable, rule-based strategy over physical measurements

## Context
Auto mode must choose processing paths and parameters, and every decision must
be explainable (§14).

## Decision
- Analysis produces physical measurements, each with an uncertainty, an
  estimator version and a validity flag.
- The strategy engine is a pure function over (analysis, request, model
  catalogue, device) that applies a **versioned rule policy**. The rules are
  code; the thresholds are data in calibration files produced from synthetic
  evaluations.
- Every decision records its value, source, rule ID and evidence. Learned
  estimators contribute measurements. They never make decisions.
- When evidence is weak or conflicting, conservative fallbacks apply, and they
  are recorded as such.

## Alternatives considered
A learned policy network: opaque, hard to explain and hard to test. It could
be revisited as a *measurement* provider later.

## Consequences
Auto mode is testable with decision tables. Its quality depends on calibration
(review item R2-12).
