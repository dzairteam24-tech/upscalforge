# Research: Animation Director

Version 0.1.0 — 2026-11-13

## Limits of this research (read first)

The build session's network blocked every external site except the Claude documentation. Web search worked, but **no source page could be opened**. Every finding below is therefore a search-engine summary of a page, not a reading of it. None counts as verified. All are typed `search summary, page not opened`. Rules built on them are provisional until the pages are opened in a session with open network access.

## Questions

1. What makes a shot necessary, and what do professionals call redundant coverage?
2. How do AI image and video tools lose character consistency, and what holds it?
3. What are the visible signs of machine-made direction?
4. When is camera movement justified?
5. What do AI video tools fail at in motion? 

## Findings

| # | Claim (as summarized by search) | Source | Date seen | Type | Resulting rule |
|---|---|---|---|---|---|
| F1 | Camera choices should be justified by what the audience needs to understand; start from the scene's dramatic purpose before planning angles. | https://filmlocal.com/filmmaking/how-to-write-a-shot-list/ | 2026-11-13 | search summary, page not opened (practitioner guide) | Scene purpose line before shots; Purpose column; checklist #1 |
| F2 | A new shot is not needed for every line of dialogue; many "maybe" shots are worth less than one definite shot. | https://wrapbook.com/blog/shot-list ; https://www.techsmith.com/blog/shot-list/ | 2026-11-13 | search summary, page not opened (practitioner guides) | Design by beats; checklist #2, #9 |
| F3 | AI video models do not remember a character between clips; text descriptions alone drift. The common fix is a saved multi-angle reference passed into every generation with a stable prompt template. | https://morphic.com/resources/how-to/character-consistency-in-ai-video ; https://www.vidu.com/blog/ai-character-generator-for-video | 2026-11-13 | search summary, page not opened (vendor pages; treat as marketing) | Canonical prompt block reused verbatim; reference set; checklist #6, #7 |
| F4 | With vague or missing camera instructions, models fall back to a generic pan or zoom; guides recommend motivated movement. | https://framia.converge.ai/page/en-US/blog/ai-video-generator-prompts-motion-mistakes | 2026-11-13 | search summary, page not opened (vendor page) | Movement is static unless motivated; always state the camera; checklist #4 |
| F5 | A conference paper comparing AI animation with hand-made work found AI did well on static principles (staging, solid drawing, appeal) and failed on dynamic ones (squash and stretch, follow-through, anticipation). A vendor guide adds that camera motion is safer than large character motion. | https://core.ac.uk/outputs/656680783 | 2026-11-13 | search summary, page not opened (academic; title and authors not confirmed) | One clear action per shot for AI video; risk flags; checklist #10 |

## Unresolved

- Q3 (signs of machine-made direction): no source found that addresses framing repetition directly. Checklist items #3, #5, #8, #11 are proposals.
- Q1 has two sources of the same kind (practitioner guides) and no professional reference. A directing textbook or studio source is still needed.
- The shot test's seven functions come from the build brief, not from research.

## Rules labeled as proposals

Shot ID scheme, 5 percent runtime tolerance, the acting-as-action rule, and all method notes for code-based animation and Blender.
