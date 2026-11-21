#!/bin/sh
# Discover real executable commands and BusyBox applets at runtime.
# Knowledge is not permission to execute: all root actions require approval.
set -eu
PATH=/bin:/usr/bin:/sbin:/usr/sbin
list_commands() {
  for dir in /bin /usr/bin /sbin /usr/sbin; do
    [ -d "$dir" ] || continue
    for item in "$dir"/*; do
      [ -f "$item" ] && [ -x "$item" ] || continue
      printf '%s\n' "${item##*/}"
    done
  done
  if command -v busybox >/dev/null 2>&1; then
    busybox --list 2>/dev/null || :
  fi
}
case "${1:-}" in
 --list)
  echo 'Comandos realmente disponíveis (executáveis e applets BusyBox):'
  list_commands | LC_ALL=C sort -u
  echo 'Inventário informativo; ações administrativas requerem autorização.'
  ;;
 --find)
  query=${2:-}
  case "$query" in ''|*[!a-zA-Z0-9_.+-]*) echo 'Informe um nome de comando válido.'; exit 2 ;; esac
  list_commands | LC_ALL=C sort -u | grep -Fxi -- "$query" || {
    echo "Comando $query não encontrado neste sistema."; exit 1;
  }
  ;;
 --status)
  echo 'xorriso - capacidades do Linux'
  printf 'Usuario efetivo: '; id -u 2>/dev/null || awk '/^Uid:/ {print $3}' /proc/self/status
  echo 'Root não significa autorização automática para comandos perigosos.'
  uname -srm
  echo 'Discos:'
  /usr/lib/xorriso/storage.sh status
  ;;
 --help|'')
  echo 'catalog --list | catalog --find NOME | catalog --status'
  echo 'Inclui applets BusyBox mesmo quando não existe um link em /bin.'
  ;;
 *) echo 'Opção inválida.'; exit 2 ;;
esac
