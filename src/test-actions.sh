#!/usr/bin/env bash
# Test real filesystem changes in an isolated directory; no physical disks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/user" "$T/run" "$T/data/models" "$T/runtime" "$T/bin"
export XORRISO_ACTION_TEST_ROOT="$T/user/Documentos"
sh -n "$ROOT/src/actions.sh" "$ROOT/src/ai-boot.sh"
sh "$ROOT/src/actions.sh" 'Crie uma pasta chamada Meus Projetos' > "$T/out"
test -d "$XORRISO_ACTION_TEST_ROOT/Meus Projetos"
grep -q 'Pasta criada e verificada' "$T/out"
sh "$ROOT/src/actions.sh" 'Liste minhas pastas' > "$T/out"
grep -q 'Meus Projetos' "$T/out"
printf 'arquivo\n' > "$XORRISO_ACTION_TEST_ROOT/arquivo.txt"
mkdir "$XORRISO_ACTION_TEST_ROOT/Outra Pasta"
sh "$ROOT/src/actions.sh" 'Liste minhas pastas' > "$T/out"
grep -q 'Outra Pasta' "$T/out"
if grep -q 'arquivo.txt' "$T/out"; then echo 'File included in folder list'; exit 37; fi
sh "$ROOT/src/actions.sh" 'Crie uma pasta chamada Meus Projetos' > "$T/out"
grep -q 'ja existe' "$T/out"
for bad in '--create:../../etc' '--create:../escape' '--create:;touch /tmp/pwn' '--create:arquivo/nome' '--create:.oculta'; do
 if sh "$ROOT/src/actions.sh" "$bad" > "$T/out"; then echo "Unsafe name accepted: $bad"; exit 32; fi
done
test ! -e "$T/escape"
if sh "$ROOT/src/actions.sh" $'--create:Ok\n../escape' > "$T/out"; then
 echo 'Multiline filename accepted'; exit 36
fi
printf 'spoof\n' > "$T/file"
ln -s "$T/file" "$XORRISO_ACTION_TEST_ROOT/Link Pasta"
if sh "$ROOT/src/actions.sh" '--create:Link Pasta' > "$T/out"; then echo 'Symlink not rejected'; exit 33; fi
# Basic file tools: literal text, no clobber, no path traversal.
sh "$ROOT/src/actions.sh" '--write:anotações.txt' 'Linha criada pela IA' > "$T/out"
test -f "$XORRISO_ACTION_TEST_ROOT/anotações.txt"
grep -q 'Arquivo criado e verificado' "$T/out"
sh "$ROOT/src/actions.sh" '--read:anotações.txt' > "$T/out"
grep -q 'Linha criada pela IA' "$T/out"
sh "$ROOT/src/actions.sh" --files > "$T/out"
grep -q 'anotações.txt' "$T/out"
if sh "$ROOT/src/actions.sh" '--write:anotações.txt' 'texto sobrescrito' > "$T/out"; then
 echo 'Existing file overwritten'; exit 46
fi
grep -q 'Linha criada pela IA' "$XORRISO_ACTION_TEST_ROOT/anotações.txt"
if sh "$ROOT/src/actions.sh" '--write:../escape' 'Nao' > "$T/out"; then
 echo 'Unsafe file name accepted'; exit 47
fi
test ! -e "$T/user/escape"

# The desktop must send arbitrary natural-language requests to the LLM planner,
# not match fixed phrases. Mock the LLM response; verify real tool execution.
export XORRISO_CONF_DIR="$T/run"
export XORRISO_ACTION_BIN="$ROOT/src/actions.sh"
export XORRISO_AGENT_BIN="$ROOT/src/ai-agent.sh"
export XORRISO_JQ_BIN="$(command -v jq)"
export XORRISO_CURL_BIN="$T/bin/agent-curl-mock"
export XORRISO_TEST_REPLY="$T/agent-answer.json"
printf '%s' 'http://127.0.0.1:8080/v1' > "$T/run/api_url"
printf '%s' 'modelo-mock' > "$T/run/api_model"
cat > "$T/bin/agent-curl-mock" <<'MOCK'
#!/bin/sh
out=
while [ "$#" -gt 0 ]; do
 case "$1" in -o) out=$2; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] || exit 21
