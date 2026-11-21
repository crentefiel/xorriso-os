#!/bin/sh
# xorriso: first real, auditable system actions.
# Executes as PID1's privileged helper, but never runs arbitrary text as shell.
set -eu
PATH=/bin:/usr/bin:/sbin
umask 077
ROOT=/data/Documentos

# CI-only override, not a security boundary (single-user root prototype).
if [ -n "${XORRISO_ACTION_TEST_ROOT:-}" ]; then
 ROOT=$XORRISO_ACTION_TEST_ROOT
else
 grep -q ' /data ext4 ' /proc/mounts 2>/dev/null || {
  echo 'Disco de dados nao montado. Use storage status.'
  exit 2
 }
fi
ensure_root() {
 [ ! -L "$ROOT" ] || { echo 'Pasta principal nao confiavel (link).'; return 3; }
 if [ ! -d "$ROOT" ]; then
  mkdir -m 700 "$ROOT" || return 3
 fi
 [ -d "$ROOT" ] && [ ! -L "$ROOT" ] || return 3
}
# A folder name is DATA, not a shell command. Unicode UTF-8 bytes are allowed
# so Brazilian Portuguese names work. Reject paths, controls and shell punctuation.
valid_name() {
 name=$1
 [ -n "$name" ] && [ "${#name}" -le 120 ] || {
  echo 'Nome deve ter de 1 a 120 bytes.'; return 3;
 }
 case "$name" in
  .*|*/*) echo 'Use apenas o nome da pasta, sem caminho nem nome oculto.'; return 3 ;;
 esac
 # od+awk validate every byte, not only the first line. UTF-8 bytes >= 128
 # are accepted as data; the model result is never interpreted by a shell.
 if ! printf '%s' "$name" | od -An -tu1 | awk '
  { for (i=1; i<=NF; i++) {
    b=$i+0
    if (!(b>=128 || (b>=48&&b<=57) || (b>=65&&b<=90) ||
          (b>=97&&b<=122) || b==32 || b==45 || b==46 || b==95))
      bad=1
  }}
  END { exit bad ? 1 : 0 }
 '; then
  echo 'Nome invalido. Use letras, acentos, numeros, espaco, ponto, _ ou -.'
  return 3
 fi
}
create_folder() {
 name=$1
 valid_name "$name" || return 3
 ensure_root || return 3
 target="$ROOT/$name"
 if [ -L "$target" ]; then echo 'Link simbolico nao permitido.'; return 3; fi
 if [ -e "$target" ]; then
  [ -d "$target" ] && { echo "A pasta ja existe: $target"; return 0; }
  echo 'Um arquivo ja usa esse nome.'; return 3
 fi
 if mkdir -m 700 "$target" && [ -d "$target" ] && [ ! -L "$target" ]; then
  echo "Pasta criada e verificada: $target"
 else
  echo 'Nao foi possivel criar a pasta.'
  return 3
 fi
}
check_folder() {
 name=$1
 valid_name "$name" || return 3
 ensure_root || return 3
 if [ -d "$ROOT/$name" ] && [ ! -L "$ROOT/$name" ]; then
  echo "Pasta existe e foi verificada: $ROOT/$name"
 else
  echo "Pasta nao encontrada: $ROOT/$name"
  return 1
 fi
}
list_folders() {
 ensure_root || return 3
 echo "Pastas em $ROOT:"
 # List only real directories, never ordinary files or symbolic links.
 for entry in "$ROOT"/*; do
  [ -d "$entry" ] && [ ! -L "$entry" ] || continue
  printf '%s\n' "${entry##*/}"
 done
}
prompt=${1:-}
case "$prompt" in
 --list|[Ll]iste\ minhas\ pastas*|[Mm]ostre\ minhas\ pastas*)
  list_folders ;;
 --create:*)
  create_folder "${prompt#--create:}" ;;
 --check:*)
  check_folder "${prompt#--check:}" ;;
 [Cc]rie\ uma\ pasta\ chamada\ *|[Cc]riar\ uma\ pasta\ chamada\ *|[Qq]uero\ criar\ uma\ pasta\ chamada\ *)
  create_folder "${prompt#*chamada }" ;;
 [Cc]rie\ a\ pasta\ *)
  create_folder "${prompt#*pasta }" ;;
 *)
  echo 'Acao nao reconhecida. Tente: Crie uma pasta chamada Meus Projetos'
  echo 'Ou: Liste minhas pastas'
  exit 2 ;;
esac
