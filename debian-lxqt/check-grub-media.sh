#!/bin/sh
# Check the APT index and the actual package files used by Calamares.
set -eu
medium=${1:?missing Live medium}
shift
test "$#" -gt 0 || exit 2
index="$medium/dists/trixie/main/binary-amd64/Packages"
if ! test -s "$index"; then
    echo "Instalador: índice de pacotes ausente na mídia: $index" >&2
    exit 1
fi
for package do
    archive=$(awk -v name="$package" '
        /^Package: / { selected = ($2 == name) }
        selected && /^Filename: / { print $2; exit }
    ' "$index")
    case "$archive" in
        pool/*) test -s "$medium/$archive" && continue ;;
    esac
    echo "Instalador: a mídia não fornece o pacote necessário $package." >&2
    exit 1
done
