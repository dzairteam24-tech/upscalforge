#!/bin/sh
# PreToolUse hook: refuses shell commands that name the protected folders.
# Reads the tool call as JSON on standard input.
if grep -q -E '\.claude/(skills|hooks)|{{MASTER_PATH_REGEX}}' ; then
  echo "Blocked: this command names a protected folder (.claude/skills, .claude/hooks, or the master library). Ask the user for an approved upgrade instead." >&2
  exit 2
fi
exit 0
