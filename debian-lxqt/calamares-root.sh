#!/bin/sh
# Root-only, fixed-purpose Calamares launcher for a transient xorriso Live boot.
# No arbitrary argv, no shell from AI, no disk operations in this script.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
if [ "$#" -ne 0 ] || ! grep -Eq '(^|[[:space:]])boot=live([[:space:]]|$)' /proc/cmdline; then
    echo 'Instalador root: permitido apenas no boot Live, sem argumentos.' >&2
    exit 2
fi
[ "$(id -u)" -eq 0 ] || { echo 'Instalador requer PolicyKit.' >&2; exit 3; }
# Re-check the protected disks *after* elevation so users cannot bypass the
# unprivileged UI wrapper and accidentally select either VDI in Calamares.
labels=$(/usr/bin/lsblk -rno LABEL) || {
    echo 'Falha ao identificar todos os discos: instalador bloqueado.' >&2
    exit 4
}
if printf '%s\n' "$labels" | grep -Eq '^(XORRISO_DATA|XORRISO_RUNTIME)$'; then
    echo 'VDIs protegidos conectados; remova-os antes de instalar no HD.' >&2
    exit 5
fi
test -x /usr/bin/calamares || exit 6
# Calamares itself displays and asks confirmation of all target disk changes.
exec /usr/bin/calamares
