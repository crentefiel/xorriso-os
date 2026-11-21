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
create_folder() {
 name=$1
 [ "${#name}" -gt 0 ] && [ "${#name}" -le 64 ] || {
  echo 'Nome deve ter de 1 a 64 caracteres.'; return 3;
 }
 # Permit only simple human names; reject traversal, slashes, shell metacharacters.
 # No eval, no sh -c, no interpretation of model text.
 # Validate the ENTIRE string, including line breaks: grep may accept one
 # valid line of a malicious multi-line filename. No control characters.
 case "$name" in
  [A-Za-z0-9]*) : ;;
  *) echo 'Nome deve iniciar com letra ou numero.'; return 3 ;;
 esac
 allowed=$(printf '%s' "$name" | LC_ALL=C tr -cd 'A-Za-z0-9 _-')
 if [ "$allowed" != "$name" ]; then
  echo 'Nome invalido. Use letras sem acentos, numeros, espaco, _ ou -.'
  return 3
 fi
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
 [Cc]rie\ uma\ pasta\ chamada\ *|[Cc]riar\ uma\ pasta\ chamada\ *|[Qq]uero\ criar\ uma\ pasta\ chamada\ *)
  create_folder "${prompt#*chamada }" ;;
 [Cc]rie\ a\ pasta\ *)
  create_folder "${prompt#*pasta }" ;;
 *)
  echo 'Acao nao reconhecida. Tente: Crie uma pasta chamada Meus Projetos'
  echo 'Ou: Liste minhas pastas'
  exit 2 ;;
esac
