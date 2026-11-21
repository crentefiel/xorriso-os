#!/usr/bin/env bash
# xorriso: create a BIOS GRUB ISO from a distribution kernel and project sources.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$HERE/dist"; WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/rootfs"; STAGE="$WORK/iso"
mkdir -p "$DIST" "$ROOT" "$STAGE/boot/grub"
for tool in gcc busybox curl jq cpio gzip grub-mkrescue xorriso; do
  command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 2; }
done
KERNEL="$(find /boot -maxdepth 1 -type f -name 'vmlinuz-*-generic' | sort -V | tail -n 1)"
[[ -n "$KERNEL" && -f "$KERNEL" ]] || { echo 'Install linux-image-generic.' >&2; exit 3; }
VERSION="${KERNEL##*/vmlinuz-}"
echo "Building with kernel $VERSION"
install -d "$ROOT"/{bin,dev,etc/ssl/certs,lib,lib64,proc,sys,run,tmp,usr/bin,usr/lib/xorriso,lib/xorriso/modules,data,runtime-data}
chmod 1777 "$ROOT/tmp"
gcc -std=gnu11 -Os -static -s -Wall -Wextra -o "$ROOT/init" "$HERE/src/xorriso-init.c"
install -m 755 "$(command -v busybox)" "$ROOT/bin/busybox"
for app in sh ash ls cat mount dmesg uname ip ps free vi grep mkdir touch echo date route ifconfig udhcpc insmod ping awk sed sleep head tail rm chmod printf clear readlink basename blkid df sync dd od tr mknod sha256sum mv wc cp kill; do
  ln -sf busybox "$ROOT/bin/$app"
done
for file in ai-request.sh ai-agent.sh local.sh network.sh storage.sh model.sh runtime.sh loopback.sh ai-boot.sh actions.sh command-catalog.sh; do
  install -m 755 "$HERE/src/$file" "$ROOT/usr/lib/xorriso/$file"
done
install -m 755 "$HERE/src/udhcpc.script" "$ROOT/etc/udhcpc.script"
install -m 644 /etc/ssl/certs/ca-certificates.crt "$ROOT/etc/ssl/certs/ca-certificates.crt"
printf 'hosts: files dns\n' > "$ROOT/etc/nsswitch.conf"
printf '127.0.0.1 localhost\n::1 localhost\n' > "$ROOT/etc/hosts"
: > "$ROOT/etc/resolv.conf"
for binary in "$(command -v curl)" "$(command -v jq)"; do
  install -m 755 "$binary" "$ROOT/usr/bin/$(basename "$binary")"
  while IFS= read -r path; do
    if [[ -f "$path" ]]; then
      install -d "$ROOT$(dirname "$path")"
      cp -L "$path" "$ROOT$path"
    fi
  done < <(ldd "$binary" | awk '{for(i=1;i<=NF;i++) if($i ~ /^\//) print $i}' | sort -u)
done
for lib in /lib/x86_64-linux-gnu/libnss_dns.so.2 /lib/x86_64-linux-gnu/libnss_files.so.2; do
  [[ -f "$lib" ]] || continue
  install -d "$ROOT$(dirname "$lib")"; cp -L "$lib" "$ROOT$lib"
done
MODULEDIR="/lib/modules/$VERSION"
for mod in mii net_failover e1000 pcnet32 8139too virtio_net virtio virtio_ring virtio_pci_modern_dev virtio_pci_legacy_dev virtio_pci virtio_blk scsi_common scsi_mod sd_mod libata libahci ahci ata_piix; do
  path="$(find "$MODULEDIR/kernel" -type f \( -name "$mod.ko" -o -name "$mod.ko.xz" -o -name "$mod.ko.zst" \) -print -quit 2>/dev/null || :)"
  [[ -n "$path" ]] || { echo "Module $mod unavailable"; continue; }
  case "$path" in
    *.zst) zstd -dc "$path" > "$ROOT/lib/xorriso/modules/$mod.ko";;
    *.xz) xz -dc "$path" > "$ROOT/lib/xorriso/modules/$mod.ko";;
    *) cp "$path" "$ROOT/lib/xorriso/modules/$mod.ko";;
  esac
done
sudo mknod -m 600 "$ROOT/dev/console" c 5 1
sudo mknod -m 666 "$ROOT/dev/null" c 1 3
for dev in 'tty0 4 0' 'tty 5 0' 'zero 1 5' 'random 1 8' 'urandom 1 9'; do
  read -r name major minor <<< "$dev"
  sudo mknod -m 666 "$ROOT/dev/$name" c "$major" "$minor"
done
(cd "$ROOT"; find . -print0 | sort -z | cpio --null -o -H newc --quiet | gzip -9 > "$DIST/initramfs.cpio.gz")
sudo cp "$KERNEL" "$STAGE/boot/vmlinuz"
sudo chown "$(id -u):$(id -g)" "$STAGE/boot/vmlinuz"
cp "$DIST/initramfs.cpio.gz" "$STAGE/boot/initramfs.cpio.gz"
cat > "$STAGE/boot/grub/grub.cfg" <<'GRUB'
set timeout=0
set timeout_style=hidden
set default=0
menuentry 'xorriso Alpha 0.15 - Linux minimo' {
 linux /boot/vmlinuz console=tty0 quiet loglevel=0 vt.global_cursor_default=0 rdinit=/init
 initrd /boot/initramfs.cpio.gz
}
GRUB
grub-mkrescue -o "$DIST/xorriso-alpha-015-grub.iso" "$STAGE"
sudo cp "$KERNEL" "$DIST/vmlinuz"
sudo chown "$(id -u):$(id -g)" "$DIST/vmlinuz"
sha256sum "$DIST/xorriso-alpha-015-grub.iso" > "$DIST/SHA256SUMS"
echo "Created $DIST/xorriso-alpha-015-grub.iso"
