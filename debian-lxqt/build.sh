#!/usr/bin/env bash
# Build a separate Debian LXQt live ISO. Never writes to attached VDI disks.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${XORRISO_LIVE_WORKDIR:-$ROOT/work}"
mkdir -p "$OUT"
cd "$OUT"
for cmd in lb xorriso; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd. On Debian/Ubuntu install live-build and xorriso." >&2; exit 2; }
done
if [[ -e config ]]; then
  echo "Existing live-build configuration in $OUT; refusing to overwrite." >&2
  exit 3
fi
lb config --mode debian --distribution trixie --architectures amd64 \
  --binary-images iso-hybrid --debian-installer none \
  --archive-areas "main" --security false --bootappend-live "boot=live components quiet"
mkdir -p config/package-lists config/includes.chroot/etc/sddm.conf.d \
  config/hooks/normal config/includes.chroot/usr/local/share/xorriso
mkdir -p config/archives
# live-build on Ubuntu 24.04 uses an obsolete trixie/updates URL. Override safely.
# Debian 13 security suite is trixie-security under /debian-security.
printf '%s\n' 'deb http://security.debian.org/debian-security trixie-security main' > config/archives/debian-security.list.chroot
cp "$ROOT/package-list.chroot" config/package-lists/xorriso.list.chroot
cp "$ROOT/10-xorriso-autologin.conf" config/includes.chroot/etc/sddm.conf.d/10-xorriso-autologin.conf
cp "$ROOT/020-xorriso-user.hook.chroot" config/hooks/normal/020-xorriso-user.hook.chroot
cp "$ROOT/README.md" config/includes.chroot/usr/local/share/xorriso/MIGRATION.md
mkdir -p config/includes.chroot/usr/local/bin
install -m 755 "$ROOT/xorriso-ui.py" config/includes.chroot/usr/local/bin/xorriso-ui.py
install -m 755 "$ROOT/xorriso-agent.py" config/includes.chroot/usr/local/bin/xorriso-agent.py
mkdir -p config/includes.chroot/usr/local/libexec/xorriso config/includes.chroot/etc/systemd/system
install -m 755 "$ROOT/admin-package.py" config/includes.chroot/usr/local/libexec/xorriso/admin-package
install -m 755 "$ROOT/mount-volumes.sh" config/includes.chroot/usr/local/libexec/xorriso/mount-volumes.sh
install -m 755 "$ROOT/start-model.sh" config/includes.chroot/usr/local/libexec/xorriso/start-model.sh
install -m 644 "$ROOT/xorriso-volumes.service" config/includes.chroot/etc/systemd/system/xorriso-volumes.service
install -m 644 "$ROOT/xorriso-model.service" config/includes.chroot/etc/systemd/system/xorriso-model.service
chmod +x config/hooks/normal/020-xorriso-user.hook.chroot
echo "Building Debian LXQt live ISO in $OUT"
sudo lb build
echo "Check $OUT for live-image-amd64.hybrid.iso; boot-test before distribution."
