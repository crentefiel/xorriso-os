#!/usr/bin/env bash
# Tiny fixtures: CI never downloads the actual MiniCPM weights.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/models" "$T/fixtures" "$T/bin"
printf 'FAKE_GGUF_MODEL_TEST_ONLY\n' > "$T/fixtures/MiniCPM-V-4_7-1B-Q4_K_M.gguf"
printf 'FAKE_VISION_PROJECTOR_TEST_ONLY\n' > "$T/fixtures/mmproj-model-f16.gguf"
export XORRISO_MODEL_TEST_MODE=1
export XORRISO_MODEL_TEST_DIR="$T/models"
export XORRISO_MODEL_TEST_WEIGHT_SHA="$(sha256sum "$T/fixtures/MiniCPM-V-4_7-1B-Q4_K_M.gguf" | awk '{print $1}')"
export XORRISO_MODEL_TEST_PROJECTOR_SHA="$(sha256sum "$T/fixtures/mmproj-model-f16.gguf" | awk '{print $1}')"
export XORRISO_MODEL_TEST_FIXTURES="$T/fixtures"
export XORRISO_CURL_BIN="$T/bin/curl-mock"
cat > "$XORRISO_CURL_BIN" <<'MOCK'
#!/bin/sh
set -eu
out=
url=
while [ "$#" -gt 0 ]; do
 case "$1" in
  --output) out="$2";shift 2 ;;
  *) url="$1";shift ;;
 esac
done
[ -n "$out" ] || exit 6
case "$url" in
 *MiniCPM-V-4_7-1B-Q4_K_M.gguf*) file=MiniCPM-V-4_7-1B-Q4_K_M.gguf ;;
 *mmproj-model-f16.gguf*) file=mmproj-model-f16.gguf ;;
 *) exit 7 ;;
esac
if [ "${XORRISO_MOCK_DOWNLOAD_FAIL:-0}" = 1 ]; then
 printf 'incomplete' > "$out"
 exit 8
fi
if [ "${XORRISO_MOCK_CORRUPT:-0}" = 1 ]; then
 printf 'untrusted bytes' > "$out"
else
 cp "$XORRISO_MODEL_TEST_FIXTURES/$file" "$out"
fi
MOCK
chmod +x "$XORRISO_CURL_BIN"
SCRIPT="$ROOT/src/model.sh"
sh -n "$SCRIPT"
sh "$SCRIPT" status > "$T/out"
grep -q 'nao instalado' "$T/out"
printf 'n\n' | sh "$SCRIPT" install > "$T/out" && exit 51 || :
[ ! -f "$T/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf" ]
printf 's\n' | sh "$SCRIPT" install > "$T/out"
[ -f "$T/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf" ]
sh "$SCRIPT" verify > "$T/out"
grep -q 'SHA-256 verificado' "$T/out"
export XORRISO_MOCK_DOWNLOAD_FAIL=1
sh "$SCRIPT" install > "$T/out"
grep -q 'ja instalado' "$T/out"
unset XORRISO_MOCK_DOWNLOAD_FAIL
export XORRISO_MOCK_CORRUPT=1
printf 's\n' | sh "$SCRIPT" vision > "$T/out" && exit 52 || :
grep -q 'rejeitado' "$T/out"
[ ! -f "$T/models/mmproj-model-f16.gguf" ]
[ ! -f "$T/models/mmproj-model-f16.gguf.part" ]
unset XORRISO_MOCK_CORRUPT
printf 's\n' | sh "$SCRIPT" vision > "$T/out"
sh "$SCRIPT" verify > "$T/out"
grep -q 'mmproj-model-f16.gguf: OK' "$T/out"
printf 'tampered\n' > "$T/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf"
sh "$SCRIPT" verify > "$T/out" && exit 53 || :
sh "$SCRIPT" install > "$T/out" && exit 54 || :
grep -q 'Nao vou sobrescrever' "$T/out"
echo 'PASS: opt-in, model+vision, SHA-256, no-clobber and corrupt download rejection'
