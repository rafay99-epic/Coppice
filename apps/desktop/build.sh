#!/bin/zsh
# Builds the app from scratch. Usage: ./build.sh
#   COPPICE_CHANNEL=stable (default) → Coppice.app          com.syntaxlabtechnology.coppice
#   COPPICE_CHANNEL=nightly          → "Coppice Nightly.app" com.syntaxlabtechnology.coppice.nightly
#   COPPICE_CHANNEL=dev              → "Coppice Dev.app"     com.syntaxlabtechnology.coppice.dev
# The channels install side by side (different bundle id + name + data + icon).
# Stable + Nightly auto-update from GitHub releases; Dev never does.
set -euo pipefail
cd "$(dirname "$0")"

# SwiftUI's property-wrapper macros (@State and friends) come from the full
# Xcode toolchain. Command Line Tools alone expose a Swift compiler that fails
# later with a misleading "SwiftUIMacros plugin not found", so stop here with
# the actual fix instead.
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
if [[ -z "$DEVELOPER_DIR_PATH" || ! -x "$DEVELOPER_DIR_PATH/usr/bin/xcodebuild" ]]; then
  echo "Coppice requires full Xcode to build SwiftUI." >&2
  echo "Active developer directory: ${DEVELOPER_DIR_PATH:-<none>}" >&2
  echo "Install Xcode 16 or newer, then select it with:" >&2
  echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

CHANNEL="${COPPICE_CHANNEL:-stable}"
case "$CHANNEL" in
  stable)
    APP_NAME="Coppice"
    BUNDLE_ID="com.syntaxlabtechnology.coppice"
    ICON_CACHE="Resources/AppIcon.icns"
    ;;
  nightly)
    APP_NAME="Coppice Nightly"
    BUNDLE_ID="com.syntaxlabtechnology.coppice.nightly"
    ICON_CACHE="Resources/AppIcon-Nightly.icns"
    ;;
  dev)
    APP_NAME="Coppice Dev"
    BUNDLE_ID="com.syntaxlabtechnology.coppice.dev"
    ICON_CACHE="Resources/AppIcon-Dev.icns"
    ;;
  *)
    echo "COPPICE_CHANNEL must be 'stable', 'nightly', or 'dev' (got '$CHANNEL')" >&2
    exit 1
    ;;
esac

echo "Compiling arm64 (Apple Silicon)…  [channel: $CHANNEL]"
# Apple Silicon only. Explicit so SwiftPM never emits a deprecated x86_64 slice.
swift build -c release --arch arm64
BINARY="$(swift build --show-bin-path -c release --arch arm64)/Coppice"
if [[ ! -x "$BINARY" ]]; then
  echo "error: SwiftPM did not produce the expected executable: $BINARY" >&2
  exit 1
fi
ARCH_INFO="$(lipo -info "$BINARY")"
echo "Binary architecture: $ARCH_INFO"
if [[ "$ARCH_INFO" != *"arm64"* || "$ARCH_INFO" == *"x86_64"* ]]; then
  echo "error: expected an arm64-only Coppice binary" >&2
  exit 1
fi

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Coppice"
cp Resources/Info.plist "$APP/Contents/Info.plist"

PB=/usr/libexec/PlistBuddy
# Version is 0.<total commit count> — 10 commits → 0.10. CI passes
# COPPICE_VERSION; local builds compute it. Nightly and Dev append a channel
# suffix and stamp branch@sha so About shows exactly what is running.
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
VERSION="${COPPICE_VERSION:-0.$COMMIT_COUNT}"
if [[ "$CHANNEL" != "stable" ]]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
  VERSION="$VERSION-$CHANNEL"
  "$PB" -c "Add :CoppiceBuildInfo string $BRANCH@$SHA" "$APP/Contents/Info.plist" 2>/dev/null \
    || "$PB" -c "Set :CoppiceBuildInfo $BRANCH@$SHA" "$APP/Contents/Info.plist"
fi
"$PB" -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
"$PB" -c "Set :CoppiceChannel $CHANNEL" "$APP/Contents/Info.plist"
# Monotonic build number (CI run number) orders Nightly pre-releases.
if [ -n "${COPPICE_BUILD:-}" ]; then
  "$PB" -c "Add :CoppiceBuildNumber string $COPPICE_BUILD" "$APP/Contents/Info.plist" 2>/dev/null \
    || "$PB" -c "Set :CoppiceBuildNumber $COPPICE_BUILD" "$APP/Contents/Info.plist"
fi
echo "Version $VERSION  ($APP_NAME · $BUNDLE_ID)"

# Generate the channel's icon once; delete the cache file to force a re-render.
if [ ! -f "$ICON_CACHE" ]; then
  echo "Rendering $CHANNEL icon…"
  PNG="/tmp/coppice_icon_${CHANNEL}_1024.png"
  swift Scripts/MakeIcon.swift "$PNG" "$CHANNEL"
  ICONSET="/tmp/Coppice-$CHANNEL.iconset"
  rm -rf "$ICONSET" && mkdir "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICON_CACHE"
fi
cp "$ICON_CACHE" "$APP/Contents/Resources/AppIcon.icns"

# Code signing. Ad-hoc (`-`) is fine locally but produces a different signature
# every build, and macOS keys TCC grants (Full Disk Access here) to the
# signature — so an ad-hoc update looks like a brand-new app and silently drops
# the grant. Set CODESIGN_IDENTITY to a stable self-signed cert
# (Scripts/make-signing-cert.sh) so every build shares one designated
# requirement and the grant survives updates.
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" != "-" ]; then
  SIGN_IDENTITIES="$(security find-identity -p codesigning 2>/dev/null || true)"
  if ! grep -qF "\"$SIGN_IDENTITY\"" <<< "$SIGN_IDENTITIES"; then
    echo "CODESIGN_IDENTITY=\"$SIGN_IDENTITY\" not found in keychain; falling back to ad-hoc." >&2
    SIGN_IDENTITY="-"
  fi
fi
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  echo "Signing with stable identity: $SIGN_IDENTITY (TCC grant persists across builds)"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
fi
echo "Done → $PWD/$APP"
