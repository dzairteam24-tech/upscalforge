#!/bin/sh
# Installs the Story Studio agent for the current user.
# Usage: sh install.sh            (from inside this folder)
set -e
MASTER="$(cd "$(dirname "$0")" && pwd)"
DEST="${HOME}/.claude"
mkdir -p "$DEST/agents" "$DEST/commands"
sed "s|{{MASTER_PATH}}|$MASTER|g" "$MASTER/agent/story-studio.md" > "$DEST/agents/story-studio.md"
cat > "$DEST/commands/studio-setup.md" <<EOF
---
description: Shows how to launch the Story Studio agent
---
Tell the user, in their chat language, only this: to set up or continue a story project, close this session, open the terminal in the project folder, and run:

    claude --agent story-studio

Do nothing else.
EOF
echo "Installed: $DEST/agents/story-studio.md"
echo "Master library: $MASTER"
echo "To start: open the terminal in a project folder and run:  claude --agent story-studio"
