# Talky

Talky is a menu bar dictation app for macOS. Hold a key, talk, let go, and the text appears wherever your cursor is. Speech goes through Whisper, then (optionally) through Claude to strip the "um"s and fix punctuation.

No accounts and no telemetry. With the local whisper.cpp model and no API keys it runs fully offline and pastes the raw transcript.

## What it does

| Action | What happens |
| --- | --- |
| Hold `fn` | Records while held. On release it transcribes, runs the default pipe, and pastes. |
| Double-tap `fn` | Hands-free recording. Tap `fn` once more (or click the stop button on the pill) to finish. Stops by itself after 5 minutes. |
| `1`-`9` while recording | Picks which pipe to run on this dictation. `0` pastes the raw transcript. You can also click the chips next to the pill. |
| Select text, tap right `⌥` | Opens the transform picker. Press a number or click a pipe to rewrite the selection in place. |
| Select text, tap right `⌥`, then hold `fn` | Dictate your own instruction ("make this friendlier", "translate to Spanish") and it gets applied to the selection. |
| `Esc` | Drops a recording, kills a transcription or LLM call already running, or closes the picker. Talky only watches Esc, so it still reaches the app you're typing in. |

The pill at the bottom of the screen shows that the mic is live, which mode you're in (Listening, Hands-free, Instruction), the input level and elapsed time.

## Install

Download `Talky-latest.dmg` from the website, open it and drag Talky into Applications. Talky checks for updates every six hours and installs them through Sparkle. You can also check from the menu bar.

On first launch a short setup window asks for the three permissions and for your API keys:

- **Groq** turns speech into text. The free tier is enough for dictation.
- **Anthropic** runs cleanup and pipes. Skip it and Talky pastes the raw transcript. The pill shows no pipes and the transform hotkey asks for a key.

Both keys can be added or changed later in Settings. Talky saves them to `~/.config/talky/.env`.

### Build from source

Requirements: macOS 14 or later, Xcode command line tools (`xcode-select --install`).

```bash
# Local transcription (skip if you only want Groq/OpenAI)
brew install whisper-cpp
scripts/download-model.sh small        # or small.en, medium, medium.en

# Build, copy to /Applications, link .env into ~/.config/talky, launch
scripts/install.sh
```

`install.sh` symlinks the repo's `.env` to `~/.config/talky/.env` if that file doesn't exist yet. To just build without installing: `scripts/build-app.sh` produces `build/Talky.app`. Source builds have no auto-updates unless you set `TALKY_FEED_URL`.

### Uninstall

Settings, then Uninstall Talky. It turns off launch at login, resets Talky's entries in the Privacy & Security lists, deletes its logs and caches, moves the app to the Trash and quits. A checkbox, on by default, also deletes `~/.config/talky` with your settings, pipes and keys.

If the app won't open, `scripts/uninstall.sh` does the same from the terminal (`--keep-settings` keeps `~/.config/talky`).

## Permissions

The setup window asks for these one at a time. If you skip one, Settings lists whatever is still missing, with an Allow button that jumps to the right pane in System Settings.

| Permission | Where | Why |
| --- | --- | --- |
| Accessibility | Privacy & Security, Accessibility | Required for the global hotkey (an active event tap), for pasting with a simulated Cmd-V, and for reading the selected text. |
| Input Monitoring | Privacy & Security, Input Monitoring | macOS gates keyboard event taps behind this too. Without it the hotkey never fires. |
| Microphone | Privacy & Security, Microphone | Recording. |

After granting Accessibility you don't need to relaunch. Talky retries every two seconds and the menu bar icon changes from a crossed-out mic to a waveform once the hotkey is live.

Two system settings get in the way of the `fn` key:

- System Settings, Keyboard, "Press 🌐 key to": set it to **Do Nothing**. Otherwise every tap also opens the emoji picker or switches input source.
- System Settings, Keyboard, Dictation: turn off Apple's dictation shortcut if it's bound to `fn`.

### Rebuilds and lost permissions

