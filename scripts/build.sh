#!/bin/zsh
# builds Claude Launcher.app in build/, universal (arm64 and x86_64), with its icon, signed with the
# first valid Developer ID Application certificate. used by install.sh and release.sh.
#   SIGN_IDENTITY   overrides the certificate ("-" signs ad hoc, for a mac without a developer id)
#   SIGN_TIMESTAMP  1 adds apple's secure timestamp, which notarization needs (release.sh sets it)
set -euo pipefail
cd "${0:A:h}/.."

APP_NAME="Claude Launcher"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -v REVOKED | grep -m1 'Developer ID Application' | awk '{print $2}')}"
IDENTITY="${IDENTITY:--}"

echo "-> building"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "-> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ClaudeLauncher" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/claude.svg Resources/aaangelmartin.svg "$APP/Contents/Resources/"
for b in "$BIN"/*.bundle; do cp -R "$b" "$APP/Contents/Resources/"; done

echo "-> icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift Resources/claude.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "-> signing with ${IDENTITY}"
TIMESTAMP="--timestamp=none"
[[ "${SIGN_TIMESTAMP:-0}" == 1 ]] && TIMESTAMP="--timestamp"
codesign --force --deep --options runtime "$TIMESTAMP" \
  --entitlements Resources/ClaudeLauncher.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
