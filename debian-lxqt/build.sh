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
  --binary-images iso-hybrid --debian-installer false --initsystem systemd \
  --archive-areas "main" --apt-indices false --security false --bootappend-live "boot=live components quiet"
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
# Old live-build invokes 'rsvg' inside the Debian chroot during ISO boot graphics
# generation. Debian 13 ships 'rsvg-convert' only; include a compatible argv wrapper.
mkdir -p config/includes.chroot/usr/bin
cat > config/includes.chroot/usr/bin/rsvg <<'RSVG'
#!/bin/sh
exec /usr/bin/rsvg-convert "$@"
RSVG
chmod 755 config/includes.chroot/usr/bin/rsvg
install -m 755 "$ROOT/xorriso-ui.py" config/includes.chroot/usr/local/bin/xorriso-ui.py
install -m 755 "$ROOT/xorriso-agent.py" config/includes.chroot/usr/local/bin/xorriso-agent.py
mkdir -p config/includes.chroot/usr/local/libexec/xorriso config/includes.chroot/etc/systemd/system
install -m 755 "$ROOT/admin-package.py" config/includes.chroot/usr/local/libexec/xorriso/admin-package
install -m 755 "$ROOT/mount-volumes.sh" config/includes.chroot/usr/local/libexec/xorriso/mount-volumes.sh
install -m 755 "$ROOT/start-model.sh" config/includes.chroot/usr/local/libexec/xorriso/start-model.sh
install -m 644 "$ROOT/xorriso-volumes.service" config/includes.chroot/etc/systemd/system/xorriso-volumes.service
install -m 644 "$ROOT/xorriso-model.service" config/includes.chroot/etc/systemd/system/xorriso-model.service
chmod +x config/hooks/normal/020-xorriso-user.hook.chroot
# Ubuntu 24.04 live-build ships old Syslinux symlinks incompatible with Debian 13 paths.
# Ship ordinary, matched Ubuntu Syslinux v6 BIOS files in a local bootloader template.
# The Debian guest remains the full target OS; these are only BIOS ISO boot records.
BOOT_TEMPLATE=/usr/share/live/build/bootloaders/isolinux
mkdir -p config/bootloaders
test -d "$BOOT_TEMPLATE"
cp -a "$BOOT_TEMPLATE" config/bootloaders/isolinux
for item in \
  "isolinux.bin:/usr/lib/ISOLINUX/isolinux.bin" \
  "vesamenu.c32:/usr/lib/syslinux/modules/bios/vesamenu.c32" \
  "ldlinux.c32:/usr/lib/syslinux/modules/bios/ldlinux.c32" \
  "libcom32.c32:/usr/lib/syslinux/modules/bios/libcom32.c32" \
  "libutil.c32:/usr/lib/syslinux/modules/bios/libutil.c32"; do
  name=${item%%:*}
  source=${item#*:}
  test -s "$source" || { echo "Missing host Syslinux BIOS asset: $source" >&2; exit 4; }
  rm -f "config/bootloaders/isolinux/$name"
  cp "$source" "config/bootloaders/isolinux/$name"
done
test -s config/bootloaders/isolinux/isolinux.bin
test -s config/bootloaders/isolinux/vesamenu.c32
# Debian 13 librsvg2-bin supplies rsvg-convert, not the removed 'rsvg' alias
# still invoked by Ubuntu's older live-build bootloader graphics template.
# A local wrapper preserves the old command name without modifying Debian.
# This build executes on an isolated CI runner; create a temporary host alias.
# It is removed on exit and never copied into the ISO.
if ! command -v rsvg >/dev/null 2>&1; then
  sudo ln -s /usr/bin/rsvg-convert /usr/local/bin/rsvg
  trap 'sudo rm -f /usr/local/bin/rsvg' EXIT
fi
echo "Building Debian LXQt live ISO in $OUT"
sudo lb build
echo "Check $OUT for live-image-amd64.hybrid.iso; boot-test before distribution."
