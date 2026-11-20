#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)";trap 'rm -rf "$T"' EXIT
mkdir -p "$T/conf" "$T/notes" "$T/bin"
printf '%s' 'https://teste.exemplo/v1' > "$T/conf/api_url"
printf '%s' 'modelo-teste' > "$T/conf/api_model"
printf '%s' 'chave-apenas-para-teste' > "$T/conf/api_key"
cat > "$T/bin/curl-mock" <<'MOCK'
#!/bin/sh
: "${XORRISO_TEST_REPLY:?}"; : "${XORRISO_TEST_LOG:?}"
printf '%s\n' "$*" >> "$XORRISO_TEST_LOG"
OUT=
while [ "$#" -gt 0 ]; do
 case "$1" in -o)OUT="$2";shift 2;; *)shift;; esac
done
[ -n "$OUT" ] || exit 10
cp "$XORRISO_TEST_REPLY" "$OUT"
MOCK
chmod +x "$T/bin/curl-mock"
export XORRISO_CONF_DIR="$T/conf" XORRISO_NOTES_DIR="$T/notes" \
 XORRISO_CURL_BIN="$T/bin/curl-mock" XORRISO_TEST_REPLY="$T/answer.json" \
 XORRISO_TEST_LOG="$T/curl.log" XORRISO_JQ_BIN="$(command -v jq)"
wrap() { jq -n --arg response "$1" '{choices:[{message:{content:$response}}]}' > "$XORRISO_TEST_REPLY"; }
wrap 'Resposta simulada da IA.'
[ "$(sh "$ROOT/src/ai-request.sh" 'Ola')" = 'Resposta simulada da IA.' ]
[ -f "$T/conf/api-auth-header" ]
! grep -q 'chave-apenas-para-teste' "$T/curl.log"
jq -e '.model=="modelo-teste"' "$T/conf/api-request.json" >/dev/null
wrap '{"action":"exec","filename":"","content":"rm -rf /","message":""}'
if sh "$ROOT/src/ai-agent.sh" 'execute qualquer comando' > "$T/out"; then exit 51; fi
grep -q 'fora da lista' "$T/out"
wrap '{"action":"write_note","filename":"../../escape","content":"x","message":""}'
if sh "$ROOT/src/ai-agent.sh" 'grave um arquivo' > "$T/out"; then exit 52; fi
[ ! -f "$T/escape" ]
wrap '{"action":"write_note","filename":"ideias.txt","content":"ideia inicial","message":""}'
printf 'n\n' | sh "$ROOT/src/ai-agent.sh" 'nota' > "$T/out"
[ ! -f "$T/notes/ideias.txt" ]
printf 's\n' | sh "$ROOT/src/ai-agent.sh" 'nota' > "$T/out"
[ "$(cat "$T/notes/ideias.txt")" = 'ideia inicial' ]
wrap '{"action":"read_note","filename":"ideias.txt","content":"","message":""}'
sh "$ROOT/src/ai-agent.sh" 'leia nota' > "$T/out"
grep -q 'ideia inicial' "$T/out"
echo '{"choices":[{"message":{"content":"nao e JSON"}}]}' > "$XORRISO_TEST_REPLY"
if sh "$ROOT/src/ai-agent.sh" 'teste' > "$T/out"; then exit 53; fi
grep -q 'Nenhuma acao realizada' "$T/out"
rm -f "$T/conf/api_key"
printf 'http://127.0.0.1:8080/v1' > "$T/conf/api_url"
wrap 'Servidor local de teste.'
sh "$ROOT/src/ai-request.sh" 'Teste local' > "$T/out"
grep -q 'Servidor local de teste.' "$T/out"
sh -n "$ROOT/src/ai-agent.sh" "$ROOT/src/ai-request.sh" "$ROOT/src/local.sh" "$ROOT/src/network.sh"
echo 'PASSOU: chat, credenciais, JSON, acoes bloqueadas, notas e localhost.'
