#!/bin/zsh
# builds Claude Launcher, signs it and installs it in ~/Applications. run it again after any change.
# SIGN_IDENTITY overrides the certificate ("-" signs ad hoc, for a mac without a developer id).
set -euo pipefail
cd "${0:A:h}/.."

APP="build/Claude Launcher.app"
DEST="$HOME/Applications/Claude Launcher.app"

./scripts/build.sh

echo "-> installing in $DEST"
pkill -x ClaudeLauncher 2>/dev/null && sleep 0.5 || true
# the app was called "Open Claude" and "Abrir Claude" before: take the old copies away so only one
# answers the shortcut
for old in OpenClaude AbrirClaude; do pkill -x "$old" 2>/dev/null && sleep 0.5 || true; done
rm -rf "$HOME/Applications/Open Claude.app" "$HOME/Applications/Abrir Claude.app"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "done: press option c"
