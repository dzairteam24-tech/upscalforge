# Change log

## 0.2.1 — 2026-11-13

- Protection hook: plain read-only commands (`ls`, `cat`, `head`, `tail`, `wc`, `diff`, `grep`, `find`, `claude plugin validate`) on the protected folders are now allowed; anything with chaining, redirection, substitution, or a write option is still refused. Tested with 6 allowed and 14 refused cases.
- All four Skills: the header `status` is exactly `draft` or `approved`.
- story-writer: every character and every location named in a scene heading has a facts entry.
- animation-director: a location or character missing from the facts gets a minimal entry marked `not in facts` and is returned to the Writer.
- Research still unverified.

## 0.2.0 — 2026-11-13

- Project Agent, playbook, project templates (settings, protection hook, CLAUDE.md, gitignore), `install.sh`, `QUICKSTART.md`.
- Sample screenplay and first test report.
- Settings template allows the Agent to read the master library.
- Skills unchanged from 0.1.0. Research still unverified.

## 0.1.0 — 2026-11-13

- First draft of the four master Skills: animation-director, story-writer, story-ideas-researcher, youtube-packaging.
- Folder and file contract.
- Platform constraints checked against the official documentation.
- Research files written from search summaries only; no source page could be opened. All findings unverified.
- Not yet done: smoke tests, Skill tests, Project Agent, install step, QUICKSTART.
