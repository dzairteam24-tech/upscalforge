# Studio Skill: story production master library

Version 0.2.0 (draft). Four general-purpose Skills for animated-story production, coordinated by a Project Agent.

| Skill | Writes | Does |
|---|---|---|
| `story-ideas-researcher` | `01-ideas.md`, `01-concept.md` | Finds, verifies, and rates story concepts |
| `story-writer` | `02-screenplay.md` | Writes the screenplay from the approved concept |
| `animation-director` | `03-bible.md`, `04-shots.md` | Video bible and purposeful shot table |
| `youtube-packaging` | `05-packaging.md` | Titles, thumbnails, description, audience |

## State of this version

- The Skills and the Project Agent are drafts. Test results and known problems are in `tests/REPORT.md`.
- The research behind the Skills is unverified: see the "Limits" section at the top of each file in `research/`.
- What remains is listed in `BUILD-STATUS.md`.

## Installing on a computer

1. Clone this repository.
2. In a terminal, go into the `studio skill` folder and run: `sh install.sh`
3. Open the terminal in a project folder (not this one) and run: `claude --agent story-studio`

The install step writes two files in your user folder: `~/.claude/agents/story-studio.md` and `~/.claude/commands/studio-setup.md`. It changes nothing else. On Windows, run it from Git Bash or WSL.

Do not copy the Skills into your personal `~/.claude/skills/` folder: personal Skills override project copies of the same name.

See `QUICKSTART.md` for the sentences to say.

## Files

- `agent/`: the Project Agent, its playbook, and project templates.
- `tests/`: sample input and the test report.
- `CONTRACT.md`: folder names, file names, headers, and IDs that everything relies on.
- `research/`: findings behind each Skill, and the platform constraints check.
- `CHANGELOG.md`, `VERSION`, `BUILD-STATUS.md`.
