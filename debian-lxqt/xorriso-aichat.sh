#!/bin/sh
# Terminal assistant. Uses the local llama-server; asks before each command.
set -eu
cfg="${HOME}/.config/aichat"
mkdir -p "$cfg"
if [ ! -f "$cfg/config.yaml" ]; then
  cp /usr/local/share/xorriso/aichat/config.yaml "$cfg/config.yaml"
fi
i=0
while [ "$i" -lt 90 ]; do
  if curl -sf --max-time 2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 1
done
if ! curl -sf --max-time 2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
  echo "O MiniCPM-V 4.7 1B ainda nao respondeu em 127.0.0.1:8080." >&2
  exit 1
fi
if [ "$#" -gt 0 ]; then
  exec /usr/local/bin/aichat "$@"
fi
echo "Terminal IA. Descreva a tarefa. O comando aparece e so roda se voce confirmar."
echo "Ctrl+C sai."
while true; do
  printf 'tarefa> '
  IFS= read -r task || exit 0
  [ -n "$task" ] || continue
  /usr/local/bin/aichat -e "$task" || true
done
