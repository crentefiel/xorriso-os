#!/bin/sh
# xorriso Alpha 0.9: optional ext4 data volume, never formats guest disks.
set -eu
PATH=/bin:/usr/bin:/sbin
LABEL=XORRISO_DATA
DEST=/data
mounted() { grep -q " $DEST ext4 " /proc/mounts 2>/dev/null; }
load_drivers() {
 for mod in virtio virtio_ring virtio_pci_modern_dev virtio_pci_legacy_dev virtio_pci virtio_blk; do
  if [ -f "/lib/xorriso/modules/$mod.ko" ]; then
   insmod "/lib/xorriso/modules/$mod.ko" >/dev/null 2>&1 || :
  fi
 done
}
locate_volume() {
 for dev in /dev/vd[a-z] /dev/sd[a-z] /dev/hd[a-z] /dev/vd[a-z][0-9]* /dev/sd[a-z][0-9]*; do
  [ -b "$dev" ] || continue
  # BusyBox blkid does not support the util-linux -s/-o flags.
  metadata=$(blkid "$dev" 2>/dev/null || :)
  case "$metadata" in
   *'LABEL="XORRISO_DATA"'*) printf '%s\n' "$dev"; return 0 ;;
  esac
 done
 return 1
}
attach() {
 if mounted; then return 0; fi
 mkdir -p "$DEST"
 load_drivers
 dev=$(locate_volume) || return 2
 mount -t ext4 -o rw,nosuid,nodev,noexec "$dev" "$DEST" || return 3
 mkdir -p "$DEST/notes" "$DEST/models"
 chmod 700 "$DEST/notes" "$DEST/models"
 return 0
}
case "${1:-status}" in
 boot) attach >/dev/null 2>&1 || : ;;
 mount)
  if attach; then
   echo "Dados persistentes montados em /data (rotulo $LABEL)."
  else
   echo "Disco ext4 $LABEL nao encontrado. Nenhum disco foi formatado."
   exit 1
  fi ;;
 status)
  if mounted; then
   echo 'Volume persistente: /data'
   df -h /data
   echo 'Notas persistentes: /data/notes'
   echo 'Arquivos futuros de IA: /data/models'
  else
   echo 'Sem volume persistente. Notas continuam na RAM.'
   echo 'Anexe disco ext4 separado rotulado XORRISO_DATA.'
  fi ;;
 *) echo 'Uso: storage status | storage mount'; exit 2 ;;
esac
