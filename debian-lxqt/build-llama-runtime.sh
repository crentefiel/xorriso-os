#!/usr/bin/env bash
# Build a portable (non-native) llama-server for Debian 13 amd64.
# The source commit is pinned AFTER the MiniCPM-V 4.7 llama.cpp merge.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_COMMIT=5bacb7c868a2bc98682de15f447fc1ce17c9c49c
DEST="$ROOT/runtime-dist"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp/llama"
git -C "$tmp/llama" remote add origin https://github.com/ggml-org/llama.cpp.git
git -C "$tmp/llama" fetch -q --depth 1 origin "$SOURCE_COMMIT"
git -C "$tmp/llama" checkout -q --detach FETCH_HEAD
test "$(git -C "$tmp/llama" rev-parse HEAD)" = "$SOURCE_COMMIT"
# Avoid a pre-4.7 binary masquerading as compatible: require native converter.
grep -Riq 'minicpmv4.7\|minicpmv4_7\|minicpmv4' "$tmp/llama/src" "$tmp/llama/tools" || {
    echo 'Pinned llama.cpp lacks MiniCPM V support' >&2; exit 5;
}
cmake -S "$tmp/llama" -B "$tmp/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE='-O2 -DNDEBUG' \
  -DCMAKE_CXX_FLAGS_RELEASE='-O2 -DNDEBUG' \
  -DCMAKE_EXE_LINKER_FLAGS='-Wl,-z,relro,-z,now' \
  -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_BLAS=OFF \
  -DLLAMA_CURL=OFF -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON
cmake --build "$tmp/build" --target llama-server --parallel 4
BIN="$tmp/build/bin/llama-server"
test -x "$BIN"
mkdir -p "$DEST"
install -m 0755 "$BIN" "$DEST/llama-server"
printf '%s\n' "$SOURCE_COMMIT" > "$DEST/llama-source-commit"
sha256sum "$DEST/llama-server" > "$DEST/llama-server.sha256"
# A binary copied from Ubuntu to Debian must not depend on private build libs.
if ldd "$DEST/llama-server" | grep -Eq 'not found|libggml|libllama'; then
    echo 'Non-portable llama-server binary: private shared dependencies found.' >&2
    ldd "$DEST/llama-server" >&2; exit 7
fi
"$DEST/llama-server" --version
echo 'PASS: pinned MiniCPM 4.7-compatible CPU llama-server built.'
