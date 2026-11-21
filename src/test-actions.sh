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
# Natural language chat must trigger a verified real operation, never an LLM echo.
export XORRISO_CONF_DIR="$T/run"
export XORRISO_ACTION_BIN="$ROOT/src/actions.sh"
export XORRISO_CHAT_BIN="$T/bin/fallback-chat"
printf '#!/bin/sh\necho "RESPOSTA-IA"\n' > "$T/bin/fallback-chat"
chmod +x "$T/bin/fallback-chat"
sh "$ROOT/src/chat-actions.sh" 'cria pasta xorriso' > "$T/out"
grep -q 'Pasta criada e verificada' "$T/out"
test -d "$XORRISO_ACTION_TEST_ROOT/xorriso"
sh "$ROOT/src/chat-actions.sh" 'conseguiu criar?' > "$T/out"
grep -q 'Pasta existe e foi verificada' "$T/out"
sh "$ROOT/src/chat-actions.sh" 'liste minhas pastas' > "$T/out"
grep -q '^xorriso
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
 "$T/out"
sh "$ROOT/src/chat-actions.sh" 'como vai?' > "$T/out"
grep -q 'RESPOSTA-IA' "$T/out"
if sh "$ROOT/src/chat-actions.sh" 'cria pasta ../../escape' > "$T/out"; then
 echo 'Unsafe natural folder name accepted'; exit 39
fi
sh "$ROOT/src/chat-actions.sh" 'conseguiu criar?' > "$T/out"
grep -q 'Nao ha criacao de pasta confirmada' "$T/out"
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
