# ADR-0012: Spatially varying behaviour through precomputed spatial maps

## Context
Face-aware processing, QC-driven strength reduction and region-dependent
consistency all vary behaviour across the image. They must not break exact
tiling or streaming.

## Decision
All spatial variation is expressed as low-resolution **spatial maps** (strength
`m`, consistency weight `w`, and model-declared conditions such as
`face_mask`). They are computed from global analysis *before* tiling, cropped
per compute window, and consumed by local operators only. Models declare which
spatial conditions they accept. The engine supplies them generically.

## Consequences
New region-aware capabilities need a map producer and a model version that
declares the map. No engine or tiling change is needed.
