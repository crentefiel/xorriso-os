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
if [ ! -x /usr/bin/calamares ] || [ ! -x /usr/bin/pkexec ] ||
   [ ! -x /usr/local/libexec/xorriso/calamares-root ]; then
    echo 'Calamares ou PolicyKit indisponivel.' >&2
    exit 5
fi
# The specific PolicyKit rule grants the ephemeral Live user permission for
# ONE fixed root-owned installer wrapper. No reusable root password or
# privileged shell is created, and the wrapper rechecks protected VDI labels.
xhost +si:localuser:root >/dev/null
trap 'xhost -si:localuser:root >/dev/null 2>&1 || true' EXIT HUP INT TERM
/usr/bin/pkexec /usr/local/libexec/xorriso/calamares-root
