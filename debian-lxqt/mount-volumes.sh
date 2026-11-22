#!/bin/sh
# Mount the user's two existing ext4 VDI volumes read-only, without journal replay.
# NEVER run mkfs, fsck -y or any partitioning command.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
mount_one() {
 label=$1
 dest=$2
 device=$(blkid -L "$label" 2>/dev/null || :)
 [ -n "$device" ] && [ -b "$device" ] || {
  echo "$label nao conectado; IA local pode ficar indisponivel. Nada sera criado ou formatado." >&2
  return 0
 }
 current=$(findmnt -rn -o SOURCE --mountpoint "$dest" 2>/dev/null || :)
 if [ -n "$current" ]; then
  echo "$dest ja montado: $current"
  return 0
 fi
 mkdir -p "$dest"
 # noload prevents replaying ext4 journal even for ostensibly read-only mounts.
 mount -t ext4 -o ro,noload,nosuid,nodev,noexec "$device" "$dest"
 echo "$label montado somente para leitura em $dest"
}
mount_one XORRISO_DATA /data
mount_one XORRISO_RUNTIME /runtime-data