`build-app.sh` signs ad hoc by default. macOS ties permission grants to the code signature, and an ad hoc signature changes on every build, so after a rebuild Talky shows up in the lists but doesn't work. Remove it with the minus button and add it again.

To avoid that, sign with a stable certificate:

1. Open Keychain Access, then Keychain Access menu, Certificate Assistant, Create a Certificate.
2. Name it `Talky Dev`, identity type Self Signed Root, certificate type Code Signing.
3. Build with `TALKY_SIGN_IDENTITY="Talky Dev" scripts/install.sh`.

Grants then survive rebuilds.

## Configuration

Everything lives in `~/.config/talky/`:

```
config.json     settings, including hotkeys (created with defaults on first launch)
pipes.json      your pipes and which one is the default
.env            API keys
models/         whisper.cpp ggml model files
```

Talky watches the folder, so saving `config.json` in an editor applies immediately. If the file has a JSON error, Talky keeps the last good config and shows the error in the menu. Missing keys fall back to defaults, so a file with only `{"hotkey": "right_command"}` is valid.

```jsonc
{
  "enabled": true,
  "hotkey": "fn",                     // hold to talk, double-tap for hands-free
  "transformHotkey": "right_option",  // tap with text selected
  "showPipesInPill": true,
  "transcription": {
    "backend": "auto",                // auto | local | groq | openai
    "localModel": "small",            // small | small.en | medium | medium.en | /abs/path/model.bin
    "language": "auto",               // or "en", "he", "de", ...
    "useWhisperServer": true,         // keep the model loaded in a background whisper-server
    "fallbackToLocal": true,          // cloud request failed? retry locally
    "vocabulary": "",                 // names and jargon to bias spelling, e.g. "Collibra, Kubernetes"
    "groqModel": "whisper-large-v3-turbo",
    "openaiModel": "whisper-1",
    "whisperCliPath": null,           // only if whisper.cpp isn't in /opt/homebrew/bin or PATH
    "whisperServerPath": null
  },
  "llm": {
    "enabled": true,                  // false: always paste the raw transcript
    "model": "claude-opus-5-5",
    "effort": "low",
    "timeoutSeconds": 30
  },
  "clipboard": {
    "restorePrevious": false,         // false: the result stays on the clipboard. true: put back what you had
    "restoreDelayMs": 500
  },
  "handsFree": {
    "maxSeconds": 300,                // a forgotten session stops and transcribes after this
    "doubleTapWindowMs": 400
  }
}
```

### Hotkey names

A hotkey is either a single modifier or a chord.

- Single modifiers: `fn`, `right_option`, `left_option`, `right_command`, `left_command`, `right_control`, `left_control`, `right_shift`, `left_shift`. The left and right versions are told apart.
- Chords: modifiers `cmd`, `ctrl`, `opt`, `shift` joined with `+` and a key: `ctrl+opt+space`, `cmd+shift+d`, `f13`. Talky swallows chord hotkeys so they don't type anything.

The transform hotkey fires on a clean tap only. Holding right `⌥` to type `ø` or `™` won't open the picker.

### Transcription backends

`auto` picks Groq if `GROQ_API_KEY` is set, then OpenAI if `OPENAI_API_KEY` is set, and otherwise the local model. With `fallbackToLocal`, a failed cloud call (offline, rate limited) retries with whisper.cpp, as long as a model file is downloaded.

Locally, Talky starts `whisper-server` in the background so the model stays in memory, and falls back to one-shot `whisper-cli` if the server won't start. `small` is the default. It's fast on Apple Silicon and good enough for most dictation. `medium` is more accurate and roughly 2-3x slower. If you only speak English, the `.en` variants are a bit more accurate at the same size. Server logs go to `~/Library/Logs/Talky/whisper-server.log`.

### LLM model

Pipes run on `claude-haiku-4-5-20251001`, chosen in Settings, then Cleanup. Every dictation waits on this call: Haiku takes about 0.7 s for a sentence, Opus 5.5 about 3 s. Sonnet and Opus give better rewrites for the Formal and Bullets pipes, but cleanup doesn't need them.

