# Platform constraints: verified against the documentation

Checked 2026-11-13 with Claude Code 2.1.323 against the official pages (skills, sub-agents, permissions, memory, hooks-guide, Skill authoring best practices). These pages were opened and read.

| # | Constraint in the build brief | Result | Note |
|---|---|---|---|
| 1 | Subagents cannot ask the user questions | Confirmed | `AskUserQuestion` is removed from every subagent |
| 2 | Agent body replaces the default system prompt | Confirmed, with an addition | An agent with an **empty** body and no `memory` field leaves the session's system prompt unchanged (v2.1.281+). This is an option for the Project Agent |
| 3 | `agent` setting starts the Agent; `initialPrompt` | Confirmed | `initialPrompt` is auto-submitted as the first user turn when the agent runs as the main session; skills and commands in it are processed |
| 4 | Project `CLAUDE.md` loads at launch; `@` imports | Confirmed | Docs advise under 200 lines; the 60-line target in the brief is stricter and kept |
| 5 | Personal Skills override project Skills of the same name | Confirmed | Order: enterprise, personal, project |
| 6 | After compaction only the start of each Skill is kept | Confirmed | First 5,000 tokens of each invoked Skill, 25,000 tokens shared. Critical rules sit at the top of every SKILL.md |
| 7 | A new `.claude/skills` directory needs a restart | **Corrected** | Existing skill directories are watched live. A top-level skills directory created during the session needs `/reload-skills`, not a restart. Restarting still works and stays the simple instruction for the user |
| 8 | Malformed frontmatter fails silently; `claude plugin validate` | Confirmed | The skill body still loads with empty metadata; `claude plugin validate <skills dir>` finds unparsable files |
| 9 | Edit deny rules do not stop every shell command | Confirmed in principle | Bash rules cannot match on the command's content field reliably. The PreToolUse hook is still needed. **Not yet smoke-tested** |
| 10 | Writes into `.claude/` prompt for approval | Not re-checked in detail | To verify in the smoke tests |
| 11 | SKILL.md under 500 lines; references one level deep | Confirmed | Also: `name` up to 64 characters, lowercase letters, digits, hyphens; `description` up to 1,024 characters, third person; description plus `when_to_use` cut at 1,536 characters in the listing |

## Smoke tests

Run in headless mode on 2026-11-13; see `tests/REPORT.md`. Passed: `agent` setting, `CLAUDE.md` imports, Skills listed, subagent spawn, protection against Edit, `echo >>`, `cp`, `mv`, and `rm`. Not tested (need an interactive session): the Agent asking a question, and `/clear`.

Two additions from the tests: the Agent needs read permission for the master library (an allow rule is in the settings template; a new folder prompts once), and allow rules in project settings are ignored until the folder's trust dialog is accepted.
