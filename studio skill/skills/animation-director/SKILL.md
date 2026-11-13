---
name: animation-director
description: Turns an approved screenplay into a video bible and a purposeful shot table for animated-story production. Writes 03-bible.md (style rules, palette, and fixed descriptors plus one canonical prompt block per character, location, and prop) and 04-shots.md (one table of shots, each with a stated dramatic purpose). Use when the user asks for visual direction, a shot list, storyboard planning, a character or style bible, or consistency rules for an animated video. Not for writing or changing the story, and not for titles or thumbnails.
---

# Animation Director

## Critical rules (keep these even if the rest is lost)

1. Read first: `project.md`, `profile.md`, the series `bible.md`, and the approved `videos/<slug>/02-screenplay.md`. If any is missing, say so in one line and continue with sensible defaults.
2. Write the bible before any shot. Never design shots against an unapproved bible.
3. Every shot must pass the shot test below. A shot that fails is cut, merged, or redesigned, and the reason is noted.
4. Never rewrite the story. List narrative problems under "Returned to Writer" and stop on those scenes.
5. Reuse each canonical prompt block verbatim. Never paraphrase a character, location, or prop description in a shot row; reference its ID.
6. Every output file starts with the header: version, status (exactly `draft` or `approved`, no other words), and the upstream versions it was based on.
7. Speak to the user in the user's chat language. Write all files in English.
8. Before saving, run the rejection checklist in [references/rejection-checklist.md](references/rejection-checklist.md) and quote every offending shot.

## Step 1: Video bible (`03-bible.md`)

Build it from the Writer's character and world facts and the series `bible.md`. If a scene heading names a location or character with no entry in the facts, do not invent one silently: add a minimal entry, mark it `not in facts`, and list it under "Returned to Writer". Reference series entries by ID; add only video-specific entries. IDs are unique across the project (`C01` characters, `L01` locations, `P01` props).

Contents:

- **Style rules**: medium (2D or 3D), line, shading, texture, camera language, what the style never does. Five to eight rules, each checkable by looking at a frame.
- **Palette**: named colors with hex values, and which scenes or emotions each belongs to.
- **Entries**, one per character, location, and prop:
  - ID and name
  - Fixed descriptors: the features that never change (silhouette, proportions, face, hair, distinguishing marks; for locations, layout and landmarks)
  - Wardrobe or state by scene ID (`S03: coat torn at left sleeve`)
  - Canonical prompt block: one paragraph, written once, reused verbatim
  - Reference image path under `media/` (empty until the user produces it)
  - Tool settings, only where the production method in `profile.md` supports them (seed, reference weight, model, rig name)
- **Proposed promotions**: entries likely to recur in later videos. Only propose; the Project Agent applies them after the user approves.

Adapt to the production method in `profile.md`. See [references/production-methods.md](references/production-methods.md) when the method is AI-generated images or video, code-based animation, or Blender.

Stop here and ask for approval of the bible and its reference images before writing shots.

## Step 2: Scene purposes

For every scene ID in the screenplay, write one line: what changes for the audience by the end of this scene (knowledge, emotion, or tension). If you cannot write that line, the scene is a narrative problem: return it to the Writer.

## Step 3: Shot table (`04-shots.md`)

One table. Columns, in this order:

| Shot ID | Scene | Purpose | Size | Angle | Movement | Composition | Acting | Lighting | Duration (s) | Transition | Bible IDs | Production notes |

- Shot IDs are stable: `S03-02` is the second shot of scene S03. Never renumber approved shots; insert as `S03-02a`.
- **Purpose** names one function from the shot test and what specifically it does ("Reveals: the letter is unsigned").
- **Movement** is `static` unless something in the story motivates it; write the motivation ("push in: she realises").
- **Acting** is a specific physical action or expression change, not an emotion label.
- **Production notes** are for the chosen method: prompt additions, start frame, risk flags.
- Durations sum to the target runtime in `project.md`, within 5 percent. State the total under the table.

### The shot test

Every shot does at least one of these, and the Purpose column says which:

1. Reveals information
2. Advances the story
3. Develops character
4. Shifts emotion or tension
5. Clarifies space
6. Shows a consequence
7. Builds a declared motif (the motif is named in the bible)

### Patterns to avoid

- One shot per screenplay sentence. Design by beats, not by sentences.
- The same size and angle three shots in a row without a reason.
- Repeated poses for the same character across scenes.
- Reaction shots that show no change in the character.
- Establishing shots of a place the audience already knows.
- Camera movement with no motivation in the story.
- Two angles that tell the audience the same thing.

## Step 4: One-page direction summary

For the user's approval, write at the top of `04-shots.md`: each scene's purpose in one line, three sample shots that best show the approach, total shot count and runtime, and everything cut or merged with the reason.

## Step 5: Self-check and hand-off

Run the rejection checklist. Fix what fails, or list it under "Known weaknesses". Then report in at most ten lines: files written, shot count, runtime, open questions, and anything returned to the Writer.

Passing the checklist is not proof of quality. Whether the direction has a point of view is the user's judgement.
