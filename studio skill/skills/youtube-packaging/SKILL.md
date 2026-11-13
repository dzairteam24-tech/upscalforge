---
name: youtube-packaging
description: Creates the YouTube packaging for a finished animated story. Produces 05-packaging.md with five titles, three thumbnail concepts with image prompts, a recommended title and thumbnail pair with reasoning, a description, keywords, tags where useful, and audience targeting, handling long-form videos and Shorts differently. Use when the user asks for YouTube titles, thumbnails, descriptions, tags, hashtags, or how to present or publish a video. Not for changing the story or the visuals, and not for finding ideas.
---

# YouTube Packaging

## Critical rules (keep these even if the rest is lost)

1. Read first: `project.md`, `profile.md`, the video's `01-concept.md`, `02-screenplay.md`, `03-bible.md`, and `04-shots.md`. If any is missing, say so in one line and continue with sensible defaults.
2. Packaging must be true to the video. Every title and thumbnail shows or promises something the video delivers. Name the scene or shot ID that delivers it.
3. Never invent numbers: no search volumes, no click-through predictions, no "the algorithm prefers" formulas.
4. Keep official YouTube guidance separate from creator opinion. Label each piece of advice `official` (with the Help page) or `opinion`.
5. Check current official YouTube Help pages in this session before writing. If you cannot open them, say so at the top of the file and label all guidance `unverified this session`.
6. Do not change the story or the visuals. Thumbnail art uses the bible's characters and style by ID.
7. One clear idea per thumbnail.
8. The file starts with the header: version, status (exactly `draft` or `approved`, no other words), and upstream versions.
9. Speak to the user in the user's chat language. Write the file in English; write titles and description in the publishing language set in `profile.md`.
10. Before saving, run [references/rejection-checklist.md](references/rejection-checklist.md) and quote every offending line.

## Step 1: Find the promise

In two lines: what the viewer gets from this video, and the single most intriguing true thing in it. Everything below serves that promise.

## Step 2: Five titles

- Each takes a different approach: the question, the specific fact, the character, the stakes, the contrast.
- Put the important words first; long titles are cut off on small screens.
- Plain words. No all-caps titles, no stacked punctuation, no emoji unless `profile.md` asks.
- For each: the title, its approach, and the scene ID that delivers on it.

## Step 3: Three thumbnail concepts

Each concept is one idea, readable at small size. For each give:

| Field | Content |
|---|---|
| Subject | Bible ID and what it is doing |
| Expression | Specific, and true to the scene |
| Pose | |
| Background | Simple; bible location ID if used |
| Composition | Where the subject sits; what is left empty |
| Lighting | |
| Palette | From the bible; state the contrast |
| Focal point | The one place the eye lands |
| Text | None, or at most four words; position; must not repeat the title |
| Image prompt | Canonical prompt block from the bible, verbatim, plus the fields above |
| Delivers | The shot ID in the video this image is true to |

The thumbnail and title work as a pair: the image shows, the title tells. They do not say the same thing twice.

## Step 4: Recommended pair

Choose one title and one thumbnail. Give the reasoning in three lines: the promise, why this pair is clear at a glance, and why it is honest. Do not predict performance.

## Step 5: Description, keywords, tags, audience

- **Description**: the first two lines carry the promise in plain language, since only the start shows before "more". Then a short paragraph about the video, sources for fact-based stories, and credits. Chapters with timestamps for long-form, taken from scene IDs. No lists of keywords.
- **Keywords**: five to eight phrases a person would type, drawn from the video's real subject. Use them naturally in the title and description. Give no volumes.
- **Tags**: optional and of small importance. Include a short list only where it helps, such as common misspellings of a name.
- **Hashtags**: at most three, relevant to the content.
- **Audience**: who the video is for in one line. State whether it must be set as "made for kids" under YouTube's rules, with the reason, and flag this for the user to confirm since it has legal weight. Note any age-sensitivity in the content.

## Long-form and Shorts

- **Long-form**: custom thumbnail matters; full description with chapters; title can pose the question the video answers.
- **Shorts**: the first second of the video does the work of the thumbnail. Give a shorter title, a one or two line description, and name the frame to select as the cover rather than three designed concepts, unless `profile.md` says the platform supports custom Shorts thumbnails. Say which shot opens the Short and why it holds attention.

See [references/official-guidance.md](references/official-guidance.md) for the list of official pages to check and what each covers.

## Step 6: Self-check and hand-off

Run the rejection checklist. Fix what fails, or list it under "Known weaknesses". Report in at most ten lines: the recommended pair, anything in the packaging the video might not deliver, and what the user must decide.

Passing the checklist is not proof of quality. The final choice is the user's.
