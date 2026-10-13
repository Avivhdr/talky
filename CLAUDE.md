# Talky

A macOS menu bar dictation app, built with SwiftPM (SwiftUI and AppKit). `README.md` has the behavior, the file layout and the dev commands.

## Design

Read `PRODUCT.md` (who, what, why) and `DESIGN.md` (the visual system, with tokens in its frontmatter) before changing any UI. They are the source of truth for look, feel and copy.

## Releasing and auto-updates

Run `/release` to cut a release (`.claude/skills/release/SKILL.md`). `scripts/release.sh --dry-run` builds and notarizes without publishing. These rules break updates in silence:

- **Bump only `CFBundleShortVersionString`** in `Resources/Info.plist`. `release.sh` owns `CFBundleVersion`, the number Sparkle compares, and commits both halves together.
- **`Resources/Info.plist` holds no Sparkle keys.** `build-app.sh` adds `SUFeedURL` and `SUPublicEDKey` only when `TALKY_FEED_URL` is set, so local builds have no updater.
- **Updates come from the website, not GitHub.** The repo is public. Installed copies still check the feed URL they were built with, https://usetalky.vercel.app. Vercel serves `web/` from `main`, so the push in `release.sh` is the deploy. The GitHub release is only an archive. Do not point the feed at GitHub.
- **`TALKY_SITE` and the Sparkle key are permanent.** Every installed copy checks the feed URL it was built with and trusts the public key it shipped with (Keychain account `dev.talky.Talky`). Enclosure URLs inside the feed can move.