cp "$XORRISO_TEST_REPLY" "$out"
MOCK
chmod +x "$T/bin/agent-curl-mock"
mock_plan() {
 jq -n --arg action "$1" --arg filename "${2:-}" --arg message "${3:-}" \
  '{choices:[{message:{content:({action:$action,filename:$filename,content:"",message:$message}|tojson)}}]}' \
  > "$XORRISO_TEST_REPLY"
}
mock_plan create_folder 'Projetos Internos 2026'
phrase='Você pode organizar uma nova pasta com o nome Projetos Internos 2026?'
sh "$ROOT/src/chat-actions.sh" "$phrase" > "$T/out"
jq -e --arg phrase "$phrase" '.messages[-1].content==$phrase' "$T/run/agent-request.json" >/dev/null
grep -q 'Pasta criada e verificada' "$T/out"
test -d "$XORRISO_ACTION_TEST_ROOT/Projetos Internos 2026"
mock_plan create_folder 'Músicas para João'
sh "$ROOT/src/chat-actions.sh" 'Pode abrir uma pasta para as músicas do João?' > "$T/out"
test -d "$XORRISO_ACTION_TEST_ROOT/Músicas para João"
mock_plan create_file 'resumo.txt' 'Relatorio criado pela IA e confirmado'
sh "$ROOT/src/chat-actions.sh" 'Escreva em resumo.txt: Relatorio criado pela IA e confirmado' > "$T/out"
grep -q 'Arquivo criado e verificado' "$T/out"
grep -q 'Relatorio criado pela IA e confirmado' "$XORRISO_ACTION_TEST_ROOT/resumo.txt"
mock_plan read_file 'resumo.txt'
sh "$ROOT/src/chat-actions.sh" 'Leia o resumo que fez' > "$T/out"
grep -q 'Relatorio criado pela IA e confirmado' "$T/out"
mock_plan list_files ''
sh "$ROOT/src/chat-actions.sh" 'Mostre todos os documentos' > "$T/out"
grep -q 'resumo.txt' "$T/out"
mock_plan create_folder 'Fotos de Natal'
sh "$ROOT/src/chat-actions.sh" 'Monte outra area onde vou guardar as fotos do Natal' > "$T/out"
test -d "$XORRISO_ACTION_TEST_ROOT/Fotos de Natal"
mock_plan check_folder ''
sh "$ROOT/src/chat-actions.sh" 'Me mostra a ultima coisa que voce criou?' > "$T/out"
grep -q 'Pasta existe e foi verificada' "$T/out"
grep -q 'Fotos de Natal' "$T/out"
mock_plan list_folders ''
sh "$ROOT/src/chat-actions.sh" 'Quais diretorios estao disponiveis aqui?' > "$T/out"
grep -q 'Projetos Internos 2026' "$T/out"
grep -q 'Fotos de Natal' "$T/out"
mock_plan none '' 'Uma pasta organiza arquivos no sistema.'
sh "$ROOT/src/chat-actions.sh" 'O que e uma pasta?' > "$T/out"
grep -q 'Uma pasta organiza arquivos' "$T/out"
mock_plan create_folder '../escape'
if sh "$ROOT/src/chat-actions.sh" 'Pedido malicioso de pasta' > "$T/out"; then
 echo 'Unsafe LLM folder name accepted'; exit 39
fi
test ! -e "$T/user/escape"
# A failed action does not replace the last confirmed folder.
mock_plan check_folder ''
sh "$ROOT/src/chat-actions.sh" 'Cheque minha ultima pasta' > "$T/out"
grep -q 'Fotos de Natal' "$T/out"

# Local IA auto-start, both model and runtime are known TEST fixtures.
export XORRISO_AUTOSTART_TEST_MODE=1
export XORRISO_AUTOSTART_TEST_DATA="$T/data"
export XORRISO_AUTOSTART_TEST_RUNTIME="$T/runtime/llama-server"
export XORRISO_AUTOSTART_TEST_STORAGE="$T/bin/storage"
export XORRISO_AUTOSTART_TEST_SERVER="$T/bin/server"
export XORRISO_AUTOSTART_TEST_LOOPBACK="$T/bin/loopback"
export XORRISO_CONF_DIR="$T/run"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/storage"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/server"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/loopback"
touch "$T/data/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf" "$T/runtime/llama-server"
sh "$ROOT/src/ai-boot.sh" start
test "$(sh "$ROOT/src/ai-boot.sh" status)" = 'pronta'
grep -q '^http://127.0.0.1:8080/v1$' "$T/run/api_url"
grep -q '^MiniCPM-V-4.7-1B$' "$T/run/api_model"
rm "$T/runtime/llama-server"
if sh "$ROOT/src/ai-boot.sh" start; then echo 'Missing runtime accepted'; exit 34; fi
grep -q 'indisponivel: VDI do motor' "$T/run/boot-status"
touch "$T/runtime/llama-server"
printf '#!/bin/sh\nexit 4\n' > "$T/bin/server"
if sh "$ROOT/src/ai-boot.sh" start; then echo 'Failed server reported ready'; exit 35; fi
grep -q '^falha: MiniCPM nao ficou pronto' "$T/run/boot-status"
# Late-appearing model on the second storage scan must start successfully.
rm -f "$T/data/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf"
if sh "$ROOT/src/ai-boot.sh" start; then echo 'Missing model accepted'; exit 38; fi
grep -q '^indisponivel: modelo nao encontrado' "$T/run/boot-status"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/server"
cat > "$T/bin/storage" <<'STORAGE'
#!/bin/sh
printf '.\n' >> "$XORRISO_AUTOSTART_TEST_DATA/attempts"
if [ "$(wc -l < "$XORRISO_AUTOSTART_TEST_DATA/attempts")" -eq 2 ]; then
 touch "$XORRISO_AUTOSTART_TEST_DATA/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf"
fi
STORAGE
sh "$ROOT/src/ai-boot.sh" start
test "$(sh "$ROOT/src/ai-boot.sh" status)" = 'pronta'
test "$(wc -l < "$T/data/attempts")" -eq 2
echo 'PASS: safe real folders; automatic IA boot; delayed model and missing components'
