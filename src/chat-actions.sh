#!/bin/sh
# Single chat entrypoint: filesystem intents are real operations, never fake LLM answers.
set -eu
PATH=/bin:/usr/bin:/sbin
ACTION=${XORRISO_ACTION_BIN:-/usr/lib/xorriso/actions.sh}
CHAT=${XORRISO_CHAT_BIN:-/usr/lib/xorriso/ai-request.sh}
CONF=${XORRISO_CONF_DIR:-/run/xorriso}
mkdir -p "$CONF"
input=${1:-}
lower=$(printf '%s' "$input" | LC_ALL=C tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
# Trim trailing spaces. Do not treat user text as shell source.
while [ "${input% }" != "$input" ]; do input=${input% }; done
while [ "${lower% }" != "$lower" ]; do lower=${lower% }; done
do_create() {
 name=$1
 [ -n "$name" ] || { echo 'Informe o nome da pasta.'; return 2; }
 # Save the outcome, not just the requested plan. Never claim success on errors.
 if output=$(/bin/sh "$ACTION" "--create:$name" 2>&1); then
  printf '%s\n' "$output"
  printf 'Pasta: %s\n' "$name" > "$CONF/last-folder"
 else
  printf '%s\n' "$output"
  rm -f "$CONF/last-folder"
  return 1
 fi
}
case "$lower" in
 'liste minhas pastas'|'mostre minhas pastas'|'listar pastas'|'listar minhas pastas'|'quais pastas existem')
  /bin/sh "$ACTION" --list ;;
 'conseguiu criar'*|'criou a pasta'*|'cade a pasta'*|'onde esta a pasta'*|'verifique a pasta'*)
  if [ -s "$CONF/last-folder" ]; then
   name=$(sed -n 's/^Pasta: //p' "$CONF/last-folder")
   [ -n "$name" ] && /bin/sh "$ACTION" "--check:$name" || echo 'Nao ha pasta registrada.'
  else echo 'Nao ha criacao de pasta confirmada nesta sessao.'; fi ;;
 'cria pasta '*|'crie pasta '*|'criar pasta '*|'cria uma pasta '*|'crie uma pasta '*|'criar uma pasta '*|'crie a pasta '*|'cria a pasta '*|'criar a pasta '*|'quero criar uma pasta '*)
  case "$lower" in
   *' chamada '*)
    name=${input#* chamada } ;;
   *' pasta '*)
    name=${input#* pasta } ;;
   *)
    echo 'Informe o nome da pasta.'; exit 2 ;;
  esac
  do_create "$name" ;;
 *'criar pasta'*|*'cria pasta'*|*'crie pasta'*|*'criou pasta'*)
  echo 'Pedido de pasta nao reconhecido. Tente: cria pasta xorriso'; exit 2 ;;
 *)
  /bin/sh "$CHAT" "$input" ;;
esac
