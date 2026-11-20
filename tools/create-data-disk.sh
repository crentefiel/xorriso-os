#!/usr/bin/env bash
# Run on Linux HOST. Creates a NEW sparse ext4 raw disk file; never overwrites.
set -euo pipefail
out="${1:-xorriso-data.img}"
size="${2:-6G}"
[[ "$size" =~ ^[1-9][0-9]*[GM]$ ]] || { echo "Tamanho invalido (ex.: 6G)"; exit 2; }
command -v mkfs.ext4 >/dev/null || { echo 'Instale e2fsprogs (mkfs.ext4).'; exit 2; }
if [[ -e "$out" ]]; then echo "Arquivo existe, recusando sobrescrever: $out" >&2; exit 3; fi
truncate -s "$size" "$out"
if ! mkfs.ext4 -F -L XORRISO_DATA "$out"; then rm -f -- "$out"; exit 4; fi
echo "Disco criado: $out ($size, ext4, rotulo XORRISO_DATA)."
echo "Anexe como SEGUNDO disco na VM; nao substitua o disco principal."
echo 'O xorriso nunca formata discos automaticamente.'
