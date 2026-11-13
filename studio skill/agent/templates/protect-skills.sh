#!/bin/sh
# PreToolUse hook for Bash. Reads the tool call as JSON on standard input.
# Refuses shell commands that name the protected folders.
# Exception: one plain read-only command (ls, cat, head, tail, wc, diff, grep,
# find, or "claude plugin validate") with no chaining, redirection, or substitution.
input=$(cat | tr '\n' ' ')
if ! printf '%s' "$input" | grep -q -E '\.claude/(skills|hooks)|{{MASTER_PATH_REGEX}}'; then
  exit 0
fi
refuse() {
  echo "Blocked: this command names a protected folder (.claude/skills, .claude/hooks, or the master library) and is not a plain read-only command. Ask the user for an approved upgrade instead." >&2
  exit 2
}
# Everything from the command field onward, with escaped double quotes removed.
rest=$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)/\1/p' | sed 's/\\"//g')
[ -n "$rest" ] || refuse
# Any remaining backslash, or a shell operator, means it is not a plain command.
case "$rest" in
  *\\*|*\>*|*\<*|*\|*|*\;*|*\&*|*\$*|*\`*) refuse ;;
esac
printf '%s' "$rest" | grep -q -E -e '-(exec|execdir|ok|okdir|delete|fprint|fprintf|fprint0|fls)' && refuse
printf '%s' "$rest" | grep -q -E '^(ls|cat|head|tail|wc|diff|grep|find|claude plugin validate)( |$)' || refuse
exit 0
