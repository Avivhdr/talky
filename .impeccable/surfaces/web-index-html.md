---
version: 1
slug: "web-index-html"
primary_target: "web/index.html"
related_targets: ["Sources/TalkyCore/Onboarding.swift","Sources/TalkyCore/Pill.swift","Sources/TalkyCore/Settings.swift"]
---

# Surface brief: Talky website and app surfaces

## Scope and mode

- `web/index.html`: Persuade. A visitor decides to download Talky.
- Onboarding, pill, Settings General, Settings Pipes (`Sources/TalkyCore/Onboarding.swift`, `Pill.swift`, `Settings.swift`, new `Theme.swift`): Operate. Native macOS controls and navigation stay; the world lends type, palette, glass material, and one signature move.

## Audience, job, constraints

Everyone on a Mac. Website job: understand hold-talk-let-go in seconds, trust the privacy story, download. App job: grant permissions, add keys, dictate, edit pipes. No invented claims, users, or numbers. macOS 14 minimum; native glass only on macOS 26 and later, material blur before that.

## Direction contract

THESIS: Talky is made of Apple's own glass: the pill, the windows and the site float over one deep color field like part of macOS. It refuses the category default of a flat white page with a screenshot.

OWN-WORLD: Color field of navy #0B1A3A and indigo #141A4A lit by soft radial violet #6B4BFF, blue #1E5BFF and peach #FF9A6B. Glass: white 8-20% fill, heavy blur, 1px white rim, a top specular line. White ink, 74% white secondary. Red #FF453A only for "mic is live". Selection is a white chip with a system-blue #0A84FF number badge. SF Pro, the platform's own voice.

STORY: The visitor sees the pill under a window, holds Space or the button, watches words arrive and filler words strike out, presses 1-3 to see pipes reshape the text, then downloads.

FIRST VIEWPORT: Glass nav capsule top center. Centered 88px headline "Talk. Talky types." One-line subhead. White "Download for Mac" plus a glass "Hold to try" button. Below, an 820px glass Notes window receiving text, and the glass pill with live waveform and numbered pipe chips under it. Signature move on every surface: the live glass pill over the color field (website demo, onboarding try-it step, settings header preview).

FORM: Liquid Glass, the user's pick from the safer-register hand, grounded candidate 2 of 3; seed key dde9a4fc.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Unresolved

- No logo asset exists; the mark is a white rounded square with three waveform bars, drawn in SVG and SwiftUI.
