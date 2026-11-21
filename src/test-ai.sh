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
jq -e '.messages|length==1 and .[0].role=="user"' "$T/conf/api-request.json" >/dev/null
jq -e 'length==2 and .[0].content=="Ola" and .[1].content=="Resposta simulada da IA."' "$T/conf/chat-history.json" >/dev/null
sh "$ROOT/src/ai-request.sh" 'Segunda mensagem' > "$T/out"
jq -e '.messages|length==3 and .[0].content=="Ola" and .[1].content=="Resposta simulada da IA." and .[2].content=="Segunda mensagem"' "$T/conf/api-request.json" >/dev/null
sh "$ROOT/src/ai-request.sh" --history-status > "$T/out"
grep -q '2' "$T/out"
sh "$ROOT/src/ai-request.sh" --history-last > "$T/out"
grep -Fq 'Ultima pergunta registrada: Segunda mensagem' "$T/out"
sh "$ROOT/src/ai-request.sh" --clear > "$T/out"
sh "$ROOT/src/ai-request.sh" --history-status > "$T/out"
grep -q '0' "$T/out"
[ ! -f "$T/conf/chat-history.json" ]
sh "$ROOT/src/ai-request.sh" --history-last > "$T/out"
grep -Fq 'Nenhuma pergunta registrada' "$T/out"

wrap '{"action":"exec","filename":"","content":"rm -rf /","message":""}'
if sh "$ROOT/src/ai-agent.sh" 'execute qualquer comando' > "$T/out"; then exit 51; fi
grep -q 'fora da lista' "$T/out"
wrap '{"action":"write_note","filename":"../../escape","content":"x","message":""}'
if sh "$ROOT/src/ai-agent.sh" 'grave um arquivo' > "$T/out"; then exit 52; fi
[ ! -f "$T/escape" ]
# A newline must invalidate the ENTIRE filename (grep -E used to match only
# a valid first line, silently permitting a control character in the path).
wrap '{"action":"write_note","filename":"valida.txt\nEVIL","content":"x","message":""}'
if printf 's\n' | sh "$ROOT/src/ai-agent.sh" 'nota maliciosa' > "$T/out"; then
 echo 'Multiline note filename accepted'; exit 60
fi
[ ! -e "$T/notes/valida.txt" ]
wrap '{"action":"read_note","filename":"valida.txt\nEVIL","content":"","message":""}'
if sh "$ROOT/src/ai-agent.sh" 'ler nota maliciosa' > "$T/out"; then
 echo 'Multiline read filename accepted'; exit 61
fi
wrap '{"action":"write_note","filename":"ideias.txt","content":"ideia inicial","message":""}'
printf 'n\n' | sh "$ROOT/src/ai-agent.sh" 'nota' > "$T/out"
[ ! -f "$T/notes/ideias.txt" ]
printf 's\n' | sh "$ROOT/src/ai-agent.sh" 'nota' > "$T/out"
[ "$(cat "$T/notes/ideias.txt")" = 'ideia inicial' ]
wrap '{"action":"read_note","filename":"ideias.txt","content":"","message":""}'
sh "$ROOT/src/ai-agent.sh" 'leia nota' > "$T/out"
grep -q 'ideia inicial' "$T/out"
# The MiniCPM agent may propose a folder, but only actions.sh validates and creates it.
mkdir -p "$T/work"
export XORRISO_ACTION_TEST_ROOT="$T/work/Documentos"
export XORRISO_ACTION_BIN="$ROOT/src/actions.sh"
wrap '{"action":"create_folder","filename":"Pasta AI","content":"","message":""}'
sh "$ROOT/src/ai-agent.sh" 'Crie uma pasta chamada Pasta AI' > "$T/out"
test -d "$T/work/Documentos/Pasta AI"
grep -q 'Pasta criada e verificada' "$T/out"
wrap '{"action":"list_folders","filename":"","content":"","message":""}'
sh "$ROOT/src/ai-agent.sh" 'Liste minhas pastas' > "$T/out"
grep -q 'Pasta AI' "$T/out"
wrap '{"action":"create_folder","filename":"../../escape","content":"","message":""}'
if sh "$ROOT/src/ai-agent.sh" 'Tente escapar do diretorio' > "$T/out"; then exit 59; fi
[ ! -f "$T/escape" ]

echo '{"choices":[{"message":{"content":"nao e JSON"}}]}' > "$XORRISO_TEST_REPLY"
if sh "$ROOT/src/ai-agent.sh" 'teste' > "$T/out"; then exit 53; fi
grep -q 'Nenhuma acao realizada' "$T/out"
rm -f "$T/conf/api_key"
printf 'http://127.0.0.1:8080/v1' > "$T/conf/api_url"
wrap 'Servidor local de teste.'
sh "$ROOT/src/ai-request.sh" 'Teste local' > "$T/out"
grep -q 'Servidor local de teste.' "$T/out"
before=$(wc -l < "$T/curl.log")
sh "$ROOT/src/ai-request.sh" 'Qual foi minha pergunta anterior?' > "$T/out"
grep -Fq 'Consulta ao historico local: Sua pergunta anterior foi: Teste local' "$T/out"
after=$(wc -l < "$T/curl.log")
[ "$before" -eq "$after" ] || { echo 'Recall used curl unexpectedly'; exit 57; }
sh "$ROOT/src/ai-request.sh" --history-last > "$T/out"
grep -Fq 'Ultima pergunta registrada: Qual foi minha pergunta anterior?' "$T/out"
printf '%s' 'http://10.0.2.2:8080/v1' > "$T/conf/api_url"
rm -f "$T/conf/api_key"
wrap 'Resposta do host NAT simulado.'
sh "$ROOT/src/ai-request.sh" 'Modelo no computador host' > "$T/out"
grep -q 'Resposta do host NAT simulado.' "$T/out"
printf 'SEGREDO-QUE-NAO-PODE-SAIR' > "$T/conf/api_key"
if sh "$ROOT/src/ai-request.sh" 'Nao vaze chave' > "$T/out"; then exit 54; fi
grep -q 'bloqueada' "$T/out"
if sh "$ROOT/src/ai-agent.sh" 'Nao vaze chave' > "$T/out"; then exit 55; fi
grep -q 'bloqueada' "$T/out"
! grep -q 'SEGREDO-QUE-NAO-PODE-SAIR' "$T/curl.log"
sh -n "$ROOT/src/ai-agent.sh" "$ROOT/src/ai-request.sh" "$ROOT/src/local.sh" "$ROOT/src/network.sh"
echo 'PASSOU: chat com memoria RAM, recuperacao fiel, limpeza, credenciais, JSON, acoes bloqueadas, notas e localhost.'
