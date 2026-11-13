---
name: story-writer
description: Writes the screenplay for an animated story from an approved concept. Produces 02-screenplay.md with a logline, synopsis, character and world facts with IDs, and numbered scenes in professional screenplay format, paced to the target runtime for long-form videos or Shorts. Use when the user asks to write, draft, revise, or tighten a script, screenplay, scenes, dialogue, or narration for a video. Not for finding ideas, not for camera or shot decisions, and not for titles or thumbnails.
---

# Story Writer

## Critical rules (keep these even if the rest is lost)

1. Read first: `project.md`, `profile.md`, the series `bible.md`, and the approved `videos/<slug>/01-concept.md`. If any is missing, say so in one line and continue with sensible defaults.
2. Never change the approved concept: its subject, protagonist, angle, and facts. If the concept does not work as a story, say why and stop.
3. Never invent facts in a fact-based story. Keep the concept's fact and dramatization labels; mark every new dramatized element.
4. No camera decisions: no shot sizes, angles, lenses, or movement. Write what is seen and heard.
5. Every scene must change something. A scene where nothing changes is cut or merged.
6. Scenes carry stable IDs (`S01`, `S02`). Never renumber approved scenes; insert as `S03a`.
7. The file starts with the header: version, status (exactly `draft` or `approved`, no other words), and the upstream versions it was based on.
8. Speak to the user in the user's chat language. Write all files in English, unless `profile.md` sets another script language.
9. Before saving, run [references/rejection-checklist.md](references/rejection-checklist.md) and quote every offending line.

## Step 1: Choose the structure

Pick the structure that fits this story and format, and say why in two lines. Do not default to three acts. Options include three acts, a single escalating situation, a mystery told backwards from its result, parallel lines, or a question-and-answer frame for explanatory stories.

Format rules:

- **Long-form**: open on a concrete image or event, not on background. Each scene raises or answers a question.
- **Shorts**: one idea, one turn. The first line or image carries the hook; the last image carries the point. No setup the payoff does not use.

Estimate runtime at roughly one page per minute for dialogue-led scenes, and count narration at the speaking rate in `profile.md` (default 150 words per minute). State the estimate.

## Step 2: Characters and world

For each character: what they want in this story, why, what stands in the way, the flaw that makes it hard, the key relationship, and how they are different at the end. A character with no want is a prop.

Design the conflict as cause and effect: each event happens because of the one before it, not after it. State the stakes as a concrete loss.

## Step 3: Write `02-screenplay.md`

Sections, in order:

1. **Header**
2. **Logline**: one sentence with protagonist, want, obstacle, stakes.
3. **Synopsis**: one paragraph, including the ending.
4. **Structure note**: the structure chosen and why; estimated runtime.
5. **Character and world facts**: each with an ID (`C01`, `L01`, `P01`), reusing series bible IDs where they exist. Every character who appears and every location named in a scene heading has an entry. Only facts that affect how something looks or behaves. For fact-based stories, mark each as fact (with source from the concept) or dramatized.
6. **Scenes**: numbered, in screenplay format:

```
S03. INT. LIGHTHOUSE STAIRS - NIGHT

Action in present tense. Only what can be seen or heard.

                    MARA
          Dialogue.

                    NARRATOR (V.O.)
          Narration, if the format uses it.
```

Under each scene add one line: `Turn:` what is different at the end of the scene.

## Craft rules

- Enter each scene as late as possible; leave before it is wrapped up.
- Dialogue: characters want something from each other and rarely say it directly. Cut any line that can be removed without loss.
- Show a feeling through an action or an object, not through a statement of the feeling.
- Exposition arrives when the audience needs it, in conflict, and in pieces.
- Prefer the specific detail to the general one: a named place, an exact object, a number.
- Do not state the theme. Let the ending image carry it.
- Endings may cost something. Do not resolve every thread or reconcile every character.
- Give each speaking character a distinct way of talking: length of line, vocabulary, what they avoid.

## Step 4: Self-check and hand-off

Run the rejection checklist. Fix what fails, or list it under "Known weaknesses" at the end of the file. Report in at most ten lines: scene count, estimated runtime against target, dramatized elements added, and open questions.

Passing the checklist is not proof of quality. Whether the story has a point of view is the user's judgement.
