#!/bin/sh
# Run only on the Linux HOST, not inside xorriso's minimal initramfs.
# llama.cpp obtains weights on demand and stores them outside the ISO.
set -eu
if ! command -v llama-server >/dev/null 2>&1; then
  echo "Instale llama-server atualizado do projeto https://github.com/ggml-org/llama.cpp"
  echo "Nenhum arquivo foi baixado por este script."
  exit 2
fi
echo "MiniCPM-V 4.7 1B sera iniciado no computador anfitriao."
echo "Os pesos GGUF serao baixados apenas se nao estiverem em cache."
echo "NAO exponha a porta 8080 diretamente a internet."
exec llama-server -hf openbmb/MiniCPM-V-4.7-1B-gguf:Q4_K_M \
  --host 127.0.0.1 --port 8080 --alias MiniCPM-V-4.7-1B
