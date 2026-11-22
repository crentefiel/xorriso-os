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
  --archive-areas "main" --apt-indices false --security false --bootappend-live "boot=live components console=ttyS0,115200n8 console=tty0"
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
# Legacy live-build 3.x ships a boot menu with timeout=0 (wait forever)
# and duplicate "menu default" entries, selecting failsafe. Debian documents
# the five-second timeout and historical bug #693453 confirms the bad default.
cat > config/bootloaders/isolinux/isolinux.cfg <<'ISOLINUX'
include menu.cfg
default vesamenu.c32
prompt 0
timeout 50
ISOLINUX
# Ensure only the NORMAL Live entry is marked as the menu default.
if [ -f config/bootloaders/isolinux/live.cfg.in ]; then
  python3 - <<'PYTHON'
from pathlib import Path
p = Path("config/bootloaders/isolinux/live.cfg.in")
result, seen = [], False
for line in p.read_text().splitlines():
    if line.strip().lower() == "menu default":
        if seen:
            continue
        seen = True
    result.append(line)
if not seen:
    raise SystemExit("No default Live entry in the Syslinux template")
p.write_text("\n".join(result) + "\n")
PYTHON
fi
# Ubuntu live-build's Syslinux step unconditionally reads 'bootlogo' as a CPIO
# archive in Debian mode, but only generates it in Ubuntu mode. Provide an
# empty, valid archive so the extraction step succeeds without touching disks.
command -v cpio >/dev/null || { echo 'Missing cpio on build host.' >&2; exit 4; }
printf '' | cpio -o -H newc > config/bootloaders/isolinux/bootlogo 2>/dev/null
test -s config/bootloaders/isolinux/bootlogo || {
  echo 'Could not create Syslinux bootlogo archive.' >&2; exit 4;
}
# Ubuntu 24.04 live-build calls the obsolete "rsvg" converter with TWO
# positional filenames. Debian 13 rsvg-convert needs "-o" instead.
# Pre-render the splash on the build host and remove the SVG to prevent
# the old conversion code from running inside the chroot at all.
if [ -f config/bootloaders/isolinux/splash.svg ]; then
  command -v rsvg-convert >/dev/null || {
    echo "Build host needs librsvg2-bin (rsvg-convert)." >&2; exit 4;
  }
  rsvg-convert --format png --height 480 --width 640 \
    config/bootloaders/isolinux/splash.svg \
    -o config/bootloaders/isolinux/splash.png
  test -s config/bootloaders/isolinux/splash.png || exit 4
  rm config/bootloaders/isolinux/splash.svg
fi
echo "Building Debian LXQt live ISO in $OUT"
sudo lb build
# Ubuntu 24.04's legacy live-build names the resulting file binary.hybrid.iso,
# whereas current live-build uses live-image-amd64.hybrid.iso. Normalize to
# one documented CI artifact name and fail early if no real ISO was created.
ISO="$OUT/live-image-amd64.hybrid.iso"
if [[ ! -s "$ISO" ]]; then
  for candidate in "$OUT/binary.hybrid.iso" "$OUT/binary.iso"; do
    if [[ -s "$candidate" ]]; then
      mv "$candidate" "$ISO"
      break
    fi
  done
fi
if [[ ! -s "$ISO" ]]; then
  echo "No ISO output found. Candidates in build directory:" >&2
  find "$OUT" -maxdepth 1 -type f -printf '%f (%s bytes)\\n' >&2
  exit 5
fi
echo "Created ISO: $ISO ($(stat -c %s "$ISO") bytes). Boot-test before distribution."
