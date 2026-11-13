#!/bin/zsh
# builds open claude, signs it and installs it in ~/Applications. run it again after any change.
# SIGN_IDENTITY overrides the certificate ("-" signs ad hoc, for a mac without a developer id).
set -euo pipefail
cd "${0:A:h}/.."

APP_NAME="Open Claude"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
DEST="$HOME/Applications/$APP_NAME.app"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -v REVOKED | grep -m1 'Developer ID Application' | awk '{print $2}')}"
IDENTITY="${IDENTITY:--}"

echo "-> building"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "-> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/OpenClaude" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/claude.svg Resources/aaangelmartin.svg "$APP/Contents/Resources/"
for b in "$BIN"/*.bundle; do cp -R "$b" "$APP/Contents/Resources/"; done

echo "-> icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift Resources/claude.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "-> signing with ${IDENTITY}"
codesign --force --deep --options runtime --timestamp=none \
  --entitlements Resources/OpenClaude.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "-> installing in $DEST"
pkill -x OpenClaude 2>/dev/null && sleep 0.5 || true
# the app was called "Abrir Claude" before: take the old copy away so only one answers the shortcut
pkill -x AbrirClaude 2>/dev/null && sleep 0.5 || true
rm -rf "$HOME/Applications/Abrir Claude.app"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "done: press option c"
