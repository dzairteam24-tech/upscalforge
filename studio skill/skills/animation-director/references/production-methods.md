# Production method notes

Read this when `profile.md` names a production method. These are starting defaults. The project's own method research in its `references/` folder overrides them.

All points here are labeled proposals or come from unopened search summaries (see the master `research/animation-director.md`). Treat them as defaults to verify, not as facts.

## AI-generated images and video

- Identity drifts between generations because each clip starts fresh. Text alone does not hold a character. Produce a reference set per character before any shot (front, three-quarter, side, neutral and one emotional expression) and pass it into every generation the tool allows.
- Keep the canonical prompt block fixed. Put shot-specific instructions (framing, action, lighting) in a separate part of the prompt.
- Prefer short shots with one clear action. Complex or multi-step character motion is where these tools fail most; camera movement is usually safer than large body movement.
- Always state the camera: size, angle, and movement or "static". An unspecified camera gets a generic pan or zoom.
- Approve each scene's starting frame before generating video from it.
- In Production notes, record seed, model, and reference weight where the tool exposes them.
- Flag hands holding objects, text on screen, crowds, and precise spatial continuity as risks.

## Code-based animation (for example motion graphics built in code)

- Favor designs made of shapes, type, and simple rigs. Avoid shots that need nuanced facial acting.
- Bible entries carry exact values: hex colors, sizes, easing names, and component names.
- Movement can be exact; state durations and easing in Production notes.

## Blender or other 3D

- Bible entries name the asset file, rig, and material set.
- Each new location or character is a build cost. Flag every shot that needs a new asset.
- Give lens length and camera height in Production notes.

## No method chosen

Recommend one from the story's needs (acting-heavy or design-heavy), the format, and the time budget in `project.md`. Give the recommendation with one reason and one risk.
