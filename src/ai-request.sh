#!/bin/sh
# Chat completions client; output is data, NEVER executed by shell.
set -eu
PATH=/bin:/usr/bin:/sbin
CONF=${XORRISO_CONF_DIR:-/run/xorriso}
CURL_BIN=${XORRISO_CURL_BIN:-curl}
JQ_BIN=${XORRISO_JQ_BIN:-jq}
getconf() { cat "$CONF/$1" 2>/dev/null || :; }
BASE=$(getconf api_url); MODEL=$(getconf api_model); KEY=$(getconf api_key)
case "$BASE" in
 https://*) : ;;
 http://127.0.0.1:*|http://localhost:*) : ;;
 *) echo 'Configure api url com HTTPS ou api local.'; exit 2 ;;
esac
[ -n "$MODEL" ] || { echo 'Configure api model ID.'; exit 2; }
case "$BASE" in
 http://127.0.0.1:*|http://localhost:*) : ;;
 *) [ -n "$KEY" ] || { echo 'Chave ausente. Use api key.'; exit 2; } ;;
esac
umask 077
mkdir -p "$CONF"
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
"$JQ_BIN" -n --arg model "$MODEL" --arg content "$PROMPT" \
 '{model:$model,messages:[{role:"user",content:$content}],stream:false}' \
 > "$CONF/api-request.json"
if [ -n "$KEY" ]; then
 if ! "$CURL_BIN" -fSs --connect-timeout 8 --max-time 90 \
  -H 'Content-Type: application/json' -H "@$CONF/api-auth-header" \
  --data-binary "@$CONF/api-request.json" "$BASE/chat/completions" \
  -o "$CONF/api-response.json"; then
  echo 'Falha na API (rede, modelo, chave ou endpoint).'; exit 1
 fi
else
 if ! "$CURL_BIN" -fSs --connect-timeout 8 --max-time 90 \
  -H 'Content-Type: application/json' \
  --data-binary "@$CONF/api-request.json" "$BASE/chat/completions" \
  -o "$CONF/api-response.json"; then
  echo 'Servidor local indisponivel.'; exit 1
 fi
fi
"$JQ_BIN" -er '.choices[0].message.content // .error.message // "Resposta sem texto reconhecivel"' \
 "$CONF/api-response.json" || { echo 'JSON invalido.'; exit 1; }
