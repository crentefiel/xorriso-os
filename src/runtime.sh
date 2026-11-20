#!/bin/sh
# xorriso Alpha 0.11 - optional llama-server on guest, from separately provisioned VDI.
# Never runs an unverified binary. Disk is mounted noexec; copy the server to tmpfs.
set -eu
PATH=/bin:/usr/bin:/sbin
STORAGE=/data
RUNTIME="$STORAGE/runtime/llama-server"
RUNTIME_HASH=3e5f1cf566de425ee2d5f0864050f20a14031b37daebe2aa7d638de4389ec2e1
MODEL="$STORAGE/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf"
PROJECTOR="$STORAGE/models/mmproj-model-f16.gguf"
RUN_DIR=/run/xorriso/llama
SERVER="$RUN_DIR/llama-server"
PIDFILE="$RUN_DIR/server.pid"
LOGFILE="$RUN_DIR/server.log"
URL=http://127.0.0.1:8080

# Fixtures only for CI tests; environment is untrusted, so these hooks are not
# a security boundary. The system is currently single-user/root in a VM.
if [ "${XORRISO_RUNTIME_TEST_MODE:-0}" = 1 ]; then
 RUNTIME=${XORRISO_RUNTIME_TEST_BINARY:?}
 RUNTIME_HASH=${XORRISO_RUNTIME_TEST_SHA256:?}
 MODEL=${XORRISO_RUNTIME_TEST_MODEL:?}
 RUN_DIR=${XORRISO_RUNTIME_TEST_RUN_DIR:?}
 SERVER="$RUN_DIR/llama-server"
 PIDFILE="$RUN_DIR/server.pid"
 LOGFILE="$RUN_DIR/server.log"
else
 # New setup: keep existing GGUF on /data, load the verified llama-server
 # from a second read-only VDI labeled XORRISO_RUNTIME.
 if grep -q ' /runtime-data ext4 ' /proc/mounts 2>/dev/null; then
  RUNTIME=/runtime-data/runtime/llama-server
 fi
