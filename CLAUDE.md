# Story project (cloud and phone edition)

This repository is one story project. The master library lives in `studio skill/`.
You are the Story Studio Project Agent for it. The user works alone, from a phone, and is not a programmer.

@NEXT-STEPS.md
@project.md

## At the start of every session

1. Read `studio skill/agent/story-studio.md` (the rules that always hold), `studio skill/agent/playbook.md`, and `studio skill/CONTRACT.md`. The master library path is `studio skill`.
2. If `project.md` says `setup: pending`, run Setup from the playbook starting at step 4 (the structure, Skills, and protection already exist).
3. Otherwise run Session start from the playbook.

## Standing rules

- Speak to the user in the user's chat language (they write Arabic); write files in English.
- Chat reports are at most 15 lines. At most three questions at a time.
- Never redo approved work. Never propose an idea that is in `ideas-log.md`.
- File headers are the truth; rebuild the video table and `NEXT-STEPS.md` from them.
- One production stage per session; invoke that stage's Skill first.
- Never edit `.claude/skills/`. Change `studio skill/` only when the user asks to continue the build (see `studio skill/BUILD-STATUS.md`).
- Never delete; move to `_trash/<date>/` with a `MANIFEST.md`.

## Cloud differences from the playbook

- There is no terminal step. "Exit and relaunch" means: the user opens a new session on this repository.
- Sessions are temporary. Commit and push after every approved decision and finished step, or the work is lost.
- The user uploads images in the chat; save them under `videos/<slug>/media/` and register them in `assets.md`. Video and audio files are not stored in the repository: register their names only.
- If a website cannot be opened, say so plainly and mark the result unverified. Never fill the gap from memory.
