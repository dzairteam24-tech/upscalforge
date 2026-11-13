# Folder and file contract

Version 0.1.0. The four Skills and the Project Agent rely on these names. Change them only with a new master version.

## Master library (this folder)

```
skills/<skill-name>/SKILL.md      four master Skills, with references/ one level deep
research/                          findings behind each Skill
CONTRACT.md  README.md  BUILD-STATUS.md  CHANGELOG.md  VERSION
```

The master library never contains a `.claude` folder and is never installed as Skills directly. Projects receive copies.

## Project (one channel or series, in its own folder outside the master)

```
.claude/            copied Skills, settings, protection
CLAUDE.md           under 60 lines; imports @NEXT-STEPS.md and @project.md
project.md          title, master version and path, format, runtime, genre, tone, audience,
                    visual style, 2D or 3D, production method, tools, time budget,
                    video table, open issues
profile.md          all project adaptation, including fingerprint traits
bible.md            series-level style; recurring characters, locations, props
ideas-log.md        one line per idea: subject or event | protagonist | angle | date | status
assets.md           every media file: path | shot or bible ID | status (Agent writes it)
NEXT-STEPS.md       rebuilt at session start
changelog.md        dated decisions
references/  archive/  _inbox/  _trash/
videos/<slug>/      per-video files and media/
```

## Per-video files

| File | Written by | Content |
|---|---|---|
| `01-ideas.md` | story-ideas-researcher | Rated candidates |
| `01-concept.md` | story-ideas-researcher | The approved concept |
| `02-screenplay.md` | story-writer | Logline, synopsis, facts with IDs, scenes |
| `03-bible.md` | animation-director | Video bible |
| `04-shots.md` | animation-director | Direction summary and shot table |
| `05-packaging.md` | youtube-packaging | Titles, thumbnails, description |

## File header (every per-video file starts with this)

```
---
version: 1
status: draft            # draft | approved
based-on: 01-concept.md v2, bible.md v3
---
```

File headers are the truth. The video table and `NEXT-STEPS.md` are rebuilt from them.

## IDs

| Kind | Form | Scope |
|---|---|---|
| Character, location, prop | `C01`, `L01`, `P01` | Unique across the project |
| Scene | `S03` (inserted: `S03a`) | Per video |
| Shot | `S03-02` (inserted: `S03-02a`) | Per video |
| Idea candidate | `I-4` | Per ideas file |

Approved IDs are never renumbered. Downstream files reference IDs and do not re-describe.

## Versions and archive

A revised file is saved as the next version. The old one moves to `archive/<slug>/<name>.v<N>.md`. A file based on an older upstream version is marked stale.

## Project Git

Local Git for text files. `.gitignore` excludes media, `_trash/`, and `_inbox/`.
