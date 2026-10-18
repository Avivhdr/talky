#!/bin/bash
# Removes Talky from this Mac. Same steps as Settings › Uninstall Talky, for when the app won't open.
#   --keep-settings   keep ~/.config/talky (settings, pipes, saved dictations, API keys, Whisper models)
set -uo pipefail

ID=dev.talky.Talky
CONFIG="${TALKY_CONFIG_DIR:-$HOME/.config/talky}"

pkill -x Talky 2>/dev/null
tccutil reset All "$ID" >/dev/null
defaults delete "$ID" 2>/dev/null
rm -rf "/Applications/Talky.app" "$HOME/Applications/Talky.app" \
  "$HOME/Library/Logs/Talky" \
  "$HOME/Library/Caches/$ID" \
  "$HOME/Library/HTTPStorages/$ID" \
  "$HOME/Library/Application Support/$ID"
[ "${1:-}" = "--keep-settings" ] || rm -rf "$CONFIG"
echo "Talky is uninstalled."
