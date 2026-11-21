#!/bin/sh
# Command inventory for the xorriso agent. Inventory is not authorization.
set -eu
PATH=/bin:/usr/bin:/sbin
case "${1:-}" in
 --list)
  echo 'Comandos executaveis instalados no xorriso (inventario, nao permissao):'
  for dir in /bin /usr/bin /sbin /usr/sbin; do
   [ -d "$dir" ] || continue
   for item in "$dir"/*; do
    [ -f "$item" ] && [ -x "$item" ] || continue
    printf '%s\n' "${item##*/}"
   done
  done | LC_ALL=C sort -u
  echo 'Builtins do shell BusyBox dependem da versao; use shell --help no console.'
  ;;
 --status)
  echo 'xorriso - capacidades do Linux'
  printf 'Usuario efetivo: '; id -u 2>/dev/null || awk '/^Uid:/ {print $3}' /proc/self/status
  echo 'Observacao: root do sistema nao autoriza execucao automatica irrestrita.'
  uname -srm
  echo 'Discos:'; /usr/lib/xorriso/storage.sh status
  ;;
 --help|'')
  echo 'catalog --list | catalog --status'
  echo 'A IA pode consultar o inventario. Executar, instalar e alterar o sistema exige uma acao explicitamente permitida.'
  ;;
 *) echo 'Opcao invalida.'; exit 2 ;;
esac
