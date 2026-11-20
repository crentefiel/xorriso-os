#!/usr/bin/env bash
# Unit tests use a tiny fake executable; they never claim real LLM inference.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'if [ -f "$T/run/server.pid" ]; then kill "$(cat "$T/run/server.pid")" 2>/dev/null || :; fi; rm -rf "$T"' EXIT
mkdir -p "$T/run" "$T/models"
cat > "$T/fake-server" <<'EOF'
#!/bin/sh
echo "Test server started"
exec sleep 120
EOF
chmod 700 "$T/fake-server"
printf 'fake-gguf-test-only\n' > "$T/models/model.gguf"
export XORRISO_RUNTIME_TEST_MODE=1
export XORRISO_RUNTIME_TEST_BINARY="$T/fake-server"
export XORRISO_RUNTIME_TEST_SHA256="$(sha256sum "$T/fake-server" | awk '{print $1}')"
export XORRISO_RUNTIME_TEST_MODEL="$T/models/model.gguf"
export XORRISO_RUNTIME_TEST_RUN_DIR="$T/run"
sh -n "$ROOT/src/runtime.sh"
sh "$ROOT/src/runtime.sh" status > "$T/status"
grep -q 'SHA-256 aprovado' "$T/status"
sh "$ROOT/src/runtime.sh" start > "$T/start"
grep -q 'iniciado no xorriso' "$T/start"
sh "$ROOT/src/runtime.sh" status > "$T/status"
grep -q 'Servidor em execucao' "$T/status"
sh "$ROOT/src/runtime.sh" stop > "$T/stop"
grep -q 'encerrado' "$T/stop"
printf 'tampered\n' >> "$T/fake-server"
if sh "$ROOT/src/runtime.sh" start > "$T/bad"; then exit 31; fi
grep -q 'SHA-256 incorreto' "$T/bad"
echo 'PASS: runtime start/stop/status, verified executable and rejected tampering'
