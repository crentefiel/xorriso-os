#!/usr/bin/env bash
# CI fixture. It is passed to a disposable QEMU VM, never packaged in the ISO.
set -Eeuo pipefail
exec >/dev/ttyS1 2>&1
trap 'echo "BIOS installation test failed at line $LINENO"' ERR
set -x
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
"$helpers/calamares-dpkg-unsafe-io"
"$helpers/calamares-sources-media"
chroot "$target" apt-cache policy grub-pc
DEBIAN_FRONTEND=noninteractive "$helpers/calamares-bootloader-config"
test "$(chroot "$target" dpkg-query -W -f='${Status}' grub-pc)" = 'install ok installed'
test -s "$target/etc/default/grub"
test -x "$target/usr/sbin/update-grub"
chroot "$target" grub-install --target=i386-pc --recheck /dev/vda
# Run the shipped Calamares packages job and the Debian stages that follow it.
/usr/local/sbin/xorriso-ci-calamares "$target"
kernel=$(uname -r)
test -s "$target/boot/vmlinuz-$kernel"
test -s "$target/boot/initrd.img-$kernel"
chroot "$target" update-grub
chroot "$target" grub-script-check /boot/grub/grub.cfg
grep -Eq '^[[:space:]]*linux[[:space:]].*vmlinuz' "$target/boot/grub/grub.cfg"
grep -Eq '^[[:space:]]*initrd[[:space:]].*initrd' "$target/boot/grub/grub.cfg"

cat > /run/xorriso-ci-chat.py <<'PY'
import json
import sys
import time
from pathlib import Path
from urllib.request import Request, urlopen

mode = sys.argv[1]
assert {p.name for p in Path("/sys/class/net").iterdir()} == {"lo"}
model = "LFM2.5-350M"
base = "http://127.0.0.1:8080/v1/"
deadline = time.monotonic() + 240
while True:
    try:
        with urlopen(base + "models", timeout=5) as reply:
            models = json.load(reply)["data"]
        if any(item.get("id") == model for item in models):
            break
    except (OSError, ValueError):
        pass
    if time.monotonic() >= deadline:
        sys.exit("O modelo local não ficou pronto")
    time.sleep(2)
status = json.loads(Path("/var/lib/xorriso-model/status.json").read_text())
assert status["source"] == "bundled_iso"
prompt = {"model": model, "messages": [{"role": "user", "content": "Diga oi em português."}],
          "max_tokens": 24, "temperature": 0, "stream": False}
req = Request(base + "chat/completions", data=json.dumps(prompt).encode(),
              headers={"Content-Type": "application/json"})
with urlopen(req, timeout=180) as reply:
    result = json.load(reply)
answer = result["choices"][0]["message"]["content"].strip()
assert answer and result["usage"]["completion_tokens"] > 0
print("XORRISO_CI_OFFLINE_CHAT_" + mode + " " + json.dumps(answer, ensure_ascii=True), flush=True)
PY
systemctl start --no-block xorriso-model.service
python3 /run/xorriso-ci-chat.py LIVE || {
    journalctl -b -u xorriso-model-provision -u xorriso-model -n 60 --no-pager
    exit 1
}
install -m 0644 /run/xorriso-ci-chat.py "$target/usr/local/libexec/xorriso-ci-chat.py"
cat > "$target/etc/systemd/system/xorriso-ci-disk.service" <<'UNIT'
[Unit]
Description=Verify the mounted BIOS test disk
ConditionKernelCommandLine=!boot=live
After=xorriso-install-mode.service xorriso-model.service
Requires=xorriso-install-mode.service xorriso-model.service
SuccessAction=poweroff
FailureAction=poweroff
[Service]
Type=oneshot
TimeoutStartSec=8min
StandardOutput=tty
StandardError=inherit
TTYPath=/dev/ttyS1
ExecStart=/usr/bin/findmnt --mountpoint / --source LABEL=XOS015TEST
ExecStart=/usr/bin/test ! -e /etc/polkit-1/rules.d/49-xorriso-live-calamares.rules
ExecStart=/usr/bin/python3 /usr/local/libexec/xorriso-ci-chat.py DISK
ExecStart=/bin/echo XORRISO_CI_BOOTED_FROM_EXT4_DISK
UNIT
ln -s ../xorriso-ci-disk.service "$target/etc/systemd/system/multi-user.target.wants/xorriso-ci-disk.service"
sync
echo XORRISO_CI_BIOS_GRUB_INSTALLED
exit 0
