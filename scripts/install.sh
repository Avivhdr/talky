#!/bin/bash
# Builds Talky, copies it to /Applications, sets up ~/.config/talky and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"
CONFIG="${TALKY_CONFIG_DIR:-$HOME/.config/talky}"

./scripts/build-app.sh

pkill -x Talky 2>/dev/null || true
rm -rf /Applications/Talky.app
cp -R build/Talky.app /Applications/Talky.app

mkdir -p "$CONFIG/models"
if [ -f "$REPO/.env" ] && [ ! -e "$CONFIG/.env" ]; then
  ln -s "$REPO/.env" "$CONFIG/.env"
  echo "Linked $REPO/.env -> $CONFIG/.env"
fi

if ! command -v whisper-cli >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/whisper-cli ]; then
  echo "whisper.cpp is not installed. For offline transcription run: brew install whisper-cpp"
fi
if ! ls "$CONFIG"/models/ggml-*.bin >/dev/null 2>&1; then
  echo "No local Whisper model yet. Download one with: scripts/download-model.sh small"
fi

open /Applications/Talky.app
echo "Talky is running. Look for the waveform icon in the menu bar."
