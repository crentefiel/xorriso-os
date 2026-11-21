#!/bin/sh
# Root operations are fixed entrypoints, never arbitrary AI-generated shell.
set -eu
PATH=/bin:/usr/bin:/sbin
umask 077
ACTION=${1:-help}
ROOT=${XORRISO_ADMIN_TEST_ROOT:-/}
if [ "${XORRISO_ADMIN_TEST_MODE:-0}" = 1 ]; then
 NETWORK=${XORRISO_ADMIN_TEST_NETWORK:?}
 STORAGE=${XORRISO_ADMIN_TEST_STORAGE:?}
else
 NETWORK=/usr/lib/xorriso/network.sh
 STORAGE=/usr/lib/xorriso/storage.sh
fi
confirm() {
 printf 'Acao administrativa: %s\nAutorizar? [s/N]: ' "$1"
 answer=
 IFS= read -r answer || answer=
 case "$answer" in s|S|sim|SIM) return 0 ;; *) echo 'Operacao cancelada.'; return 2 ;; esac
}
case "$ACTION" in
 help|capabilities)
  echo 'Comandos autorizados ao agente root: capabilities, system_status, disk_status, process_status, network_status, network_up, storage_mount.'
  echo 'Nao ha execucao livre de shell ou instalacao automatica nesta etapa.'
  ;;
 system_status)
  uname -a
  cat /proc/uptime
  free -m
  ;;
 disk_status)
  /bin/sh "$STORAGE" status
  ;;
 process_status)
  ps
  ;;
 network_status)
  /bin/sh "$NETWORK" status
  ;;
 network_up)
  confirm 'ativar rede Linux' || exit $?
  /bin/sh "$NETWORK" up
  ;;
 storage_mount)
  confirm 'montar volumes existentes sem formatar' || exit $?
  /bin/sh "$STORAGE" mount
  ;;
 *)
  echo 'Acao root nao permitida.' >&2
  exit 3 ;;
esac
