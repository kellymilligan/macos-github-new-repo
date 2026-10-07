#!/usr/bin/env bash
# Builds build/NewRepo.app. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/NewRepo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/NewRepo" "$APP/Contents/MacOS/NewRepo"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS treats it as a proper app (needed for "Open at login").
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x NewRepo 2>/dev/null || true
  rm -rf /Applications/NewRepo.app
  cp -R "$APP" /Applications/
  open /Applications/NewRepo.app
  echo "Installed to /Applications/NewRepo.app"
fi
