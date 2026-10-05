#!/bin/bash
# Builds, signs, notarizes and publishes a Talky release.
#
# Bump CFBundleShortVersionString in Resources/Info.plist first. This script bumps CFBundleVersion
# (the number Sparkle compares), builds a universal Developer ID app, notarizes it, writes the
# update zip, appcast and DMG into web/, commits, pushes (Vercel project "usetalky"
# deploys web/) and creates a GitHub release.
#
# One-time setup on the release Mac:
#   - A "Developer ID Application" certificate in the login Keychain (Xcode › Settings › Accounts).
#   - xcrun notarytool store-credentials talky-notary --apple-id <email> --team-id <team> --password <app-specific>
#   - brew install create-dmg
#   - The Sparkle EdDSA key. The first run creates it in the Keychain. Back it up with
#     .build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.talky.Talky -x key.txt
#     and never change it: installed copies only accept updates signed with it.
#   - Connect GitHub repo Avivhdr/talky to the Vercel project usetalky, with root directory web/
#     and production branch main. The push below is what publishes the site.
#   - TALKY_SITE is https://usetalky.vercel.app. Keep it. Installed copies read the feed from
#     it, and a later change leaves those copies unable to update.
set -euo pipefail
cd "$(dirname "$0")/.."

TALKY_SITE="${TALKY_SITE:-https://usetalky.vercel.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-talky-notary}"
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
INFO=Resources/Info.plist

die() { echo "error: $*" >&2; exit 1; }

# Preflight
[[ "$TALKY_SITE" == *example.com* ]] && die "set TALKY_SITE to your domain"
[ "$(git branch --show-current)" = main ] || die "release from main"
[ -z "$(git status --porcelain)" ] || die "commit or stash your changes first"
command -v create-dmg >/dev/null || die "brew install create-dmg"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "no notary profile \"$NOTARY_PROFILE\" (see the setup notes at the top of this script)"
IDENTITY="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 \
  | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.+)"$/\1/')"
[ -n "$IDENTITY" ] || die "no Developer ID Application certificate in the Keychain"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
TAG="v$VERSION"
gh release view "$TAG" >/dev/null 2>&1 && die "$TAG already exists, bump CFBundleShortVersionString"

swift package resolve
"$SPARKLE_BIN/generate_keys" --account dev.talky.Talky >/dev/null   # creates the key on first run

BUILD=$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$INFO"
echo "Releasing $VERSION (build $BUILD)"

TALKY_SIGN_IDENTITY="$IDENTITY" TALKY_FEED_URL="$TALKY_SITE/appcast.xml" TALKY_UNIVERSAL=1 \
  scripts/build-app.sh
APP=build/Talky.app

# Submits without --wait and polls, because long submissions can outlive the connection.
notarize() {
  local target="$1" upload="$1"
  if [ -d "$target" ]; then
    upload="dist/notarize-$(basename "$target").zip"
    ditto -c -k --keepParent "$target" "$upload"
  fi
  local id
  id="$(xcrun notarytool submit "$upload" --keychain-profile "$NOTARY_PROFILE" --output-format json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  echo "Notarizing $(basename "$target") ($id)"
  while :; do
    local status
    status="$(xcrun notarytool info "$id" --keychain-profile "$NOTARY_PROFILE" --output-format json \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
    case "$status" in
      Accepted) break ;;
      Invalid|Rejected) xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE"; die "notarization $status" ;;
      *) sleep 20 ;;
    esac
  done
  xcrun stapler staple "$target"
}

rm -rf dist && mkdir -p dist/stage web/downloads
notarize "$APP"
spctl -a -vvv --type execute "$APP"

# Sparkle update: versioned zip name so a stale CDN copy can't fail the signature check.
ZIP="Talky-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/stage/$ZIP"
"$SPARKLE_BIN/generate_appcast" --account dev.talky.Talky \
  --download-url-prefix "$TALKY_SITE/downloads/" dist/stage

# DMG for first installs. The website always links the "latest" name.
DMG="dist/Talky-$VERSION.dmg"
mkdir -p dist/dmg && cp -R "$APP" dist/dmg/
create-dmg --volname "Talky" --window-size 600 380 --icon-size 128 \
  --icon "Talky.app" 160 180 --hide-extension "Talky.app" --app-drop-link 440 180 \
  --codesign "$IDENTITY" --hdiutil-retries 20 --overwrite "$DMG" dist/dmg
notarize "$DMG"

find web/downloads -name 'Talky-*' -delete
cp "dist/stage/$ZIP" web/downloads/
cp "$DMG" web/downloads/Talky-latest.dmg
cp dist/stage/appcast.xml web/appcast.xml

git add "$INFO" web
git commit -m "release: $TAG (build $BUILD)"
git push

echo "Waiting for $TALKY_SITE to serve build $BUILD…"
for _ in $(seq 60); do
  curl -fsS "$TALKY_SITE/appcast.xml" 2>/dev/null | grep -q "<sparkle:version>$BUILD</sparkle:version>" && break
  sleep 5
done
curl -fsSI "$TALKY_SITE/downloads/$ZIP" >/dev/null || die "$TALKY_SITE/downloads/$ZIP is not reachable yet"

gh release create "$TAG" "web/downloads/$ZIP" "$DMG" --title "Talky $VERSION" --generate-notes
echo "Released $TAG"
