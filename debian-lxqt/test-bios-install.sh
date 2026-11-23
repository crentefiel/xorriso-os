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

# Boot the kernel and initramfs from the exact ISO. The read-only second
# virtio disk supplies a CI command for this boot only, outside the product.
xorriso -osirrox on -indev "$iso" -extract /live "$tmp/live" -end
mapfile -t kernels < <(find "$tmp/live" -maxdepth 1 -type f -name 'vmlinuz*')
mapfile -t initrds < <(find "$tmp/live" -maxdepth 1 -type f -name 'initrd*')
if (( ${#kernels[@]} != 1 || ${#initrds[@]} != 1 )); then
    echo "Expected one Live kernel and one initramfs in the ISO." >&2
    exit 1
fi
cp "$here/test-bios-guest.sh" "$tmp/check.raw"
printf '%*s' "$(( (512 - $(stat -c %s "$tmp/check.raw") % 512) % 512 ))" '' >> "$tmp/check.raw"

vm=(qemu-system-x86_64 -machine accel=kvm:tcg -m 3072 -smp 2 -display none
    -monitor none -no-reboot -nic none
    -drive "if=none,id=target,file=$disk,format=raw"
    -device virtio-blk-pci,drive=target,serial=XOS015TARGET)
run_vm() {
    local phase=$1 limit=$2 marker=$3
    shift 3
    local log="$logs/$phase.log"
    if ! timeout --kill-after=10s "$limit" "${vm[@]}" -serial "file:$log" "$@" ||
       ! grep -Fq "$marker" "$log"; then
        tail -n 100 "$log" >&2
        return 1
    fi
    echo "PASS: $marker"
}

run_vm bios-install 23m XORRISO_CI_BIOS_GRUB_INSTALLED \
    -cdrom "$iso" -kernel "${kernels[0]}" -initrd "${initrds[0]}" \
    -drive "if=none,id=check,file=$tmp/check.raw,format=raw,readonly=on" \
    -device virtio-blk-pci,drive=check,serial=XOS015CHECK \
    -append 'boot=live console=ttyS0,115200n8 systemd.run="/bin/bash /dev/vdb" systemd.run_success_action=poweroff systemd.run_failure_action=poweroff panic=5'
# This time SeaBIOS gets only the installed disk. No kernel, ISO or test
# input device is supplied by the host.
run_vm bios-disk-boot 14m XORRISO_CI_BOOTED_FROM_EXT4_DISK -boot c
grep -F 'XORRISO_CI_OFFLINE_CHAT_LIVE ' "$logs/bios-install.log"
grep -F 'XORRISO_CI_OFFLINE_CHAT_DISK ' "$logs/bios-disk-boot.log"
