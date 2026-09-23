#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

COPPICE_CHANNEL=nightly ./build.sh

APP="build/Coppice Nightly.app"
DEST="/Applications/Coppice Nightly.app"

echo "Installing → $DEST"
osascript -e 'tell application "Coppice Nightly" to quit' 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "$APP" "$DEST"
open "$DEST"
echo "Launched Coppice Nightly — branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git rev-parse --short HEAD 2>/dev/null)"
