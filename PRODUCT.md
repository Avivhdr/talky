# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

The download page (`web/index.html`) is web. The app itself is a native macOS menu bar app in SwiftUI and AppKit; its surfaces follow macOS conventions.

## Users

Everyone who types on a Mac (confirmed: "meant to be used by everyone"). Not developers specifically. The user is in some other app, mid-task, and wants text to appear where the cursor is without switching context.

## Product Purpose

Talky is a menu bar dictation app for macOS. Hold a key, talk, let go, and the text appears wherever the cursor is. Speech turns into text on the Mac with Whisper (whisper.cpp ships inside the app). With an optional Anthropic API key, Claude then runs pipes on it: strips filler words, makes it formal, turns it into bullets. Success: dictation feels faster and less effortful than typing, and setup takes a minute.

## Positioning

It works in every app, with one key, and has no account and no telemetry. Pipes let one dictation become a formal email, bullets, or a translation by pressing a number while talking. Selected text can be rewritten in place by voice.

## Operating Context

- The pill floats at the bottom center of the screen over whatever app is in front. It never takes focus. It shows mode (Listening, Hands-free, Instruction), input level, elapsed time, and pipe chips numbered 1-9 plus 0 for raw.
- The transform picker opens over a text selection when the user taps right Option.
- Onboarding is one small window in two layers: welcome, the speech model download, two permissions (Microphone, Accessibility), then pipes with an optional Anthropic key (pipes rewrite dictation and also text the user selects), then a real try of dictation in a text box, and with a key a second try: a pipe on a draft message that is already in the box. Finishing opens Settings on Pipes.
- Settings has three tabs: General (hotkey, hands-free hotkey, saved-dictations hotkey, language, launch at login, speech model, Claude: key, pipes on or off, model and transform hotkey, updates, uninstall), Pipes (edit pipe prompts and test them against sample text side by side), and Saved dictations (each recording, the words, and the pipe result when a pipe ran). A tap hotkey opens Saved dictations. The Settings sidebar is the other way to open it.
- The website is a single download page.

## Capabilities and Constraints

- macOS 14 or later, Apple silicon and Intel. Distributed as a DMG, updates through Sparkle.
- Two layers. Dictation: whisper.cpp inside the app with a downloaded model (Whisper large-v3 turbo, 574 MB); free, offline, audio never leaves the Mac. Pipes: optional, need an Anthropic API key. Anthropic is the only API Talky supports.
- The key is stored in `~/.config/talky/.env`.
- Saved dictations keeps the latest 200 dictations in `~/.config/talky` (`snippets.json` and `snippets/`): the recording, the words, and the pipe result when a pipe ran. Audio and text stay on the Mac. Uninstall can delete them with the rest of that folder. The default key is right Control. Settings can change any shortcut or turn it off. The action then has no key until the user sets one.
- The project is not complicated by intent; do not add features or flows.

## Brand Commitments

- Name: Talky. Tagline in use: "Hold a key, talk, let go."
- Talky must feel premium and modern, at the craft level of Linear, Raycast, and Apple Pro apps (confirmed by the user). Retro and physical-object styles were rejected.
- Voice: plain, short, direct sentences, no hype (inferred from README and current copy).
- No logo asset exists yet. The app uses the SF Symbol `waveform`.

## Evidence on Hand

- Real behavior and copy in `README.md` and `web/index.html`.
- No testimonials, user counts, benchmarks, press, or screenshots exist. Do not invent them.
- Pricing: the app is free and open source under the MIT License (`github.com/Avivhdr/talky`); Anthropic bills the user for pipe usage.

## Product Principles

1. One key, any app. The product disappears into what the user is already doing.
2. Plain enough for anyone. No jargon on user-facing surfaces; API keys are explained in one sentence each.
3. Private by default. No account, no telemetry, and the surfaces say exactly where audio and text go.
4. Small on purpose. Fewer settings and steps beat more options.

## Accessibility & Inclusion

The audience is everyone, so contrast, keyboard use, and VoiceOver labels matter on every surface (inferred; no specific standard was set).
