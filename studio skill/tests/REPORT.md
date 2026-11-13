# Test report — version 0.2.0 — 2026-11-13

Run with Claude Code 2.1.323 in headless mode (`claude -p`) inside temporary folders outside the repository, in a cloud container. Temporary folders and the test install were removed afterwards.

## Smoke tests

| Test | Result | Evidence |
|---|---|---|
| `install.sh` writes the agent with the master path | Pass | Path present in the installed agent file |
| `agent` setting starts the Agent from a plain `claude` | Pass | Session followed the agent's rules and `initialPrompt` fired |
| `CLAUDE.md` and its `@` imports load in the agent session | Pass | Agent repeated marker text from `project.md` and `NEXT-STEPS.md` without reading them |
| The four Skills are listed in the project | Pass | Agent named all four |
| Agent can spawn a subagent | Pass | Subagent returned `sub-ok` |
| Edit on a protected Skill file | Blocked | "File is in a directory that is denied by your permission settings." |
| `echo >>`, `cp`, `mv`, `rm` on a protected Skill file | Blocked (all four) | Hook message; file byte-identical afterwards |
| Shell command naming the master library | Blocked | Hook exit code 2 |
| Agent can ask the user a question | **Not tested** | Needs an interactive session |
| Whether `/clear` keeps the Agent | **Not tested** | Needs an interactive session. Until proven: a fresh session means exit and relaunch |

### Problems found

1. **The Agent cannot read the master library without permission.** In a new folder the first read of the playbook asks for approval; the user must accept it. After setup the project settings carry an allow rule for it. In an untrusted folder that allow rule is ignored until the trust dialog is accepted once.
2. **The hook blocks more than needed.** Any shell command that names `.claude/skills` is refused, including read-only `ls`, `cat`, and `diff`. The playbook's validation step (`claude plugin validate`, `diff -r`) must therefore run before protection is added, or use the Read tool. Fixed in 0.2.1: the hook template now allows one plain read-only command and refuses the rest (6 allowed and 14 refused cases run against the template). The project copy still needs an approved upgrade.
3. The hook is a shell script. On Windows it needs Git Bash or WSL. Not tested on Windows or macOS.

## Trigger test

One session was asked which Skill it would invoke for 24 requests: three per Skill that should trigger, and twelve that should not.

Result: 24 of 24 as expected. This is the model's stated choice, not 24 observed invocations; it is weaker evidence than real use.

## Skill test: animation-director (one case)

Input: `tests/sample-screenplay.md` (four scenes, 60-second Short, AI images then image-to-video). The approval stop after the bible was waived for the test.

| Criterion | Result |
|---|---|
| Both files written with headers | Pass; the `status` field carried extra words instead of `draft` |
| Every shot has a Purpose naming a shot-test function | Pass, 15 of 15 |
| Runtime within 5 percent of target | Pass: 60 s |
| Movement static unless motivated | Pass: 13 static, 2 push-ins with a stated motivation |
| Acting cells are actions, not emotion labels | Pass on the rows inspected |
| Bible IDs referenced, not re-described | Pass on the rows inspected |
| Narrative problems returned to the Writer, not fixed | Pass: two returned (title against logline; the burning of the music box is never shown) |
| Did not invent story facts | Weak: it added location L03 for the landing, which the screenplay names in a slug line but not in the facts list. It reported this |

Not judged: whether the direction is good. That is the user's judgement.

## Not tested

- story-writer, story-ideas-researcher, youtube-packaging: no test case run. The researcher and packaging Skills need open network access to work as designed.
- Second test case for the Director.
- The Project Agent's setup, production, memory, and cleaning procedures end to end.
- Full test, cases A and B.
