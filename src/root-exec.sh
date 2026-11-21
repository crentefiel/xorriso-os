#!/bin/sh
# xorriso root command executor.
# The LLM may PROPOSE a Linux command, but only the human may approve it.
# This is intentionally root in the experimental single-user xorriso OS.
set -eu
PATH=/bin:/usr/bin:/sbin
umask 077
CONF=${XORRISO_CONF_DIR:-/run/xorriso}
PENDING=$CONF/root-pending
BUSYBOX=${XORRISO_BUSYBOX_BIN:-/bin/busybox}

fail() { printf '%s\n' "$1"; exit "${2:-2}"; }
init() {
 [ ! -L "$CONF" ] || fail 'Diretorio de controle nao confiavel.'
 mkdir -p "$CONF"
 chmod 700 "$CONF"
 [ ! -L "$PENDING" ] || fail 'Fila de comandos nao confiavel.'
}
validate_command() {
 command_text=$1
 [ -n "$command_text" ] && [ "${#command_text}" -le 1000 ] ||
   fail 'Comando vazio ou maior que 1000 bytes.'
 # Single-line preview: prevent hidden newlines in the human confirmation.
 cleaned=$(printf '%s' "$command_text" | LC_ALL=C tr -d '\011\012\015')
 [ "$cleaned" = "$command_text" ] ||
   fail 'Comando com caracteres de controle nao permitido.'
}
token_ok() {
 case "$1" in *[!0-9a-f]*|'') return 1 ;; esac
 [ "${#1}" -eq 16 ]
}
audit() {
 now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
 printf '%s | %s | %s\n' "$now" "$1" "$2" >> "$CONF/root-audit.log"
}
init
mode=${1:-}
case "$mode" in
 --propose)
  command_text=${2:-}
  validate_command "$command_text"
  [ ! -e "$PENDING" ] ||
   fail 'Ja existe comando pendente. Autorize ou cancele antes de propor outro.' 3
  token=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
  token_ok "$token" || fail 'Falha ao gerar identificador seguro.' 3
  mkdir -m 700 "$PENDING" || fail 'Nao foi possivel criar confirmacao.'
  if ! {
    printf '%s\n' "$token" > "$PENDING/token"
    date +%s > "$PENDING/created"
    printf '%s' "$command_text" > "$PENDING/command"
  }; then
    rm -rf -- "$PENDING"
    fail 'Nao foi possivel salvar a proposta.'
  fi
  audit PROPOSE "$token"
  printf 'A IA PROPOS um comando Linux como root, mas NAO executou:\n'
  printf '  %s\n' "$command_text"
  printf 'Para executar, DIGITE exatamente: autorizar %s\n' "$token"
  printf 'Para descartar, DIGITE: cancelar %s\n' "$token"
  printf 'Expira em 5 minutos. Revise o comando; pode alterar o sistema.\n'
  ;;
 --approve:*|--cancel:*)
  token=${mode#*:}
  token_ok "$token" || fail 'Identificador de confirmacao invalido.'
  [ -d "$PENDING" ] && [ ! -L "$PENDING" ] ||
    fail 'Nao ha comando aguardando autorizacao.' 3
  saved=$(cat "$PENDING/token" 2>/dev/null || :)
  [ "$saved" = "$token" ] || fail 'Codigo nao corresponde ao pedido pendente.' 3
  created=$(cat "$PENDING/created" 2>/dev/null || :)
  case "$created" in *[!0-9]*|'') fail 'Registro de confirmacao corrompido.' 3 ;; esac
  now=$(date +%s)
  if [ "$now" -lt "$created" ] || [ "$((now-created))" -gt 300 ]; then
    rm -rf -- "$PENDING"
    audit EXPIRED "$token"
    fail 'A autorizacao expirou. Peca a acao novamente.' 3
  fi
  if [ "${mode%%:*}" = '--cancel' ]; then
    rm -rf -- "$PENDING"
    audit CANCEL "$token"
    echo 'Comando cancelado. Nenhuma acao executada.'
    exit 0
  fi
  command_text=$(cat "$PENDING/command")
  validate_command "$command_text"
  RUNNING="$CONF/root-running.$$"
  [ ! -e "$RUNNING" ] || fail 'Erro de estado, abortado.' 3
  mv "$PENDING" "$RUNNING" || fail 'Nao foi possivel validar confirmacao.' 3
  trap 'rm -rf -- "$RUNNING"' EXIT HUP INT TERM
  audit APPROVE "$token"
  printf 'Executando comando aprovado como root:\n  %s\n' "$command_text"
  output="$RUNNING/output"
  rc=0
  "$BUSYBOX" timeout -s KILL 25 /bin/sh -c "$command_text" > "$output" 2>&1 || rc=$?
  printf 'Saida real (maximo de 4000 bytes):\n'
  head -c 4000 "$output" || :
  printf '\nCodigo de saida: %s\n' "$rc"
  audit RESULT "$token exit=$rc"
  [ "$rc" -eq 0 ] || exit "$rc"
  ;;
 --status)
  if [ -d "$PENDING" ] && [ ! -L "$PENDING" ]; then
    printf 'Comando aguardando autorizacao: %s\n' "$(cat "$PENDING/token")"
    printf '%s\n' "$(cat "$PENDING/command")"
  else
    echo 'Nenhum comando root pendente.'
  fi
  ;;
 *)
  fail 'Uso: root-exec.sh --propose COMANDO | --approve:CODIGO | --cancel:CODIGO | --status'
  ;;
esac
