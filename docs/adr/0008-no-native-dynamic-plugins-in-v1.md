# ADR-0008: No native dynamic plugins in v1

## Context
The brief asks for plugins covering models, stages, backends and formats.
Loading native shared libraries runs untrusted code with full privileges, and
Rust has no stable ABI.

## Decision
v1 uses compile-time registries populated by feature-gated crates, and treats
models as data plugins (validated `.sfm` files). Third-party code will later
use out-of-process plugins with a versioned protocol.

## Consequences
Third parties cannot add native code to a binary distribution in v1. That is
the security trade-off chosen here.
