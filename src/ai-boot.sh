#!/bin/sh
# Alpha 0.15: boot-time local AI bootstrap without TTY output.
# Never installs software or formats any VDI.
set -eu
PATH=/bin:/usr/bin:/sbin
CONF=${XORRISO_CONF_DIR:-/run/xorriso}
STATUS="$CONF/boot-status"
LOG="$CONF/boot-ai.log"
DATA=/data
RUNTIME_PATH=/runtime-data/runtime/llama-server
STORAGE_SCRIPT=/usr/lib/xorriso/storage.sh
RUNTIME_SCRIPT=/usr/lib/xorriso/runtime.sh
LOOPBACK_SCRIPT=/usr/lib/xorriso/loopback.sh
# CI-only fixtures, not used on normal boot.
if [ "${XORRISO_AUTOSTART_TEST_MODE:-0}" = 1 ]; then
 DATA=${XORRISO_AUTOSTART_TEST_DATA:?}
 RUNTIME_PATH=${XORRISO_AUTOSTART_TEST_RUNTIME:?}
 STORAGE_SCRIPT=${XORRISO_AUTOSTART_TEST_STORAGE:?}
 RUNTIME_SCRIPT=${XORRISO_AUTOSTART_TEST_SERVER:?}
 LOOPBACK_SCRIPT=${XORRISO_AUTOSTART_TEST_LOOPBACK:?}
fi
mkdir -p "$CONF"
chmod 700 "$CONF"
umask 077
state() { printf '%s\n' "$1" > "$STATUS.tmp"; mv "$STATUS.tmp" "$STATUS"; }
case "${1:-start}" in
 status)
  if [ -f "$STATUS" ]; then cat "$STATUS"; else echo 'preparando'; fi
  exit 0 ;;
 start) : ;;
 *) echo 'Uso: ai-boot.sh start | status'; exit 2 ;;
esac
state 'preparando'
: > "$LOG"
if ! /bin/sh "$LOOPBACK_SCRIPT" up >>"$LOG" 2>&1; then
 state 'indisponivel: rede local'
 exit 1
fi
# Default to localhost, never replace an intentionally configured API.
if [ ! -s "$CONF/api_url" ]; then
 printf '%s\n' 'http://127.0.0.1:8080/v1' > "$CONF/api_url"
 printf '%s\n' 'MiniCPM-V-4.7-1B' > "$CONF/api_model"
fi
if [ ! -f "$DATA/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf" ] ||
   [ ! -f "$RUNTIME_PATH" ]; then
 /bin/sh "$STORAGE_SCRIPT" boot >> "$LOG" 2>&1 || :
fi
if [ ! -f "$DATA/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf" ]; then
 state 'indisponivel: modelo nao encontrado'
 exit 2
fi
if [ ! -f "$RUNTIME_PATH" ]; then
 state 'indisponivel: VDI do motor nao encontrado'
 exit 3
fi
if /bin/sh "$RUNTIME_SCRIPT" start >>"$LOG" 2>&1; then
 state 'pronta'
 exit 0
fi
state 'falha: carregamento da IA'
exit 4
