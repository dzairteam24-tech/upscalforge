# ADR-0016: Export profiles with data-driven rules and compliance checks

**Status: Accepted (owner request, 2026-09-29).**

## Context
The owner submits images to Adobe Stock, which enforces format, colour,
resolution, size, quality and AI-disclosure rules.

## Decision
- Export profiles are named, versioned rule sets stored as data files.
- A profile constrains the strategy engine (models, modes, scale, colour
  target, encoder) and runs a compliance check on the encoded output.
- Results are Pass / Pass-with-warnings / Fail, with reasons.
- Profiles can block models by `licence_scope`. The Adobe Stock profile blocks
  `non-commercial` models, because contributors must hold the rights to
  AI-tool output they submit.
- The report includes an AI-disclosure section to support the user's own
  labelling decision.

## Consequences
When Adobe's rules change, the data file changes, not the code. Colour
management needs a real sRGB conversion path for exports.
