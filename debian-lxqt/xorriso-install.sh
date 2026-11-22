#!/bin/sh
# Launch Debian 13's graphical installer from a Live session only.
# No partitioning, formatting, mounting or disk selection in this wrapper.
set -eu
if ! grep -Eq '(^|[[:space:]])boot=live([[:space:]]|$)' /proc/cmdline; then
    echo 'Instalador disponivel somente na sessao Live da ISO xorriso.' >&2
    exit 2
fi
if [ -z "$(printenv DISPLAY || true)" ]; then
    echo 'O instalador precisa da sessao grafica Live.' >&2
    exit 3
fi
# Refuse launch if either protected VDI label is visible.
if lsblk -rno LABEL 2>/dev/null | grep -Eq '^(XORRISO_DATA|XORRISO_RUNTIME)$'; then
    echo 'Disco protegido conectado. Desconecte XORRISO_DATA e XORRISO_RUNTIME antes da instalacao.' >&2
    exit 4
fi
if [ ! -x /usr/bin/calamares ] || [ ! -x /usr/bin/pkexec ]; then
    echo 'Calamares ou PolicyKit indisponivel.' >&2
    exit 5
fi
# The scoped live-only polkit rule still requests user authentication.
# No unrestricted root shell and no command strings from the model.
xhost +si:localuser:root >/dev/null
trap 'xhost -si:localuser:root >/dev/null 2>&1 || true' EXIT HUP INT TERM
/usr/bin/pkexec /usr/bin/calamares
