# Studio Skill: story production master library

Version 0.1.0 (draft). Four general-purpose Skills for animated-story production, to be coordinated by a Project Agent.

| Skill | Writes | Does |
|---|---|---|
| `story-ideas-researcher` | `01-ideas.md`, `01-concept.md` | Finds, verifies, and rates story concepts |
| `story-writer` | `02-screenplay.md` | Writes the screenplay from the approved concept |
| `animation-director` | `03-bible.md`, `04-shots.md` | Video bible and purposeful shot table |
| `youtube-packaging` | `05-packaging.md` | Titles, thumbnails, description, audience |

## State of this version

- The Skills are drafts. They have not been tested.
- The research behind them is unverified: see the "Limits" section at the top of each file in `research/`.
- The Project Agent, the install step, and `QUICKSTART.md` do not exist yet. See `BUILD-STATUS.md`.

## Using a Skill by hand, until the Project Agent exists

1. Copy the Skill's folder from `skills/` into your project's `.claude/skills/` folder.
2. Start `claude` in the project folder.
3. Ask for the work in plain words, or type `/` and the Skill's name.

Do not copy the Skills into your personal `~/.claude/skills/` folder: personal Skills override project copies of the same name.

## Installing on another computer

Not available yet. It will be: clone this repository, then run the install step, which places the Project Agent in the user-level agents folder with the path of the local clone.

## Files

- `CONTRACT.md`: folder names, file names, headers, and IDs that everything relies on.
- `research/`: findings behind each Skill, and the platform constraints check.
- `CHANGELOG.md`, `VERSION`, `BUILD-STATUS.md`.
