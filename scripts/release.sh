#!/bin/bash
# Builds, signs, notarizes and publishes a Talky release.
#
#   scripts/release.sh            build, sign, notarize and publish to $TALKY_SITE
#   scripts/release.sh --dry-run  build, sign and notarize into dist/web-preview; commit and publish nothing
#
# Bump CFBundleShortVersionString in Resources/Info.plist first, and leave the bump uncommitted.
# This script bumps CFBundleVersion (the number Sparkle compares), builds a universal Developer ID
# app, notarizes it, writes the update zip, appcast and DMG into web/, commits both version halves
# in one commit, pushes (Vercel project "usetalky" deploys web/) and creates a GitHub release.
#
# Where updates live: the GitHub repo is private, so its release assets 404 for Sparkle. The feed
# and the binaries ride the website instead. The GitHub release is only an archive.
#   Feed (built into every copy, never move it):  $TALKY_SITE/appcast.xml
#   Update zip (named by the feed, can move):     $TALKY_SITE/downloads/Talky-<version>.zip
#   First install (the website links it):        $TALKY_SITE/downloads/Talky-latest.dmg
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

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true
# A dry run stages into dist/ and leaves the working tree as it found it, so the real run after it
# starts clean.
if $DRY_RUN; then PUBLISH=dist/web-preview; else PUBLISH=web; fi

die() { echo "error: $*" >&2; exit 1; }

# Preflight. Publishing is a commit on main, so unrelated work must not ride along. The version
# bump in Info.plist is the exception: it is the first step of a release, and it goes into the
# release commit with the build number.
[[ "$TALKY_SITE" == *example.com* ]] && die "set TALKY_SITE to your domain"
if ! $DRY_RUN; then
  [ "$(git branch --show-current)" = main ] || die "release from main"
  UNRELATED="$(git status --porcelain | grep -vE "^( M|M |MM) $INFO\$" || true)"
  [ -z "$UNRELATED" ] || die "commit or stash everything except the version bump first:
$UNRELATED"
fi
command -v create-dmg >/dev/null || die "brew install create-dmg"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "no notary profile \"$NOTARY_PROFILE\" (see the setup notes at the top of this script)"
IDENTITY="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 \
  | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.+)"$/\1/')"
[ -n "$IDENTITY" ] || die "no Developer ID Application certificate in the Keychain"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
TAG="v$VERSION"
if $DRY_RUN; then
  echo "DRY RUN: nothing will be committed, pushed or published."
else
  gh release view "$TAG" >/dev/null 2>&1 && die "$TAG already exists, bump CFBundleShortVersionString"
fi

swift test
"$SPARKLE_BIN/generate_keys" --account dev.talky.Talky >/dev/null   # creates the key on first run

OLD_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")"
BUILD=$(( OLD_BUILD + 1 ))
set_build() { /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $1" "$INFO"; }
# The build number is compiled into the app, so a dry run sets it too, then puts it back, also on failure.
$DRY_RUN && trap 'set_build "$OLD_BUILD"' EXIT
set_build "$BUILD"
echo "Releasing $VERSION (build $OLD_BUILD -> $BUILD)"

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

rm -rf dist && mkdir -p dist/stage "$PUBLISH/downloads"
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
spctl -a -t open --context context:primary-signature -v "$DMG"

find "$PUBLISH/downloads" -name 'Talky-*' -delete
cp "dist/stage/$ZIP" "$PUBLISH/downloads/"
cp "$DMG" "$PUBLISH/downloads/Talky-latest.dmg"
cp dist/stage/appcast.xml "$PUBLISH/appcast.xml"
sed -e 's/^/    /' "$PUBLISH/appcast.xml"

if $DRY_RUN; then
  echo "DRY RUN done. The build number is back to $OLD_BUILD. Check the files:"
  ls -lh "$PUBLISH/appcast.xml" "$PUBLISH/downloads/"*
  exit 0
fi

# The push is the deploy: Vercel builds main and serves web/ at $TALKY_SITE.
git add "$INFO" web
git commit -m "release: $TAG (build $BUILD)"
git push

echo "Waiting for $TALKY_SITE to serve build ${BUILD}…"
LIVE=false
for _ in $(seq 60); do
  if curl -fsS --max-time 10 "$TALKY_SITE/appcast.xml" 2>/dev/null | grep -q "<sparkle:version>$BUILD</sparkle:version>"; then
    LIVE=true; break
  fi
  sleep 5
done
$LIVE || die "the feed did not serve build $BUILD within 5 minutes. Check the Vercel deploy, then create the GitHub release by hand"

# Sparkle checks the length in the feed against the bytes it downloads, and drops the update in
# silence when they differ.
EXPECTED="$(grep -Eo 'length="[0-9]+"' web/appcast.xml | head -1 | grep -Eo '[0-9]+')"
SERVED="$(curl -fsSL --max-time 120 "$TALKY_SITE/downloads/$ZIP" | wc -c | tr -d ' ')"
[ "$SERVED" = "$EXPECTED" ] || die "$TALKY_SITE/downloads/$ZIP has $SERVED bytes, the feed says $EXPECTED"
echo "Feed is live. The update zip is $SERVED bytes, as the feed says."

gh release create "$TAG" "web/downloads/$ZIP" "$DMG" --title "Talky $VERSION" --generate-notes
echo "Released $TAG (build $BUILD)"
echo "  Feed:     $TALKY_SITE/appcast.xml"
echo "  Update:   $TALKY_SITE/downloads/$ZIP"
echo "  Download: $TALKY_SITE/downloads/Talky-latest.dmg"
