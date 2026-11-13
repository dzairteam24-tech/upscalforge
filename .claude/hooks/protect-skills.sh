#!/bin/sh
# PreToolUse hook: refuses shell commands that name the protected folders.
if grep -q -E '\.claude/(skills|hooks)' ; then
  echo "Blocked: this command names a protected folder (.claude/skills or .claude/hooks). Ask the user for an approved upgrade instead." >&2
  exit 2
fi
exit 0
