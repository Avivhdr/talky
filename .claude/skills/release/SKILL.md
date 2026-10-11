---
name: release
description: Cut and publish a Talky release (bump, build, notarize, deploy, verify)
argument-hint: "[patch|minor|major|X.Y.Z|dry-run] — omit to bump the patch"
# Only a human starts a release. It pushes to main, deploys the website, publishes a GitHub
# release and ships a binary to every installed copy. When to do that is the user's call.
disable-model-invocation: true
---

Cut a new release of Talky (macOS menu bar app, Sparkle auto-updates).

Target version: read `$ARGUMENTS` against the current `CFBundleShortVersionString` in
`Resources/Info.plist` (`X.Y.Z`):

- Omitted, or `patch`: `X.Y.Z` → `X.Y.(Z+1)`.
- `minor`: `X.Y.Z` → `X.(Y+1).0`.
- `major`: `X.Y.Z` → `(X+1).0.0`.
- `dry-run`: skip to step 3 and run `scripts/release.sh --dry-run`. It builds, signs and notarizes
  into `dist/web-preview/`, and leaves the working tree as it found it. Report the files it lists
  and stop.
- Anything else is an explicit version. **Stop and ask** if it isn't `X.Y.Z`, or isn't greater
  than the current version.

## Steps

1. Check out `main` and `git pull`. **Stop and ask** if the tree has changes, or if `main` is
   behind or ahead of `origin/main`. Leave the user's work exactly where it is.

2. In `Resources/Info.plist`, set **only** `CFBundleShortVersionString`, and leave it uncommitted.

   `release.sh` owns `CFBundleVersion`: it adds one and commits both version halves together.
   Sparkle compares `CFBundleVersion`, so a build number that doesn't rise means installed copies
   never see the update.

3. Run `scripts/release.sh` from the repo root and show the output. Notarization takes minutes;
   run it in the background and wait for it to exit.

   It builds the universal app, notarizes the app and the DMG, EdDSA-signs the update zip, writes
   `web/appcast.xml`, commits and pushes. **That push is the Vercel deploy.** It then waits for the
   live feed to show the new build, checks that the served zip has the byte count the feed names,
   and creates the GitHub release last.

4. Verify from outside the script:

   - `curl -sS https://usetalky.vercel.app/appcast.xml` shows the new `sparkle:shortVersionString`
     and a `sparkle:version` one higher than the last release.
   - The enclosure URL returns HTTP 200, and its byte count equals the `length` in the feed.
     Sparkle drops an update with a wrong length in silence.
   - `https://usetalky.vercel.app/downloads/Talky-latest.dmg` returns 200, and `hdiutil attach`
     shows `Talky.app` and an `Applications` link. Detach it after.

5. Report: the version and build shipped, the feed check, both download checks, and the GitHub
   release URL.

## Stop and ask first if

- The tag `vX.Y.Z` already exists: the version was not bumped.
- The build, `swift test` or notarization fails. Release only on a green suite.
- The feed doesn't go live inside the script's wait. The Vercel deploy probably failed, and the
  feed and the zip it names must go live together.
- Anything would change `TALKY_SITE` or the Sparkle key (account `dev.talky.Talky`). Every
  installed copy checks the feed URL and trusts the public key it was built with, so a change
  strands those copies.
