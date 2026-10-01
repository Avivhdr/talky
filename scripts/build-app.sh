#!/bin/bash
# Builds build/Talky.app. Set TALKY_SIGN_IDENTITY to a code signing certificate name
# so macOS keeps your Accessibility/Input Monitoring grants across rebuilds (see README).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Talky"

APP=build/Talky.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Talky"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${TALKY_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --identifier dev.talky.Talky "$APP"
echo "Built $APP (signed with: $IDENTITY)"
