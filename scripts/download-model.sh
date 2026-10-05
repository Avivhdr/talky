#!/bin/bash
# Downloads a whisper.cpp model into ~/.config/talky/models.
# Usage: scripts/download-model.sh [small|small.en|medium|medium.en]
set -euo pipefail
MODEL="${1:-small}"
case "$MODEL" in
  small|small.en|medium|medium.en|base|base.en|large-v3-turbo) ;;
  *) echo "Unknown model: $MODEL (use small, small.en, medium or medium.en)"; exit 1 ;;
esac
DIR="${TALKY_CONFIG_DIR:-$HOME/.config/talky}/models"
mkdir -p "$DIR"
OUT="$DIR/ggml-$MODEL.bin"
if [ -f "$OUT" ]; then echo "Already have $OUT"; exit 0; fi
curl -L --fail --progress-bar -o "$OUT.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin"
mv "$OUT.part" "$OUT"
echo "Saved $OUT"
