#!/bin/sh
# Start the locally provisioned LFM2.5-350M model as the unprivileged model user.
# The real weight SHA-256 is checked during download; do not run from a VDI.
set -eu
EXPECTED_MODEL=LFM2.5-350M
export XORRISO_EXPECTED_MODEL="$EXPECTED_MODEL"

# Launch server in background so we can warm it up.
/usr/bin/python3 /usr/local/libexec/xorriso/run-model.py &
SERVER_PID=$!

# Wait for the API to become ready, then do one short generation to warm the model.
warmup() {
  i=0
  while [ "$i" -lt 60 ]; do
    if curl -sf --max-time 2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
      curl -sf --max-time 30 \
        -H "Content-Type: application/json" \
        -d '{"model":"LFM2.5-350M","messages":[{"role":"user","content":"oi"}],"max_tokens":8,"temperature":0}' \
        http://127.0.0.1:8080/v1/chat/completions >/dev/null 2>&1 || true
      return 0
    fi
    i=$((i+1))
    sleep 1
  done
  return 1
}

warmup || true

# Keep the server as the main process for systemd.
wait "$SERVER_PID"
