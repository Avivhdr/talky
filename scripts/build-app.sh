#!/bin/bash
# Builds build/Talky.app with Sparkle inside.
#
#   TALKY_SIGN_IDENTITY  code signing identity. Default: "Talky Dev" or "Apple Development" from the
#                        Keychain, else "-" (ad hoc). A stable identity keeps macOS permission grants
#                        across rebuilds. A Developer ID identity also turns on Hardened Runtime and a
#                        secure timestamp, which notarization needs.
#   TALKY_FEED_URL       Sparkle appcast URL. Unset means no auto-updates (local dev builds).
#   TALKY_UNIVERSAL=1    build for arm64 and x86_64 (needs full Xcode).
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
[ "${TALKY_UNIVERSAL:-}" = 1 ] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
BIN="$BIN_DIR/Talky"

APP=build/Talky.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Talky"
cp Resources/Info.plist "$APP/Contents/Info.plist"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
  "$APP/Contents/Frameworks/Sparkle.framework"
# whisper.cpp, which turns speech into text inside Talky.
ditto "$BIN_DIR/whisper.framework" "$APP/Contents/Frameworks/whisper.framework"

PLIST="$APP/Contents/Info.plist"

# The app icon. Resources/AppIcon.icon is an Icon Composer document. actool (from Xcode 26 or later)
# turns it into Assets.car, the Liquid Glass icon for macOS 26 and later, and AppIcon.icns for earlier macOS.
if xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist build/AppIcon.plist \
    >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Merge build/AppIcon.plist" "$PLIST"
else
  echo "No icon: compiling Resources/AppIcon.icon needs actool from Xcode 26 or later."
fi

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

# Sign inside out: Sparkle's helpers, the frameworks, then the app.
IDENTITY="${TALKY_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning | grep -E '"(Talky Dev|Apple Development)' | head -1 \
    | sed -E 's/^[^"]*"(.+)"$/\1/' || true)"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY=-
  echo "Signing ad hoc. macOS drops Talky's permissions on every rebuild (see README, \"Rebuilds and lost permissions\")."
fi
SIGN=(codesign --force --sign "$IDENTITY")
[[ "$IDENTITY" == "Developer ID"* ]] && SIGN+=(--options runtime --timestamp)
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$FW/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Autoupdate"
"${SIGN[@]}" "$FW/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$APP/Contents/Frameworks/whisper.framework"
"${SIGN[@]}" --identifier dev.talky.Talky --entitlements Resources/Talky.entitlements "$APP"
echo "Built $APP (signed with: $IDENTITY${TALKY_FEED_URL:+, updates from $TALKY_FEED_URL})"
