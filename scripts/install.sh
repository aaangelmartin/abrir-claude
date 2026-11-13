#!/bin/zsh
# builds abrir claude, signs it and installs it in ~/Applications. run it again after any change.
# SIGN_IDENTITY overrides the certificate ("-" signs ad hoc, for a mac without a developer id).
set -euo pipefail
cd "${0:A:h}/.."

APP_NAME="Abrir Claude"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
DEST="$HOME/Applications/$APP_NAME.app"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -v REVOKED | grep -m1 'Developer ID Application' | awk '{print $2}')}"
IDENTITY="${IDENTITY:--}"

echo "-> compilando"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "-> montando $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AbrirClaude" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/claude.svg "$APP/Contents/Resources/"
for b in "$BIN"/*.bundle; do cp -R "$b" "$APP/Contents/Resources/"; done

echo "-> icono"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift Resources/claude.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "-> firmando con ${IDENTITY}"
codesign --force --deep --options runtime --timestamp=none \
  --entitlements Resources/AbrirClaude.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "-> instalando en $DEST"
pkill -x AbrirClaude 2>/dev/null && sleep 0.5 || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "listo: pulsa option c"
