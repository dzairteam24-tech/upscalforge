# ADR-0010: Synchronous-first scheduler on threads

## Context
The brief requires overlapping CPU and GPU work only where it measurably
helps.

## Decision
The synchronous executor is the reference. A pipelined executor (three
threads, bounded channels of depth 2, a reorder buffer, double-buffered
staging) is enabled per device only when calibration shows a gain. No async
runtime is used.

## Consequences
The simplest correct path always exists for debugging and comparison. The
concurrent path is justified by numbers.
