#!/usr/bin/env bash
# CI fixture. It is passed to a disposable QEMU VM, never packaged in the ISO.
set -Eeuo pipefail
exec >/dev/ttyS0 2>&1
trap 'echo "BIOS installation test failed at line $LINENO"' ERR
udevadm settle --timeout=30
test "$(cat /sys/class/block/vda/serial)" = XOS015TARGET
test "$(cat /sys/class/block/vdb/serial)" = XOS015CHECK
test "$(cat /sys/class/block/vdb/ro)" = 1
test -b /dev/vda1
test ! -d /sys/firmware/efi
media=/run/live/medium
test -s "$media/live/filesystem.squashfs"
target=$(mktemp -d /tmp/calamares-root-XXXXXX)
mkfs.ext4 -q -L XOS015TEST /dev/vda1
mount /dev/vda1 "$target"
unsquashfs -no-progress -processors 2 -f -d "$target" "$media/live/filesystem.squashfs"
mount --rbind /dev "$target/dev"
mount --make-rslave "$target/dev"
mount --rbind /sys "$target/sys"
mount --make-rslave "$target/sys"
mount -t proc proc "$target/proc"
uuid=$(blkid -s UUID -o value /dev/vda1)
test -n "$uuid"
printf 'UUID=%s / ext4 defaults 0 1\n' "$uuid" > "$target/etc/fstab"

# Make the disposable disk report its first boot over the QEMU serial port.
# Leave the main /etc/default/grub to the real Debian package and helper.
mkdir -p "$target/etc/default/grub.d"
cat > "$target/etc/default/grub.d/99-xorriso-ci.cfg" <<'GRUB'
GRUB_TIMEOUT=0
GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0,115200n8"
GRUB
helpers=/usr/share/calamares/helpers
"$helpers/calamares-sources-media"
chroot "$target" apt-cache policy grub-pc
DEBIAN_FRONTEND=noninteractive "$helpers/calamares-bootloader-config"
test "$(chroot "$target" dpkg-query -W -f='${Status}' grub-pc)" = 'install ok installed'
test -s "$target/etc/default/grub"
test -x "$target/usr/sbin/update-grub"
chroot "$target" grub-install --target=i386-pc --recheck /dev/vda
# Debian's Calamares sequence regenerates the installed initramfs after GRUB.
kernel=$(uname -r)
test -s "$target/boot/vmlinuz-$kernel"
if test -e "$target/boot/initrd.img-$kernel"; then
    chroot "$target" update-initramfs -u -k "$kernel"
else
    chroot "$target" update-initramfs -c -k "$kernel"
fi
chroot "$target" update-grub
chroot "$target" grub-script-check /boot/grub/grub.cfg
grep -Eq '^[[:space:]]*linux[[:space:]].*vmlinuz' "$target/boot/grub/grub.cfg"
grep -Eq '^[[:space:]]*initrd[[:space:]].*initrd' "$target/boot/grub/grub.cfg"

cat > "$target/etc/systemd/system/xorriso-ci-disk.service" <<'UNIT'
[Unit]
Description=Verify the mounted BIOS test disk
ConditionKernelCommandLine=!boot=live
After=xorriso-install-mode.service
Requires=xorriso-install-mode.service
SuccessAction=poweroff
FailureAction=poweroff
[Service]
Type=oneshot
StandardOutput=tty
TTYPath=/dev/ttyS0
ExecStart=/usr/bin/findmnt --mountpoint / --source LABEL=XOS015TEST
ExecStart=/usr/bin/test ! -e /etc/polkit-1/rules.d/49-xorriso-live-calamares.rules
ExecStart=/bin/echo XORRISO_CI_BOOTED_FROM_EXT4_DISK
UNIT
ln -s ../xorriso-ci-disk.service "$target/etc/systemd/system/multi-user.target.wants/xorriso-ci-disk.service"
sync
echo XORRISO_CI_BIOS_GRUB_INSTALLED
exit 0
