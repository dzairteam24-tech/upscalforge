# Build status

Updated 2026-11-13. Read this first in any new session.

## Where the build is

The user asked for all four Skills to be built at once, inside the folder `studio skill/` of the repository `dzairteam24-tech/upscalforge`, on branch `ccr-f3d3e043-ot2kdq`. The staged plan in the build brief (stop after each Skill) was set aside at the user's request.

## Done

- Claude Code documentation read; constraints confirmed or corrected (`research/platform-constraints.md`).
- Folder and file contract (`CONTRACT.md`).
- Four master Skills drafted, each with a rejection checklist (`skills/`).
- Research files, one per Skill (`research/`), from search summaries only.
- Project Agent (`agent/story-studio.md`, `agent/playbook.md`), project templates (`agent/templates/`), `install.sh`, `QUICKSTART.md`.
- Sample screenplay (`tests/sample-screenplay.md`); not yet approved by the user.
- Smoke tests, trigger test, and one Director test (`tests/REPORT.md`).
- Version 0.2.1: hook over-blocking fixed in the template and tested; fixes from the Director test applied to the Skills.

## Not done

1. **Research is unverified.** The session's network blocks every external site, and two requests to open it were rejected by the service. The user must change Network access in the environment settings, or run the build on their own computer. Then redo the research and revise rules and source labels.
2. **Interactive smoke tests**: the Agent asking a question; `/clear`. Need the user's computer.
3. **Project copies are behind the master.** The master is 0.2.1 (hook fix and three Skill rule fixes, see `CHANGELOG.md`); the copies in the repository's `.claude/` are still 0.2.0. The user approved the upgrade on 2026-11-13, but the cloud session's own safety check refused both ways of doing it (copying over the protected folders, and removing the protection in the settings file). It must be done outside a cloud session: on a computer, or by editing the files on GitHub.
4. **Skill tests** for the Writer, Researcher, and Packaging; a second Director case; pass criteria to be agreed with the user in Arabic.
5. **Project Agent end to end**: setup, production, memory, and cleaning have not been run.
6. **Full test** (cases A and B): not started. Needs the user's real first video.
7. Install on the user's computer (`sh install.sh`); not tested on Windows or macOS.
8. Arabic research summaries to redo after real research.

## Environment notes

- Built in a temporary cloud session, not a local clone. Nothing was installed at user level.
- A proposal to create an environment with the research sites allowed was rejected by the service. To do the research, the user can allow the sites in the environment's network settings, or run the build on their own computer.
- Pushes go to the branch above only. The default branch was not touched.

## Sentence to paste into a new session

> Read `studio skill/BUILD-STATUS.md` and continue the build from "Not done". Speak to me in Arabic.
