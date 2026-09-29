# ADR-0005: Process colour in native encoding

## Context
Converting every image to sRGB before processing clips wide-gamut colours and
adds conversion error. The model is trained on gamma-encoded RGB and does not
depend much on the exact primaries.

## Decision
Gamma-encoded RGB and grey images are processed in their own encoded values,
and the ICC profile is passed through byte for byte. A minimal ICC reader only
*classifies* the transfer (gamma-like, linear, unknown). Linear and HDR data
go through a documented invertible working encoding. Unknown profiles cause a
warning and are handled as gamma-like with the profile preserved.

## Alternatives considered
- **Convert to sRGB, process, convert back.** Clips gamut; needs a full CMS.
- **Process in linear light.** Mismatches the training distribution and
  wastes precision in the shadows at 8 bits.

## Consequences
No full colour-management system is needed in v1. HDR is experimental until
evaluated. CMYK is rejected.
