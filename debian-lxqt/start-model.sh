#!/bin/sh
# Start the bundled MiniCPM-V 4.7 1B as the unprivileged model user.
# The real weight SHA-256 is checked during download; do not run from a VDI.
set -eu
EXPECTED_MODEL=MiniCPM-V-4.7-1B
export XORRISO_EXPECTED_MODEL="$EXPECTED_MODEL"

# Warmup runs in background so systemd sees the real server as main process.
warmup_bg() {
  (
    i=0
    while [ "$i" -lt 45 ]; do
      if curl -sf --max-time 2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
        curl -sf --max-time 25 \
          -H "Content-Type: application/json" \
          -d '{"model":"MiniCPM-V-4.7-1B","messages":[{"role":"user","content":"oi"}],"max_tokens":6,"temperature":0}' \
          http://127.0.0.1:8080/v1/chat/completions >/dev/null 2>&1 || true
        exit 0
      fi
      i=$((i+1))
      sleep 1
    done
    exit 0
  ) &
}

warmup_bg
exec /usr/bin/python3 /usr/local/libexec/xorriso/run-model.py
