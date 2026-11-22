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
  --archive-areas "main" --apt-indices false --apt-recommends false --security false --bootappend-live "boot=live components live-config.nocomponents=sudo username=xorriso quiet splash console=ttyS0,115200n8 console=tty0"
# Ubuntu 24.04 bundles live-build 3.0, which only processes config/hooks/*.chroot.
# Newer live-build expects config/hooks/normal/*.hook.chroot.
# Select the layout by inspecting the actual installed build helper.
HOOK_HELPER=/usr/lib/live/build/lb_chroot_hooks
test -f "$HOOK_HELPER" || { echo "Missing live-build chroot hook runner" >&2; exit 4; }
if grep -Fq 'config/hooks/*.chroot' "$HOOK_HELPER"; then
  HOOK_DEST=config/hooks
else
  HOOK_DEST=config/hooks/normal
fi
echo "Using live-build hook directory: $HOOK_DEST"
mkdir -p config/package-lists config/includes.chroot/etc/sddm.conf.d \
  "$HOOK_DEST" config/includes.chroot/usr/local/share/xorriso
mkdir -p config/archives
# live-build on Ubuntu 24.04 uses an obsolete trixie/updates URL. Override safely.
# Debian 13 security suite is trixie-security under /debian-security.
printf '%s\n' 'deb http://security.debian.org/debian-security trixie-security main' > config/archives/debian-security.list.chroot
cp "$ROOT/package-list.chroot" config/package-lists/xorriso.list.chroot
cp "$ROOT/10-xorriso-autologin.conf" config/includes.chroot/etc/sddm.conf.d/10-xorriso-autologin.conf
install -m 755 "$ROOT/020-xorriso-user.hook.chroot" "$HOOK_DEST/020-xorriso-user.hook.chroot"
cp "$ROOT/README.md" config/includes.chroot/usr/local/share/xorriso/MIGRATION.md
mkdir -p config/includes.chroot/usr/local/bin
install -m 755 "$ROOT/xorriso-ui.py" config/includes.chroot/usr/local/bin/xorriso-ui.py
install -m 755 "$ROOT/xorriso-agent.py" config/includes.chroot/usr/local/bin/xorriso-agent.py
install -m 755 "$ROOT/xorriso_terminal.py" config/includes.chroot/usr/local/bin/xorriso_terminal.py
install -m 755 "$ROOT/xorriso-install.sh" config/includes.chroot/usr/local/bin/xorriso-install
mkdir -p config/includes.chroot/usr/share/polkit-1/actions
install -m 644 "$ROOT/xorriso-calamares.policy" config/includes.chroot/usr/share/polkit-1/actions/org.xorriso.install.policy
mkdir -p config/includes.chroot/usr/local/libexec/xorriso config/includes.chroot/etc/systemd/system
install -m 755 "$ROOT/admin-package.py" config/includes.chroot/usr/local/libexec/xorriso/admin-package
install -m 755 "$ROOT/admin-service.py" config/includes.chroot/usr/local/libexec/xorriso/admin-service
install -m 755 "$ROOT/calamares-root.sh" config/includes.chroot/usr/local/libexec/xorriso/calamares-root
install -m 755 "$ROOT/mount-volumes.sh" config/includes.chroot/usr/local/libexec/xorriso/mount-volumes.sh
install -m 755 "$ROOT/start-model.sh" config/includes.chroot/usr/local/libexec/xorriso/start-model.sh
install -m 755 "$ROOT/xorriso-run-model.py" config/includes.chroot/usr/local/libexec/xorriso/run-model.py
install -m 755 "$ROOT/xorriso-model-provision.py" config/includes.chroot/usr/local/libexec/xorriso/model-provision.py
install -m 644 "$ROOT/xorriso-model-provision.service" config/includes.chroot/etc/systemd/system/xorriso-model-provision.service
mkdir -p config/includes.chroot/usr/lib/sysusers.d config/includes.chroot/opt/xorriso
install -m 644 "$ROOT/xorriso-model-sysusers.conf" config/includes.chroot/usr/lib/sysusers.d/xorriso-model.conf
# llama-server must actually be in the ISO: source built at pinned revision by CI.
test -x "$ROOT/runtime-dist/llama-server" || {
  echo 'MiniCPM runtime missing. Build first: bash debian-lxqt/build-llama-runtime.sh' >&2; exit 8;
}
install -m 755 "$ROOT/runtime-dist/llama-server" config/includes.chroot/opt/xorriso/llama-server
install -m 755 "$ROOT/xorriso-install-mode.sh" config/includes.chroot/usr/local/libexec/xorriso/install-mode.sh
install -m 644 "$ROOT/live-calamares.rules" config/includes.chroot/usr/local/share/xorriso/live-calamares.rules
install -m 644 "$ROOT/xorriso-install-mode.service" config/includes.chroot/etc/systemd/system/xorriso-install-mode.service
install -m 644 "$ROOT/xorriso-volumes.service" config/includes.chroot/etc/systemd/system/xorriso-volumes.service
install -m 644 "$ROOT/xorriso-model.service" config/includes.chroot/etc/systemd/system/xorriso-model.service
test -x "$HOOK_DEST/020-xorriso-user.hook.chroot"
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
# live-build deletes its temporary chroot during lb build. Inspect the actual
# compressed root filesystem that will ship inside the ISO, not OUT/chroot.
SQUASHFS="$OUT/binary/live/filesystem.squashfs"
test -s "$SQUASHFS" || {
  echo "Built ISO is missing its Live root filesystem: $SQUASHFS" >&2; exit 6;
}
for expected in \
  etc/skel/Desktop/xorriso.desktop \
  etc/skel/Desktop/arquivos.desktop \
  etc/skel/.config/lxqt/session.conf \
  etc/skel/.config/autostart/xorriso-ui.desktop \
  etc/xdg/autostart/xorriso-ui.desktop \
  etc/skel/.config/autostart/xorriso-trust-launchers.desktop \
  usr/local/bin/xorriso-desktop-ready \
  usr/local/bin/xorriso_terminal.py \
  usr/local/bin/xorriso-install \
  usr/local/libexec/xorriso/calamares-root \
  usr/share/polkit-1/actions/org.xorriso.install.policy \
  usr/local/libexec/xorriso/install-mode.sh \
  usr/local/libexec/xorriso/admin-service \
  usr/local/libexec/xorriso/model-provision.py \
  usr/local/libexec/xorriso/run-model.py \
  opt/xorriso/llama-server \
  usr/lib/sysusers.d/xorriso-model.conf \
  etc/systemd/system/xorriso-model-provision.service \
  usr/local/share/xorriso/live-calamares.rules \
  etc/systemd/system/xorriso-install-mode.service \
  etc/calamares/settings.conf \
  usr/bin/calamares \
  usr/local/bin/xorriso-trust-launchers \
  usr/share/plymouth/themes/tribar/tribar.plymouth \
  usr/lib/live/config/0030-user-setup; do
  if ! unsquashfs -cat "$SQUASHFS" "$expected" >/dev/null 2>&1; then
    echo "xorriso desktop skeleton or live-config is missing from Live SquashFS: $expected" >&2
    exit 6
  fi
