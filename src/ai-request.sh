#!/bin/sh
# Chat completions client: short, memory-limited conversation stored ONLY in RAM.
# Model text is untrusted data and NEVER executed as a shell command.
set -eu
PATH=/bin:/usr/bin:/sbin
CONF=${XORRISO_CONF_DIR:-/run/xorriso}
CURL_BIN=${XORRISO_CURL_BIN:-curl}
JQ_BIN=${XORRISO_JQ_BIN:-jq}
umask 077
mkdir -p "$CONF"
HISTORY="$CONF/chat-history.json"
getconf() { cat "$CONF/$1" 2>/dev/null || :; }
case "${1:-}" in
 --clear)
  rm -f "$HISTORY" "$HISTORY.tmp" "$CONF/api-request.json" "$CONF/api-response.json" "$CONF/api-message.txt"
  echo 'Conversa e respostas temporarias apagadas da memoria RAM.'
  exit 0 ;;
 --history-status)
  if [ -f "$HISTORY" ] && "$JQ_BIN" -e 'type=="array"' "$HISTORY" >/dev/null 2>&1; then
   turns=$("$JQ_BIN" -r '[.[] | select(.role=="user")] | length' "$HISTORY")
  else
   turns=0
  fi
  echo "Trocas de conversa armazenadas na RAM: $turns"
  exit 0 ;;
esac
BASE=$(getconf api_url)
MODEL=$(getconf api_model)
KEY=$(getconf api_key)
case "$BASE" in
 https://*) : ;;
 http://127.0.0.1:*|http://localhost:*) : ;;
 http://10.0.2.2:*) [ -z "$KEY" ] || { echo 'API key bloqueada no HTTP do host virtual.'; exit 2; } ;;
 *) echo 'Configure api url com HTTPS ou api local.'; exit 2 ;;
esac
[ -n "$MODEL" ] || { echo 'Configure api model ID.'; exit 2; }
case "$BASE" in
 http://127.0.0.1:*|http://localhost:*|http://10.0.2.2:*) : ;;
 *) [ -n "$KEY" ] || { echo 'Chave ausente. Use api key.'; exit 2; } ;;
esac
if [ -n "$KEY" ]; then
 printf 'Authorization: Bearer %s\n' "$KEY" > "$CONF/api-auth-header"
fi
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
if [ "${1:-}" = '--test' ]; then
 echo "Consultando modelos em $BASE/models ..."
 if [ -n "$KEY" ]; then
  "$CURL_BIN" -fSs --connect-timeout 8 --max-time 25 -H "@$CONF/api-auth-header" "$BASE/models" -o "$CONF/api-response.json"
 else
  "$CURL_BIN" -fSs --connect-timeout 8 --max-time 25 "$BASE/models" -o "$CONF/api-response.json"
 fi
 "$JQ_BIN" -r '.data[0:10][]?.id // empty' "$CONF/api-response.json" || :
 exit 0
fi
PROMPT=${1:-}
[ -n "$PROMPT" ] || { echo 'Pergunta vazia.'; exit 2; }
# Truncate history to four turns; never persist it to /data.
if [ ! -f "$HISTORY" ] ||
 ! "$JQ_BIN" -e 'type=="array" and length<=8 and all(.[]; type=="object" and (.role=="user" or .role=="assistant") and (.content|type=="string"))' "$HISTORY" >/dev/null 2>&1; then
 printf '[]\n' > "$HISTORY"
fi
LOCAL=0
case "$BASE" in http://127.0.0.1:*|http://localhost:*) LOCAL=1 ;; esac
SYSTEM='Voce e a IA local do xorriso. Responda em portugues brasileiro, de modo natural e breve. Use texto simples, sem arte ASCII, emojis, bordas, simbolos decorativos ou Markdown. Para facilitar o console Linux, prefira letras ASCII sem acentos. Se nao souber a resposta, diga que nao sabe.'
"$JQ_BIN" -n --arg model "$MODEL" --arg content "$PROMPT" --arg sys "$SYSTEM" \
 --argjson local "$LOCAL" --slurpfile history "$HISTORY" \
 '{model:$model,messages:((if $local==1 then [{role:"system",content:$sys}] else [] end)+$history[0]+[{role:"user",content:$content}]),stream:false,max_tokens:256,temperature:0.6}' \
 > "$CONF/api-request.json"
if [ -n "$KEY" ]; then
 if ! "$CURL_BIN" -fSs --connect-timeout 8 --max-time 120 \
  -H 'Content-Type: application/json' -H "@$CONF/api-auth-header" \
  --data-binary "@$CONF/api-request.json" "$BASE/chat/completions" \
  -o "$CONF/api-response.json"; then
  echo 'Falha na API (rede, modelo, chave ou endpoint).'; exit 1
 fi
else
 if ! "$CURL_BIN" -fSs --connect-timeout 8 --max-time 120 \
  -H 'Content-Type: application/json' \
  --data-binary "@$CONF/api-request.json" "$BASE/chat/completions" \
  -o "$CONF/api-response.json"; then
  echo 'Servidor local indisponivel.'; exit 1
 fi
fi
if ! "$JQ_BIN" -er '.choices[0].message.content | select(type=="string" and length>0)' \
 "$CONF/api-response.json" > "$CONF/api-message.txt"; then
 "$JQ_BIN" -r '.error.message // "Resposta invalida ou vazia do modelo."' "$CONF/api-response.json" 2>/dev/null || echo 'JSON invalido.'
 exit 1
fi
# Keep only four user/assistant pairs, in RAM. Do not retain failed requests.
"$JQ_BIN" -n --arg prompt "$PROMPT" --slurpfile history "$HISTORY" \
 --slurpfile resp "$CONF/api-response.json" \
 '($history[0]+[{role:"user",content:$prompt},{role:"assistant",content:$resp[0].choices[0].message.content}])[-8:]' > "$HISTORY.tmp"
mv "$HISTORY.tmp" "$HISTORY"
cat "$CONF/api-message.txt"
