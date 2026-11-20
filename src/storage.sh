#!/bin/sh
# xorriso Alpha 0.9: optional ext4 data volume, never formats guest disks.
set -eu
PATH=/bin:/usr/bin:/sbin
LABEL=XORRISO_DATA
DEST=/data
mounted() { grep -q " $DEST ext4 " /proc/mounts 2>/dev/null; }
load_drivers() {
 for mod in scsi_common scsi_mod sd_mod libata libahci ahci ata_piix virtio virtio_ring virtio_pci_modern_dev virtio_pci_legacy_dev virtio_pci virtio_blk; do
  if [ -f "/lib/xorriso/modules/$mod.ko" ]; then
   insmod "/lib/xorriso/modules/$mod.ko" >/dev/null 2>&1 || :
  fi
 done
}
ensure_device_nodes() {
 # devtmpfs generally provides these; create missing nodes from kernel sysfs.
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
 ensure_device_nodes
 for dev in /dev/vd[a-z] /dev/sd[a-z] /dev/hd[a-z] /dev/vd[a-z][0-9]* /dev/sd[a-z][0-9]*; do
  [ -b "$dev" ] || continue
  # ext4 superblock starts at byte 1024: magic offset 56, label offset 120.
  # BusyBox blkid is intentionally not used; it may omit LABEL.
  magic=$(dd if="$dev" bs=1 skip=1080 count=2 2>/dev/null | od -An -tx1 | tr -d '[:space:]')
  [ "$magic" = "53ef" ] || continue
  label=$(dd if="$dev" bs=1 skip=1144 count=12 2>/dev/null)
  if [ "$label" = "$LABEL" ]; then printf '%s\n' "$dev"; return 0; fi
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
   echo "Diagnostico de dispositivos:"
   cat /proc/partitions 2>/dev/null || :
   echo "Identificacoes blkid:"
   blkid 2>/dev/null || :
   exit 1
  fi ;;
 probe)
  load_drivers
  ensure_device_nodes
  echo 'Dispositivos de bloco reconhecidos pelo kernel:'
  cat /proc/partitions 2>/dev/null || :
  echo 'Busca pelo volume ext4 rotulado XORRISO_DATA:'
  if dev=$(locate_volume); then
    echo "Encontrado: $dev"
  else
    echo 'Nao encontrado. Verifique se o VDI esta anexado como DISCO RIGIDO (nao como CD).'
    echo 'Se usar controlador SATA, atualize para a ISO com driver AHCI.'
  fi
  ;;
 status)
  if mounted; then
   echo 'Volume persistente: /data'
   df -h /data
   echo 'Notas persistentes: /data/notes'
   echo 'Arquivos futuros de IA: /data/models'
  else
   echo 'Sem volume persistente. Notas continuam na RAM.'
   echo 'Anexe disco ext4 separado rotulado XORRISO_DATA.'
   echo 'Use storage probe para diagnosticar controladora e disco.'
  fi ;;
 *) echo 'Uso: storage status | storage mount | storage probe'; exit 2 ;;
esac