fi
mounted() {
 [ "${XORRISO_RUNTIME_TEST_MODE:-0}" = 1 ] && return 0
 grep -q ' /data ext4 ' /proc/mounts 2>/dev/null
}
binary_valid() {
 [ -f "$RUNTIME" ] || return 1
 case "$RUNTIME_HASH" in ''|*[!0-9a-f]*) return 1 ;; esac
 [ "${#RUNTIME_HASH}" -eq 64 ] || return 1
 actual=$(sha256sum "$RUNTIME" | awk '{print $1}')
 [ "$actual" = "$RUNTIME_HASH" ]
}
pid_ok() {
 [ -f "$PIDFILE" ] || return 1
 pid=$(cat "$PIDFILE")
 case "$pid" in ''|*[!0-9]*) return 1 ;; esac
 [ "$pid" -gt 1 ] || return 1
 kill -0 "$pid" 2>/dev/null || return 1
 [ -r "/proc/$pid/cmdline" ] || [ "${XORRISO_RUNTIME_TEST_MODE:-0}" = 1 ] || return 1
 return 0
}
case "${1:-status}" in
 status)
  if ! mounted; then
   echo "Sem disco persistente montado. Use storage mount."
   exit 1
  fi
  if binary_valid; then echo "llama-server: instalado, SHA-256 aprovado ($RUNTIME)."; else
   echo "llama-server: ausente ou verificacao de integridade falhou."
  fi
  if [ -f "$MODEL" ]; then echo "MiniCPM GGUF: encontrado."; else echo "MiniCPM GGUF: ausente."; fi
  if pid_ok; then
   echo "Servidor em execucao (PID $pid): $URL"
   if [ "${XORRISO_RUNTIME_TEST_MODE:-0}" != 1 ]; then
    if curl -fSs --connect-timeout 1 --max-time 3 "$URL/health" >/dev/null 2>&1; then
     echo 'API local: pronta.'
    else
     echo 'API local: sem resposta (modelo carregando, rede local ou processo).'
    fi
   fi
  else
   echo "Servidor parado."
  fi
  ;;
 start)
  mounted || { echo 'Anexe disco persistente e execute storage mount.'; exit 2; }
  binary_valid || { echo 'Runtime ausente ou SHA-256 incorreto. Anexe o VDI XORRISO_RUNTIME, execute storage mount e tente novamente.'; exit 3; }
  [ -f "$MODEL" ] || { echo 'MiniCPM ausente. Use net up e model install.'; exit 4; }
  if [ "${XORRISO_RUNTIME_TEST_MODE:-0}" != 1 ]; then
   /bin/sh /usr/lib/xorriso/model.sh verify >/dev/null || { echo 'Modelo GGUF nao passou na verificacao.'; exit 5; }
  fi
  if [ "${XORRISO_RUNTIME_TEST_MODE:-0}" != 1 ]; then
   /bin/sh /usr/lib/xorriso/loopback.sh up || {
    echo 'Loopback 127.0.0.1 indisponivel; servidor local nao iniciado.'
    exit 6
   }
  fi
  mkdir -p "$RUN_DIR"
  chmod 700 "$RUN_DIR"
  if pid_ok; then echo "Servidor ja ativo (PID $pid)."; exit 0; fi
  if [ -e "$SERVER" ] && [ -L "$SERVER" ]; then echo 'Link simbolico nao permitido.'; exit 6; fi
  cp "$RUNTIME" "$SERVER"
  chmod 700 "$SERVER"
  [ "$(sha256sum "$SERVER" | awk '{print $1}')" = "$RUNTIME_HASH" ] || {
   rm -f "$SERVER"; echo 'Verificacao da copia em RAM falhou.'; exit 7;
  }
  set -- -m "$MODEL" --host 127.0.0.1 --port 8080 --alias MiniCPM-V-4.7-1B -c 2048 -t 2
  if [ -f "$PROJECTOR" ] && [ "${XORRISO_RUNTIME_TEST_MODE:-0}" != 1 ]; then
   set -- "$@" --mmproj "$PROJECTOR"
  fi
  "$SERVER" "$@" > "$LOGFILE" 2>&1 </dev/null &
  pid=$!
  printf '%s\n' "$pid" > "$PIDFILE"
  sleep 2
  if ! kill -0 "$pid" 2>/dev/null; then
   echo 'Servidor encerrou. Consulte runtime log.'
   cat "$LOGFILE" 2>/dev/null | tail -n 12 || :
   rm -f "$PIDFILE"
   exit 8
  fi
  echo "llama-server iniciado no xorriso. PID $pid."
  if [ "${XORRISO_RUNTIME_TEST_MODE:-0}" != 1 ]; then
   echo 'Aguardando o carregamento do modelo e a API local...'
   count=0
   while [ "$count" -lt 30 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
     echo 'Servidor terminou durante o carregamento.'
     tail -n 12 "$LOGFILE" 2>/dev/null || :
     rm -f "$PIDFILE"
     exit 8
    fi
    if curl -fSs --connect-timeout 1 --max-time 2 "$URL/health" >/dev/null 2>&1; then
     echo 'API local pronta: http://127.0.0.1:8080'
     exit 0
    fi
    count=$((count+1))
    sleep 2
   done
   echo 'O processo existe mas a API nao respondeu. Use runtime status e runtime log.'
   exit 9
  fi
  ;;
 stop)
  if ! pid_ok; then echo 'Servidor nao esta em execucao.'; exit 0; fi
  exe=$(readlink "/proc/$pid/exe" 2>/dev/null || :)
  if [ "${XORRISO_RUNTIME_TEST_MODE:-0}" != 1 ] && [ "$exe" != "$SERVER" ]; then
   echo 'PID nao corresponde ao servidor gerenciado. Nenhum processo encerrado.'
   exit 9
  fi
  kill "$pid" || exit 1
  rm -f "$PIDFILE"
  echo 'Servidor local encerrado.'
  ;;
 log) if [ -f "$LOGFILE" ]; then tail -n 25 "$LOGFILE"; else echo 'Sem log de runtime.'; fi ;;
 help)
  echo 'runtime status | runtime start | runtime stop | runtime log'
  echo 'Usa o VDI XORRISO_RUNTIME (somente leitura) e copia o binario verificado para /run.'
  echo 'Nao baixa modelo nem runtime automaticamente.'
  ;;
 *) echo 'Uso: runtime status | runtime start | runtime stop | runtime log'; exit 2 ;;
esac
