#!/bin/sh
# Host-side smoke test: catalog is informative, never an arbitrary command runner.
set -eu
SCRIPT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/src/command-catalog.sh"
sh -n "$SCRIPT"
sh "$SCRIPT" --list | grep -q 'Comandos executaveis instalados'
sh "$SCRIPT" --list | grep -q 'nao permissao'
sh "$SCRIPT" --help | grep -q 'catalog --list'
if sh "$SCRIPT" --run 'rm -rf /' >/dev/null 2>&1; then
 echo 'FAIL: catalog accepted arbitrary execution' >&2; exit 1
fi
echo 'PASS: command catalog read-only smoke tests'
