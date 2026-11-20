#!/bin/sh
# xorriso: two optional ext4 volumes, never format or overwrite any disk.
# XORRISO_DATA: /data (rw) for GGUF weights and notes.
# XORRISO_RUNTIME: /runtime-data (ro) for the llama-server executable.
set -eu
PATH=/bin:/usr/bin:/sbin
DATA_LABEL=XORRISO_DATA
RUNTIME_LABEL=XORRISO_RUNTIME
DATA_DEST=/data
RUNTIME_DEST=/runtime-data

mounted_at() { grep -q " $1 ext4 " /proc/mounts 2>/dev/null; }

load_drivers() {
 for mod in scsi_common scsi_mod sd_mod libata libahci ahci ata_piix virtio virtio_ring virtio_pci_modern_dev virtio_pci_legacy_dev virtio_pci virtio_blk; do
  if [ -f "/lib/xorriso/modules/$mod.ko" ]; then
   insmod "/lib/xorriso/modules/$mod.ko" >/dev/null 2>&1 || :
  fi
 done
}
ensure_device_nodes() {
 for entry in /sys/class/block/*; do
  name=${entry##*/}
  case "$name" in sd[a-z]|vd[a-z]|hd[a-z]|sd[a-z][0-9]*|vd[a-z][0-9]*) : ;; *) continue ;; esac
  [ -b "/dev/$name" ] && continue
  [ -r "$entry/dev" ] || continue
  number=$(cat "$entry/dev")
  major=${number%%:*}
  minor=${number#*:}
  mknod -m 600 "/dev/$name" b "$major" "$minor" 2>/dev/null || :
 done
}
locate_volume() {
 target_label=$1
 ensure_device_nodes
 for dev in /dev/vd[a-z] /dev/sd[a-z] /dev/hd[a-z] /dev/vd[a-z][0-9]* /dev/sd[a-z][0-9]*; do
  [ -b "$dev" ] || continue
  # Direct ext4 on full disk or on a partition. Superblock at 1024 bytes;
  # magic at +56 and volume label at +120. Read exactly label length
  # (12 for XORRISO_DATA, 15 for XORRISO_RUNTIME), not hard-coded 12.
  magic=$(dd if="$dev" bs=1 skip=1080 count=2 2>/dev/null | od -An -tx1 | tr -d '[:space:]')
  [ "$magic" = "53ef" ] || continue
  name=$(dd if="$dev" bs=1 skip=1144 count=${#target_label} 2>/dev/null)
  if [ "$name" = "$target_label" ]; then printf '%s\n' "$dev"; return 0; fi
 done
 return 1
}
attach_data() {
 mounted_at "$DATA_DEST" && return 0
 mkdir -p "$DATA_DEST"
 load_drivers
 dev=$(locate_volume "$DATA_LABEL") || return 2
 mount -t ext4 -o rw,nosuid,nodev,noexec "$dev" "$DATA_DEST" || return 3
 mkdir -p "$DATA_DEST/notes" "$DATA_DEST/models"
 chmod 700 "$DATA_DEST/notes" "$DATA_DEST/models"
 return 0
}
attach_runtime() {
 mounted_at "$RUNTIME_DEST" && return 0
 mkdir -p "$RUNTIME_DEST"
 load_drivers
 dev=$(locate_volume "$RUNTIME_LABEL") || return 2
 # Read only: executing the verified binary still happens from RAM (/run).
 mount -t ext4 -o ro,nosuid,nodev,noexec "$dev" "$RUNTIME_DEST" || return 3
 return 0
}
case "${1:-status}" in
 boot)
  attach_data >/dev/null 2>&1 || :
  attach_runtime >/dev/null 2>&1 || :
  ;;
 mount)
  if attach_data; then
   echo 'Disco de modelos montado em /data (XORRISO_DATA).'
  else
   echo 'Nao foi encontrado o disco de modelos XORRISO_DATA. Nada foi formatado.'
   exit 1
  fi
  if attach_runtime; then
   echo 'Disco de runtime montado em /runtime-data (XORRISO_RUNTIME, somente leitura).'
  else
   echo 'Disco de runtime opcional nao encontrado. Modelos e notas foram preservados.'
  fi
  ;;
 probe)
  load_drivers
  ensure_device_nodes
  echo 'Dispositivos de bloco detectados pelo kernel:'
  cat /proc/partitions 2>/dev/null || :
  for label in "$DATA_LABEL" "$RUNTIME_LABEL"; do
   if dev=$(locate_volume "$label"); then
    echo "$label: $dev"
   else
    echo "$label: nao encontrado"
   fi
  done
  ;;
 status)
  if mounted_at "$DATA_DEST"; then
   echo 'Volume de modelos: /data (rw)'
   df -h "$DATA_DEST"
   echo 'MiniCPM: /data/models'
   echo 'Notas: /data/notes'
  else
   echo 'Sem volume persistente de modelos. Notas continuam na RAM.'
  fi
  if mounted_at "$RUNTIME_DEST"; then
   echo 'Volume do motor: /runtime-data (ro)'
   echo 'llama-server: /runtime-data/runtime/llama-server'
  else
   echo 'Motor em VDI separado: nao montado.'
  fi
  ;;
 *) echo 'Uso: storage status | storage mount | storage probe'; exit 2 ;;
esac
