#!/bin/sh
# Calamares invokes this on the Live system, before and after using its APT media.
set -eu
target=$(findmnt -rn -t proc -o TARGET | sed -n 's#^\(.*/calamares-root-[^/]*\)/proc$#\1#p')
if [ -z "$target" ] || [ ! -d "$target/etc/apt/sources.list.d" ] || ! mountpoint -q -- "$target"; then
    echo 'Calamares could not identify one mounted installation root' >&2
    exit 1
fi
medium=
for path in /run/live/medium /run/initramfs/live; do
    if mountpoint -q -- "$path"; then
        medium=$path
        break
    fi
done
if [ -z "$medium" ]; then
    echo 'Calamares could not find the mounted Debian Live medium' >&2
    exit 1
fi

list="$target/etc/apt/sources.list.d/debian-live-media.list"
bound="$target$medium"
case "${1:-}" in
    -u)
        if mountpoint -q -- "$bound"; then
            umount -- "$bound"
        fi
        rm -f -- "$list"
        rmdir -- "$bound" 2>/dev/null || :
        rmdir -- "${bound%/*}" 2>/dev/null || :
        ;;
    '')
        rm -f -- "$target/etc/apt/sources.list.d/base.list"
        mkdir -p -- "$bound"
        if ! mountpoint -q -- "$bound"; then
            mount --bind "$medium" "$bound"
        fi
        printf 'deb [trusted=yes] file:%s trixie main\n' "$medium" > "$list"
        ;;
    *)
        echo 'Unexpected Calamares media action' >&2
        exit 1
        ;;
esac
chroot "$target" apt-get update