done
printf '%s\\n' 'PASS: xorriso desktop customization verified in ISO SquashFS.'
# Validate actual installed Debian packages, not just package-list intentions.
# A missing theme or a recursive Plasma dependency is a failed minimal image.
STATUS_FILE="$OUT/xorriso-dpkg-status.txt"
MANIFEST="$OUT/package-manifest.txt"
unsquashfs -cat "$SQUASHFS" var/lib/dpkg/status > "$STATUS_FILE"
awk -F': ' '/^Package: / { package=$2 }
             /^Status: install ok installed$/ { if (package != "") print package }' \
    "$STATUS_FILE" | LC_ALL=C sort -u > "$MANIFEST"
for needed in sddm sddm-theme-maui lxqt-core lxqt-session xfwm4 xdg-user-dirs pcmanfm-qt \
  calamares calamares-settings-debian grub-pc-bin grub-efi-amd64-bin efibootmgr \
  qterminal gvfs live-boot live-config user-setup xorg \
  xserver-xorg-video-all xserver-xorg-input-all python3-tk \
  plymouth plymouth-themes polkitd pkexec; do
  grep -Fxq "$needed" "$MANIFEST" || {
    echo "Required package missing in built ISO: $needed" >&2; exit 7;
  }
done
for unwanted in plasma-workspace plasma-desktop plasma-discover sddm-theme-debian-breeze; do
  if grep -Fxq "$unwanted" "$MANIFEST"; then
    echo "Unexpected KDE Plasma component still installed: $unwanted" >&2
    exit 7
  fi
done
echo "Verified minimal installed package count: $(wc -l < "$MANIFEST")"
echo "PASS: LXQt runtime and lightweight SDDM without Plasma in SquashFS."

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
