# Project Agent playbook

Read with `CONTRACT.md`. The agent file holds the rules that always apply; this file holds the procedures.

## Session start (every session in an existing project)

1. Read `project.md`, `NEXT-STEPS.md`, and the header of every file under `videos/`.
2. Rebuild the video table in `project.md` and rewrite `NEXT-STEPS.md` from the headers. Mark as stale any file whose `based-on` names an older version than the upstream file now has.
3. Confirm the four Skills are listed. If not, tell the user to exit and run `claude` again in this folder.
4. Scan for media files not listed in `assets.md`. For each, ask which shot or bible ID it belongs to, then register it. Never treat an unregistered file as unused.
5. Report in five lines at most: the current video, what is finished, what is half-finished, the next step.
6. Wait for the user.

## Setup (once per project)

1. Confirm the folder with the user. Refuse the master library and the home folder. Take a read-only inventory. Write nothing yet.
2. Warn the user once: setup writes into `.claude/`, which asks for approval each time; this is expected. Explain the kinds of prompt they will see (file edits, shell commands, web access) and what to check (the path, and that nothing is deleted).
3. If the folder has material, make sure it is a Git repository and commit a snapshot of the text files.
4. Ask for what is missing, pre-filled from what was found, three questions at a time: subject, genre, tone, audience, format, runtime, visual style, 2D or 3D, production method, tools, time budget.
5. Ask for two or three examples the user considers human-quality and what they dislike in AI-made content. Accept pasted text, a file in `references/`, or a link whose transcript can be fetched. Say plainly when a link cannot be fetched and ask for a description of the visuals in words. Extract five to seven observable traits and confirm them.
6. For existing material, show an old-path to new-path table. Uncertain files go to `_inbox/`. Never overwrite. Merge into an existing `CLAUDE.md`.
7. After approval: create the structure in `CONTRACT.md`, move files, log existing ideas in `ideas-log.md` (published ones as used) and media in `assets.md`, and ask the stage of each existing video. Do not retrofit IDs onto finished videos.
8. Check `~/.claude/skills/` for a personal Skill with the same name as any of the four. If one exists, warn the user: it would override the project copy.
9. Copy the four Skill folders from the master `skills/` into `.claude/skills/`. Record the master `VERSION` and path in `project.md`.
10. Only after copying, add protection from the master `agent/templates/`: copy `protect-skills.sh` to `.claude/hooks/`, make it executable, and write `.claude/settings.json` from `settings.json` (replace `{{MASTER_PATH}}`). Write `CLAUDE.md` and `.gitignore` from the templates. Commit.
11. Propose `profile.md`: each adaptation with its reason. Cover genre and subject (stricter sourcing for history, accuracy for science), format, production method, and the fingerprint traits. Apply after approval and log it in `changelog.md`.
12. Before first adapting to a production method, research its strengths, limits, and common problems, and save that in the project's `references/`. If research sources cannot be opened, say so and mark the notes unverified. If no method is chosen, recommend one from the story, the format, and the time budget.
13. Validate: run `claude plugin validate .claude/skills`, and compare the copies with the master (`diff -r`). The protection hook allows these plain read-only commands. Report any difference.
14. Tell the user to exit and run `claude` in this folder. In the next session, confirm the Skills are visible before continuing.

## Production (per video, one stage per session)

| Stage | Skill | Output | User approves |
|---|---|---|---|
| 1 Ideas | `story-ideas-researcher` | `01-ideas.md`, then `01-concept.md` | The concept |
| 2 Screenplay | `story-writer` | `02-screenplay.md` | The screenplay |
| 3 Bible | `animation-director` (step 1) | `03-bible.md` | The bible and reference images |
| 4 Shots | `animation-director` (steps 2 to 5) | `04-shots.md` | The visual direction: one-page summary, each scene's purpose, three sample shots |
| 5 Packaging | `youtube-packaging` | `05-packaging.md` | The packaging choice |

For each stage: invoke the Skill, save the file with its header, show the user what needs approval, update the header status when approved, update `project.md`, `NEXT-STEPS.md`, `ideas-log.md` or `assets.md` as relevant, log the decision in `changelog.md`, and commit.

At the end of every stage tell the user:

- that the stage is saved, and the exact steps to start the next one: exit, run `claude`, and the sentence to say;
- what they must now produce outside Claude Code (tool, number of items), the exact folder and filename pattern (for example `videos/<slug>/media/C01-ref-front.png`, `videos/<slug>/media/S03-02.mp4`), and the sentence to say when it is done.

### Rejection

Ask which parts fail and why. Revise only those. Save as the next version and move the old one to `archive/<slug>/<name>.v<N>.md`. After two failed revisions, ask whether the problem is upstream.

### Changing an approved decision

Log it. Search downstream files for the affected IDs. Show the impact. Then update the upstream file first and regenerate only the affected parts. Mark as stale any file based on an older upstream version.

### Promotions to the series bible

The Director proposes; apply to `bible.md` only after the user approves, then bump its version.

## Organizing and cleaning

Run at setup, after a video is finished, and when asked. Scope: the finished video's folder and unassigned files at the project root.

1. Ask first whether an editing program links to these files. If yes, do not move or rename media.
2. Classify each file: in use (referenced by a current bible, shot table, or packaging file, or marked final by the user), old version, unused, or unsure. Unregistered files and anything whose use cannot be proven are unsure and stay in place.
3. Show a table grouped by folder: group, count, total size, reason, three example filenames, and a label: keep, archive, or move to trash (recoverable). Ask group by group.
4. After approval, move the files, update every reference in the same step, and write `_trash/<date>/MANIFEST.md` with the original paths.
5. Update `assets.md`, `ideas-log.md`, and `changelog.md`. Removing an idea file never removes its line in `ideas-log.md`.

## Upgrading the Skills

Only at the user's request, and between videos. Show the master `CHANGELOG.md`. With approval, remove the protection, replace the Skills, restore the protection, re-run the block test (an Edit and a shell command against a Skill file must both be refused), and log the new version.

## The user's reading checklist

Give this with every piece of output to review:

1. Could I tell who made this and what they care about?
2. Is there one detail I did not expect?
3. Did anything explain itself when it should have shown me?
4. Would I cut any line or shot and lose nothing?
5. Does the ending cost someone something?
