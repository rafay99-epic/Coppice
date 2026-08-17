#!/bin/zsh
# Builds the CURRENT branch as the Dev channel and installs it next to Stable.
# Stable (/Applications/Coppice.app) is never touched — break Dev all you like.
# Usage: ./dev.sh
set -euo pipefail
cd "$(dirname "$0")"

COPPICE_CHANNEL=dev ./build.sh

APP="build/Coppice Dev.app"
DEST="/Applications/Coppice Dev.app"

echo "Installing → $DEST"
osascript -e 'tell application "Coppice Dev" to quit' 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "$APP" "$DEST"
open "$DEST"
echo "Launched Coppice Dev — branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git rev-parse --short HEAD 2>/dev/null)"
echo "It is a menu bar app: look for the scissors icon, not the Dock."
