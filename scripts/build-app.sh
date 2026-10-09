#!/bin/bash
# Builds build/Talky.app with Sparkle inside.
#
#   TALKY_SIGN_IDENTITY  code signing identity. Default "-" (ad hoc). A Developer ID identity also
#                        turns on Hardened Runtime and a secure timestamp, which notarization needs.
#                        A stable identity also keeps macOS permission grants across rebuilds.
#   TALKY_FEED_URL       Sparkle appcast URL. Unset means no auto-updates (local dev builds).
#   TALKY_UNIVERSAL=1    build for arm64 and x86_64 (needs full Xcode).
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
[ "${TALKY_UNIVERSAL:-}" = 1 ] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/Talky"

APP=build/Talky.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Talky"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ ! -x .build/whisper/bin/whisper-cli ] || [ ! -x .build/whisper/bin/whisper-server ]; then
  bash scripts/build-whisper.sh
fi
mkdir -p "$APP/Contents/Resources/whisper"
cp .build/whisper/bin/whisper-cli .build/whisper/bin/whisper-server "$APP/Contents/Resources/whisper/"
chmod +x "$APP/Contents/Resources/whisper/whisper-cli" "$APP/Contents/Resources/whisper/whisper-server"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
  "$APP/Contents/Frameworks/Sparkle.framework"

PLIST="$APP/Contents/Info.plist"
if [ -n "${TALKY_FEED_URL:-}" ]; then
  KEY="$(.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.talky.Talky -p 2>/dev/null || true)"
  if [ -z "$KEY" ]; then
    echo "No Sparkle signing key in the Keychain. Run scripts/release.sh once or:"
    echo "  .build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.talky.Talky"
    exit 1
  fi
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $TALKY_FEED_URL" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $KEY" "$PLIST"
  # Check every 6 hours without asking first.
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 21600" "$PLIST"
fi

# Sign inside out: Sparkle's helpers, the framework, then the app.
IDENTITY="${TALKY_SIGN_IDENTITY:--}"
SIGN=(codesign --force --sign "$IDENTITY")
[ "$IDENTITY" != "-" ] && SIGN+=(--options runtime --timestamp)
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$FW/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Autoupdate"
"${SIGN[@]}" "$FW/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$APP/Contents/Resources/whisper/whisper-cli"
"${SIGN[@]}" "$APP/Contents/Resources/whisper/whisper-server"
"${SIGN[@]}" --identifier dev.talky.Talky --entitlements Resources/Talky.entitlements "$APP"
echo "Built $APP (signed with: $IDENTITY${TALKY_FEED_URL:+, updates from $TALKY_FEED_URL})"
