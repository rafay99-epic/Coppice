#!/bin/zsh
# Builds the CURRENT branch as the Nightly channel and installs it next to
# Stable (and Dev). Stable (/Applications/Coppice.app) is never touched. Use this
# to smoke-test a Nightly build locally before pushing to the `nightly` branch.
# A local build has build number 0, so it will offer to pull the published one.
# Usage: ./nightly.sh
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