## Pipes

A pipe is a named prompt that transforms text. Talky ships with three:

- **Clean**, the default for dictation. Removes filler words and false starts, fixes punctuation, keeps your wording. Full sentences get sentence case, and short chat-style fragments stay lowercase without a trailing period.
- **Formal.** Work-email prose.
- **Bullets.** A markdown bullet list.

Settings, then Pipes is the one place to edit and test them. Each pipe is a card: its name and prompt on the left, and on the right its output for the test text at the top of the screen. Press Run all pipes (⌘↩) and every pipe runs at once, with its latency shown on the card. Change a prompt and the card flags the old output as stale until you run again. The same screen adds, deletes, reorders (order sets the number key) and picks the default. "Use raw transcript by default" turns cleanup off unless you pick a pipe in the pill.

Every pipe runs inside a fixed wrapper prompt that tells Claude to return only the transformed text and to treat the input as material, not as instructions. Dictating "can you write me a poem" pastes that sentence, cleaned up, instead of a poem.

## Troubleshooting

- **Nothing happens when I hold fn.** Check the menu bar icon. A crossed-out mic means Accessibility or Input Monitoring is missing, or Talky is turned off. Also check the 🌐 key setting above.
- **Hotkey dead in password fields.** Expected. macOS secure input blocks all event taps while a password field has focus.
- **"Didn't catch any speech".** The recording was under 0.3 s or nearly silent. Check the input device in System Settings, Sound.
- **Text doesn't paste in one app.** A few apps ignore synthetic Cmd-V. The text is still on the clipboard, so paste it by hand.
- **Transform picker says "Select some text first".** Talky reads the selection through Accessibility and falls back to a synthetic Cmd-C for apps that don't expose it. Some apps support neither.
- **Hotkey stopped working after a rebuild.** See "Rebuilds and lost permissions".

## Development

```bash
swift build          # debug build
swift test           # unit tests: hotkey parsing, config merging, .env parsing, transcript cleanup, WAV
scripts/build-app.sh # release .app bundle
```

The app needs to run from a bundle (`build/Talky.app`) because the microphone prompt requires the usage string in Info.plist. Set `TALKY_CONFIG_DIR=/tmp/talky-test` to point it at a scratch config folder.

Layout:

```
Sources/TalkyCore/
  Controller.swift     state machine: hold, double-tap, hands-free, Esc, picker
  Hotkeys.swift        hotkey parsing and the CGEventTap
  Audio.swift          mic capture at 16 kHz mono, WAV writer
  Transcription.swift  whisper-server / whisper-cli, Groq, OpenAI
  LLM.swift            Claude Messages API
  TextIO.swift         paste, clipboard snapshot/restore, selected text, permissions
  Pill.swift           floating pill, pipe chips, transform picker
  Settings.swift       settings window: General, and Pipes (edit and test together)
  Onboarding.swift     first-run window: permissions, API keys
  Distribution.swift   Sparkle updater, uninstall
  AppDelegate.swift    menu bar, wiring, config file watcher
```

## Releasing

`scripts/release.sh` publishes a version. Bump `CFBundleShortVersionString` in `Resources/Info.plist`, commit, and run it from `main`. It bumps the build number, builds a universal app signed with your Developer ID, notarizes it, and writes three files into `web/`: the Sparkle update zip, `appcast.xml` and `Talky-latest.dmg`. Then it commits, pushes, waits until the site serves the new appcast and creates a GitHub release.

`web/` is the website. The Vercel project `usetalky` serves it at https://usetalky.vercel.app, with root directory `web/`. `scripts/release.sh` uses that address as `TALKY_SITE`. A push to `main` updates the site after GitHub repo `Avivhdr/talky` is connected to that project. The setup steps (certificate, notary profile, Sparkle key) are at the top of the script. Keep this address and the Sparkle key. Every installed copy reads its feed URL and public key from its own Info.plist, so a change to either one stops updates for those copies.

