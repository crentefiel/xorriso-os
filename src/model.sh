#!/bin/sh
# xorriso Alpha 0.10 — opt-in MiniCPM GGUF installer, NO inference runtime.
# Official SHA-256 values from openbmb/MiniCPM-V-4.7-1B-gguf.
set -eu
PATH=/bin:/usr/bin:/sbin
umask 077

MODEL_DIR=/data/models
MODEL_URL=https://huggingface.co/openbmb/MiniCPM-V-4.7-1B-gguf/resolve/main
WEIGHT=MiniCPM-V-4_7-1B-Q4_K_M.gguf
PROJECTOR=mmproj-model-f16.gguf
WEIGHT_SHA=f18f594747e5317ab490cff9c06339c9cfb89acbe2f02ebc48a4e167bc23576d
PROJECTOR_SHA=fb9cc047a3cdad5317fd8433a4aeda2d22f00f02ca4bd93b34ad84165b25a900

# Test-only hooks allow tiny simulated downloads; they are never used in the ISO.
TEST_MODE=${XORRISO_MODEL_TEST_MODE:-0}
if [ "$TEST_MODE" = 1 ]; then
 MODEL_DIR=${XORRISO_MODEL_TEST_DIR:?Missing test directory}
 WEIGHT_SHA=${XORRISO_MODEL_TEST_WEIGHT_SHA:?Missing test hash}
 PROJECTOR_SHA=${XORRISO_MODEL_TEST_PROJECTOR_SHA:?Missing test hash}
fi
CURL_BIN=${XORRISO_CURL_BIN:-curl}

storage_ready() {
 if [ "$TEST_MODE" = 1 ]; then return 0; fi
 grep -q ' /data ext4 ' /proc/mounts 2>/dev/null || {
  echo 'Conecte e monte primeiro o disco persistente: storage mount'
  echo 'O xorriso nunca baixa os pesos na RAM.'
  return 1
 }
}

check_hash() {
 file=$1 expected=$2
 [ -f "$file" ] || return 1
 actual=$(sha256sum "$file" | awk '{print $1}')
 [ "$actual" = "$expected" ]
}

report_file() {
 filename=$1 expected=$2
 if [ ! -f "$MODEL_DIR/$filename" ]; then
  echo "$filename: nao instalado"
 elif check_hash "$MODEL_DIR/$filename" "$expected"; then
  echo "$filename: OK (SHA-256 verificado)"
 else
  echo "$filename: hash diferente, arquivo nao confiavel"
  return 1
 fi
}

ensure_space() {
 required_kb=$1
 if [ "$TEST_MODE" = 1 ]; then return 0; fi
 available=$(df -k /data | awk 'NR==2 {print $4}')
 case "$available" in ''|*[!0-9]*) echo 'Nao consegui conferir o espaco disponivel.'; return 1 ;; esac
 if [ "$available" -lt "$required_kb" ]; then
  echo "Espaco insuficiente no disco de dados: livres ${available} KiB."
  return 1
 fi
}

get_file() {
 filename=$1 expected=$2 size_label=$3 required_kb=$4
 storage_ready || return 1
 mkdir -p "$MODEL_DIR"
 target="$MODEL_DIR/$filename"
 if [ -f "$target" ]; then
  if check_hash "$target" "$expected"; then
   echo "$filename ja instalado e verificado."
   return 0
  fi
  echo "Arquivo existente tem hash incorreto: $target"
  echo 'Nao vou sobrescrever um arquivo existente. Verifique manualmente.'
  return 1
 fi
 ensure_space "$required_kb" || return 1
 echo "Download oficial: $filename ($size_label)."
 echo 'Conexao HTTPS; o SHA-256 sera verificado antes da instalacao.'
 printf 'Autorizar download? [s/N]: '
 answer=
 IFS= read -r answer || answer=
 case "$answer" in s|S|sim|SIM) : ;; *) echo 'Download cancelado.'; return 2 ;; esac
 part="$target.part"
 if [ -e "$part" ]; then
  echo "Arquivo temporario existente: $part"
  echo 'Remova-o manualmente antes de tentar novamente.'
  return 1
 fi
 if ! "$CURL_BIN" -fLSs --retry 2 --connect-timeout 20 \
     --proto '=https' --proto-redir '=https' --output "$part" \
     "$MODEL_URL/$filename?download=true"; then
  rm -f "$part"
  echo 'Falha no download HTTPS. Nenhum modelo foi instalado.'
  return 1
 fi
 if ! check_hash "$part" "$expected"; then
  rm -f "$part"
  echo 'SHA-256 NAO CONFERE. Download rejeitado e arquivo temporario excluido.'
  return 1
 fi
 chmod 600 "$part"
 mv "$part" "$target"
 sync
 echo "Instalado e verificado: $target"
}

case "${1:-status}" in
 status)
  if ! storage_ready; then exit 1; fi
  report_file "$WEIGHT" "$WEIGHT_SHA" || :
  report_file "$PROJECTOR" "$PROJECTOR_SHA" || :
  echo 'Motor llama.cpp: ainda nao embarcado.'
  echo 'Use model install para GGUF Q4_K_M e model vision para projetor.'
  ;;
 verify)
  storage_ready || exit 1
  report_file "$WEIGHT" "$WEIGHT_SHA"
  if [ -f "$MODEL_DIR/$PROJECTOR" ]; then report_file "$PROJECTOR" "$PROJECTOR_SHA"; fi
  ;;
 install) get_file "$WEIGHT" "$WEIGHT_SHA" 'aprox. 672 MB' 900000 ;;
 vision) get_file "$PROJECTOR" "$PROJECTOR_SHA" 'aprox. 1,11 GB' 1500000 ;;
 help)
  echo 'model status | model install | model vision | model verify'
  echo 'Instala apenas GGUF oficial no disco ext4 separado, com SHA-256 fixado.'
  echo 'Nao instala nem executa llama-server ainda.'
  ;;
 *)
  echo 'Uso: model status | model install | model vision | model verify'
  exit 2
  ;;
esac
