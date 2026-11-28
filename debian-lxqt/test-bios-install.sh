#!/usr/bin/env bash
# Run only against a new sparse file. No host block device or network is attached.
set -euo pipefail
iso=$(realpath "${1:?usage: test-bios-install.sh IMAGE.iso}")
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
logs="${XORRISO_BOOT_DIAGNOSTICS_DIR:-$(dirname "$iso")/boot-diagnostics}"
mkdir -p "$logs"
disk="$tmp/target.raw"
truncate -s 8G "$disk"
printf 'label: dos\n\nstart=2048, type=83, bootable\n' | sfdisk "$disk"

# The release ISO stays read-only. For this one boot, append an initramfs
# hook that enables a test service in the Live session's volatile overlay.
xorriso -osirrox on -indev "$iso" -extract /live/vmlinuz "$tmp/vmlinuz" \
    -extract /live/initrd.img "$tmp/initrd.img" -end
payload="$tmp/payload"
mkdir -p "$payload/scripts/init-bottom"
install -m 0755 "$here/test-calamares-cleanup.sh" "$payload/xorriso-ci-calamares"
sudo unmkinitramfs "$tmp/initrd.img" "$tmp/unpacked"
order=$(sudo find "$tmp/unpacked" -type f -path '*/scripts/init-bottom/ORDER' -print -quit)
test -n "$order"
sudo cat "$order" > "$payload/scripts/init-bottom/ORDER"
sudo rm -r -- "$tmp/unpacked"
printf '\n/scripts/init-bottom/xorriso-ci "$@"\n' >> "$payload/scripts/init-bottom/ORDER"
cat > "$payload/scripts/init-bottom/xorriso-ci" <<'HOOK'
#!/bin/sh
case "${1:-}" in prereqs) exit 0 ;; esac
set -eu
units="${rootmnt:-/root}/etc/systemd/system"
test -x "${rootmnt:-/root}/bin/bash"
cp /xorriso-ci-calamares "${rootmnt:-/root}/usr/local/sbin/xorriso-ci-calamares"
mkdir -p "$units/multi-user.target.wants"
cat > "$units/xorriso-ci-installer.service" <<'UNIT'
[Unit]
Description=Run the disposable BIOS installation test
ConditionKernelCommandLine=xorriso_ci_bios=1
After=dev-vdb.device local-fs.target
Requires=dev-vdb.device
SuccessAction=poweroff
FailureAction=poweroff
[Service]
Type=oneshot
ExecStart=/bin/bash /dev/vdb
TimeoutStartSec=29min
StandardOutput=journal+console
UNIT
ln -sf ../xorriso-ci-installer.service "$units/multi-user.target.wants/xorriso-ci-installer.service"
echo XORRISO_CI_TEST_UNIT_ENABLED >/dev/ttyS0
HOOK
chmod 755 "$payload/scripts/init-bottom/xorriso-ci"
install -m 0600 "$tmp/initrd.img" "$tmp/ci-initrd.img"
truncate -s %4 "$tmp/ci-initrd.img"
(cd "$payload" && find . -print0 | cpio --null -o -H newc) >> "$tmp/ci-initrd.img"
cp "$here/test-bios-guest.sh" "$tmp/check.raw"
printf '%*s' "$(( (512 - $(stat -c %s "$tmp/check.raw") % 512) % 512 ))" '' >> "$tmp/check.raw"

vm=(qemu-system-x86_64 -machine accel=kvm:tcg -m 4096 -smp 2 -display none
    -monitor none -no-reboot -nic none
    -drive "if=none,id=target,file=$disk,format=raw"
    -device virtio-blk-pci,drive=target,serial=XOS015TARGET)
run_vm() {
    local phase=$1 limit=$2 marker=$3
    shift 3
    local log="$logs/$phase.log" guest="$logs/$phase-guest.log"
    if ! timeout --kill-after=10s "$limit" "${vm[@]}" \
        -serial "file:$log" -serial "file:$guest" "$@" ||
       ! grep -Eq "^${marker}[[:space:]]*$" "$guest"; then
        tail -n 30 "$log" >&2
        tail -n 100 "$guest" >&2
        return 1
    fi
    echo "PASS: $marker"
}

run_vm bios-install 30m XORRISO_CI_BIOS_GRUB_INSTALLED \
    -cdrom "$iso" -kernel "$tmp/vmlinuz" -initrd "$tmp/ci-initrd.img" \
    -drive "if=none,id=check,file=$tmp/check.raw,format=raw,readonly=on" \
    -device virtio-blk-pci,drive=check,serial=XOS015CHECK \
    -append 'boot=live components live-config.nocomponents=sudo username=xorriso console=ttyS0,115200n8 systemd.mask=serial-getty@ttyS0.service xorriso_ci_bios=1 panic=5'
# This time SeaBIOS gets only the installed disk. No kernel, ISO or test
# input device is supplied by the host.
run_vm bios-disk-boot 14m XORRISO_CI_BOOTED_FROM_EXT4_DISK -boot c
grep -E '^XORRISO_CI_CALAMARES_PACKAGES_AND_INITRAMFS_OK[[:space:]]*$' "$logs/bios-install-guest.log"
grep -F 'XORRISO_CI_OFFLINE_CHAT_LIVE ' "$logs/bios-install-guest.log"
grep -F 'XORRISO_CI_OFFLINE_CHAT_DISK ' "$logs/bios-disk-boot-guest.log"
