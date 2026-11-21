#!/bin/sh
# IA plans are untrusted data: allowed actions ONLY, no arbitrary shell.
set -eu
PATH=/bin:/usr/bin:/sbin
CONF=${XORRISO_CONF_DIR:-/run/xorriso}
if [ -n "${XORRISO_NOTES_DIR:-}" ]; then
 NOTES=$XORRISO_NOTES_DIR
elif grep -q ' /data ext4 ' /proc/mounts 2>/dev/null; then
 NOTES=/data/notes
else
 NOTES=/tmp/xorriso/notas
fi
CURL_BIN=${XORRISO_CURL_BIN:-curl}
JQ_BIN=${XORRISO_JQ_BIN:-jq}
ACTION_BIN=${XORRISO_ACTION_BIN:-/usr/lib/xorriso/actions.sh}
getconf() { cat "$CONF/$1" 2>/dev/null || :; }
if [ "${1:-}" = '--notes' ]; then
 mkdir -p "$NOTES"; echo "Notas em $NOTES:"
 ls -1 "$NOTES" 2>/dev/null || :
 exit 0
fi
PROMPT=${1:-}
[ -n "$PROMPT" ] || { echo 'Uso: agent seu pedido'; exit 2; }
BASE=$(getconf api_url); MODEL=$(getconf api_model); KEY=$(getconf api_key)
case "$BASE" in
 https://*) [ -n "$KEY" ] || { echo 'Use api key.'; exit 2; } ;;
 http://127.0.0.1:*|http://localhost:*) : ;;
 http://10.0.2.2:*) [ -z "$KEY" ] || { echo "API key bloqueada no HTTP do host virtual."; exit 2; } ;;
 *) echo 'Configure api url ou api local.'; exit 2 ;;
esac
[ -n "$MODEL" ] || { echo 'Configure api model.'; exit 2; }
umask 077
mkdir -p "$CONF" "$NOTES"
SYSTEM='Voce e um planejador do xorriso Alpha 0.9. Responda SOMENTE com um objeto JSON puro, sem markdown. Escolha uma acao de: status, net_status, list_notes, read_note, write_note, create_folder, list_folders, none. Para read_note, write_note e create_folder use filename simples, sem barras nem caminhos. Para criar pasta, escolha create_folder com filename e para listar pastas list_folders. Para write_note use content texto breve. Nunca gere scripts nem comandos de terminal. Se pedido nao for permitido, action none. Formato: {"action":"none","filename":"","content":"","message":"resposta em portugues"}.'
"$JQ_BIN" -n --arg model "$MODEL" --arg system "$SYSTEM" --arg question "$PROMPT" \
 '{model:$model,messages:[{role:"system",content:$system},{role:"user",content:$question}],temperature:0,stream:false}' \
 > "$CONF/agent-request.json"
if [ -n "$KEY" ]; then
 printf 'Authorization: Bearer %s\n' "$KEY" > "$CONF/api-auth-header"
 if ! "$CURL_BIN" -fSs --connect-timeout 8 --max-time 90 \
  -H 'Content-Type: application/json' -H "@$CONF/api-auth-header" \
  --data-binary "@$CONF/agent-request.json" "$BASE/chat/completions" \
  -o "$CONF/agent-response.json"; then
  echo 'Erro ao consultar IA via API.'; exit 1
 fi
else
 if ! "$CURL_BIN" -fSs --connect-timeout 8 --max-time 90 \
  -H 'Content-Type: application/json' \
  --data-binary "@$CONF/agent-request.json" "$BASE/chat/completions" \
  -o "$CONF/agent-response.json"; then
  echo 'Servidor local indisponivel.'; exit 1
 fi
fi
if ! "$JQ_BIN" -e '.choices[0].message.content | fromjson | select(type=="object")' \
 "$CONF/agent-response.json" > "$CONF/agent-plan.json" 2>/dev/null; then
 echo 'A IA nao retornou um plano JSON valido. Nenhuma acao realizada.'; exit 1
fi
ACTION=$("$JQ_BIN" -r '.action // "none"' "$CONF/agent-plan.json")
MESSAGE=$("$JQ_BIN" -r '.message // ""' "$CONF/agent-plan.json")
FILENAME=$("$JQ_BIN" -r '.filename // ""' "$CONF/agent-plan.json")
case "$ACTION" in
 none)
  printf 'IA: %s\n' "$MESSAGE"; echo 'Nenhuma acao executada.' ;;
 status)
  uname -a; cat /proc/uptime; echo 'Somente leitura.' ;;
 net_status)
  ip -4 addr show;ip route show;echo 'Somente leitura.' ;;
 list_notes)
  echo 'Notas:';ls -1 "$NOTES";echo 'Somente leitura.' ;;
 create_folder)
  echo "Pedido de criacao da pasta: $FILENAME"
  /bin/sh "$ACTION_BIN" "--create:$FILENAME" ;;
 list_folders)
  /bin/sh "$ACTION_BIN" --list ;;

 read_note|write_note)
  case "$FILENAME" in ''|.|..|.*) echo 'Nome invalido.'; exit 3 ;; esac
  if [ "${#FILENAME}" -gt 64 ] || ! printf '%s' "$FILENAME" | grep -Eq '^[a-zA-Z0-9_-][a-zA-Z0-9_.-]*$'; then
   echo 'Nome invalido. Nenhuma acao realizada.'; exit 3
  fi
  TARGET="$NOTES/$FILENAME"
  if [ -L "$TARGET" ]; then echo 'Link simbolico rejeitado.'; exit 3; fi
  if [ "$ACTION" = 'read_note' ]; then
   if [ -f "$TARGET" ]; then cat "$TARGET"; else echo 'Nota nao encontrada.'; fi
   exit 0
  fi
  CONTENT=$("$JQ_BIN" -r '.content // "" | strings' "$CONF/agent-plan.json" 2>/dev/null) || { echo 'Texto invalido.'; exit 3; }
  [ "${#CONTENT}" -le 4096 ] || { echo 'Conteudo longo demais.'; exit 3; }
  echo "Plano: criar nota temporaria $FILENAME";printf 'Conteudo:\n%s\n' "$CONTENT"
  printf 'Autorizar gravacao? [s/N]: '
  IFS= read -r OK || OK=n
  case "$OK" in s|S|sim|SIM)
   (umask 077;printf '%s\n' "$CONTENT" > "$TARGET")
   echo "Nota criada em $TARGET" ;;
   *) echo 'Operacao cancelada.' ;;
  esac ;;
 *)
  echo "Acao '$ACTION' fora da lista permitida. Nada foi executado."; exit 3 ;;
esac
