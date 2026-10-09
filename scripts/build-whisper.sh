#!/bin/bash
# Builds the whisper.cpp engine that Talky ships inside the app.
# Output: .build/whisper/bin/whisper-cli and whisper-server.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=.build/whisper/src
BUILD=.build/whisper/build
OUT=.build/whisper/bin

if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 --branch v1.9.4 https://github.com/ggml-org/whisper.cpp.git "$SRC"
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$(xcrun --find clang)" \
  -DCMAKE_CXX_COMPILER="$(xcrun --find clang++)" \
  -DCMAKE_OSX_SYSROOT="$SDK" \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_NATIVE=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DWHISPER_BUILD_SERVER=ON \
  -DWHISPER_SDL2=OFF \
  -DWHISPER_BUILD_IS_DEV=OFF
cmake --build "$BUILD" --target whisper-cli whisper-server -j "$(sysctl -n hw.ncpu)"

mkdir -p "$OUT"
cp "$BUILD/bin/whisper-cli" "$BUILD/bin/whisper-server" "$OUT/"
chmod +x "$OUT/whisper-cli" "$OUT/whisper-server"
echo "Built $OUT/whisper-cli and $OUT/whisper-server"
