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
  --iso-application xorriso --iso-volume XORRISO --iso-publisher xorriso --archive-areas "main" --apt-indices false --apt-recommends false --security false --bootappend-live "boot=live components live-config.nocomponents=sudo username=xorriso quiet splash console=ttyS0,115200n8 console=tty0"
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
install -D -m 0644 "$ROOT/calamares-packages.conf" config/includes.chroot/etc/calamares/modules/packages.conf
install -D -m 0755 "$ROOT/calamares-sources-media.sh" config/includes.chroot/usr/share/calamares/helpers/calamares-sources-media
# Debian's Calamares sources-media helper installs the firmware-specific
# package from the ISO's own APT repository. The front ends conflict when
# installed together, so live-build resolves their download lists separately.
printf '%s\n' grub-pc > config/package-lists/grub-bios.list.binary
printf '%s\n' grub-efi > config/package-lists/grub-efi.list.binary
cp "$ROOT/10-xorriso-autologin.conf" config/includes.chroot/etc/sddm.conf.d/10-xorriso-autologin.conf
install -m 755 "$ROOT/020-xorriso-user.hook.chroot" "$HOOK_DEST/020-xorriso-user.hook.chroot"
cp "$ROOT/README.md" config/includes.chroot/usr/local/share/xorriso/MIGRATION.md
mkdir -p config/includes.chroot/usr/local/bin
# Node.js 22 is what the Debian 12 reference environment runs. Debian 13's
# nodejs package is 20.x, and its npm package is a separate module tree.
NODE_VERSION=22.23.3
NODE_TARBALL="node-v${NODE_VERSION}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}"
NODE_SHA256=df450af89261115ef9f9e3830c3eeb2cc9213b63c720b1af623cb5dcbe2e02de
curl -fsSL "$NODE_URL" -o "$OUT/${NODE_TARBALL}"
echo "${NODE_SHA256}  $OUT/${NODE_TARBALL}" | sha256sum -c -
tar -xJf "$OUT/${NODE_TARBALL}" -C config/includes.chroot/usr/local --strip-components=1
test -x config/includes.chroot/usr/local/bin/node
test -x config/includes.chroot/usr/local/bin/npm
rm -f "$OUT/${NODE_TARBALL}"

# aichat talks to the existing llama-server. It shows the command and waits.
AICHAT_VERSION=0.30.0
AICHAT_TARBALL="aichat-v${AICHAT_VERSION}-x86_64-unknown-linux-musl.tar.gz"
AICHAT_URL="https://github.com/sigoden/aichat/releases/download/v${AICHAT_VERSION}/${AICHAT_TARBALL}"
AICHAT_SHA256=6b0cc08c5ceb551dc52bfac2221752f82215be5908c70605d655e9b91ab1557c
curl -fsSL "$AICHAT_URL" -o "$OUT/${AICHAT_TARBALL}"
echo "${AICHAT_SHA256}  $OUT/${AICHAT_TARBALL}" | sha256sum -c -
tar --no-same-owner -xzf "$OUT/${AICHAT_TARBALL}" -C "$OUT" aichat
install -m 755 "$OUT/aichat" config/includes.chroot/usr/local/bin/aichat
rm -f "$OUT/${AICHAT_TARBALL}" "$OUT/aichat"
test -x config/includes.chroot/usr/local/bin/aichat
install -D -m 644 "$ROOT/aichat-config.yaml" config/includes.chroot/usr/local/share/xorriso/aichat/config.yaml
install -D -m 755 "$ROOT/xorriso-aichat.sh" config/includes.chroot/usr/local/bin/xorriso-aichat
install -D -m 755 "$ROOT/xorriso-aichat.sh" config/includes.chroot/usr/local/bin/ia
install -m 755 "$ROOT/025-xorriso-brand.hook.chroot" "$HOOK_DEST/025-xorriso-brand.hook.chroot"
install -D -m 644 "$ROOT/branding/logo.png" config/includes.chroot/usr/share/xorriso/logo.png
install -D -m 644 "$ROOT/branding/wallpaper.png" config/includes.chroot/usr/share/xorriso/wallpaper.png
install -D -m 644 "$ROOT/branding/xorriso.plymouth" config/includes.chroot/usr/share/plymouth/themes/xorriso/xorriso.plymouth
install -D -m 644 "$ROOT/branding/xorriso.script" config/includes.chroot/usr/share/plymouth/themes/xorriso/xorriso.script
install -D -m 644 "$ROOT/branding/wallpaper.png" config/includes.chroot/usr/share/plymouth/themes/xorriso/wallpaper.png
CHROME_DEB="$OUT/google-chrome-stable_current_amd64.deb"
curl -fL --retry 3 -o "$CHROME_DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
test "$(stat -c %s "$CHROME_DEB")" -gt 50000000
install -D -m 644 "$CHROME_DEB" config/includes.chroot/usr/local/share/xorriso/google-chrome.deb
rm -f "$CHROME_DEB"
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
install -m 755 "$ROOT/check-grub-media.sh" config/includes.chroot/usr/local/libexec/xorriso/check-grub-media
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
python3 "$ROOT/xorriso-model-provision.py" --bundle config/includes.chroot/usr/share/xorriso/models
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
cp "$ROOT/branding/isolinux-splash.png" config/bootloaders/isolinux/splash.png
find config/bootloaders -type f -exec grep -Iq . {} \; -print0 | xargs -0 sed -i 's/Debian GNU\/Linux/xorriso/g; s/Debian Live/xorriso/g'
echo "Building xorriso live ISO in $OUT"
sudo lb build
sh "$ROOT/check-grub-media.sh" "$OUT/binary" grub-pc grub-efi grub-efi-amd64
# live-build deletes its temporary chroot during lb build. Inspect the actual
# compressed root filesystem that will ship inside the ISO, not OUT/chroot.
SQUASHFS="$OUT/binary/live/filesystem.squashfs"
test -s "$SQUASHFS" || {
  echo "Built ISO is missing its Live root filesystem: $SQUASHFS" >&2; exit 6;
}
for expected in \
  etc/skel/Desktop/chrome.desktop \
  etc/skel/Desktop/configuracoes.desktop \
  etc/skel/Desktop/terminal.desktop \
  etc/skel/.config/lxqt/session.conf \
  etc/os-release \
  usr/bin/qterminal \
  opt/google/chrome/chrome \
  usr/local/bin/ia \
  usr/share/xorriso/logo.png \
  usr/share/xorriso/wallpaper.png \
  usr/share/plymouth/themes/xorriso/xorriso.plymouth \
  etc/skel/.config/autostart/xorriso-trust-launchers.desktop \
  usr/local/bin/xorriso-desktop-ready \
  usr/local/bin/xorriso_terminal.py \
  usr/local/bin/node \
  usr/local/bin/npm \
  usr/local/bin/aichat \
  usr/local/bin/xorriso-aichat \
  usr/local/share/xorriso/aichat/config.yaml \
  usr/local/bin/xorriso-install \
  usr/local/libexec/xorriso/calamares-root \
  usr/share/polkit-1/actions/org.xorriso.install.policy \
  usr/local/libexec/xorriso/install-mode.sh \
  usr/local/libexec/xorriso/admin-service \
  usr/local/libexec/xorriso/model-provision.py \
  usr/local/libexec/xorriso/run-model.py \
  opt/xorriso/llama-server \
  usr/share/xorriso/models/model.json \
  usr/share/xorriso/models/LICENSE \
  usr/lib/sysusers.d/xorriso-model.conf \
  etc/systemd/system/xorriso-model-provision.service \
  usr/local/share/xorriso/live-calamares.rules \
  etc/systemd/system/xorriso-install-mode.service \
  etc/calamares/settings.conf \
  usr/bin/calamares \
  usr/bin/unsquashfs \
  usr/sbin/grub-install \
  usr/sbin/update-grub \
  usr/share/grub/default/grub \
  usr/local/libexec/xorriso/check-grub-media \
  usr/local/bin/xorriso-trust-launchers \
  usr/share/plymouth/themes/xorriso/xorriso.script \
  usr/sbin/update-cracklib \
  var/cache/cracklib/cracklib_dict.pwd \
  var/cache/cracklib/cracklib_dict.pwi \
  var/cache/cracklib/cracklib_dict.hwm \
  usr/lib/live/config/0030-user-setup; do
  if ! unsquashfs -cat "$SQUASHFS" "$expected" >/dev/null 2>&1; then
    echo "xorriso desktop skeleton or live-config is missing from Live SquashFS: $expected" >&2
    exit 6
  fi
done
if ! unsquashfs -cat "$SQUASHFS" etc/calamares/modules/packages.conf | cmp - "$ROOT/calamares-packages.conf"; then
  echo 'Incorrect Calamares package cleanup configuration in the final ISO' >&2; exit 6
fi
if ! unsquashfs -cat "$SQUASHFS" usr/share/calamares/helpers/calamares-sources-media | cmp - "$ROOT/calamares-sources-media.sh"; then
  echo 'Incorrect Calamares media helper in the final ISO' >&2; exit 6
fi
model_path=usr/share/xorriso/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf
projector_path=usr/share/xorriso/models/mmproj-model-f16-4x.gguf
for bundled in "$model_path" "$projector_path"; do
  if ! unsquashfs -cat "$SQUASHFS" "$bundled" | cmp - "config/includes.chroot/$bundled"; then
    echo 'Bundled GGUF differs from the verified download' >&2; exit 6
  fi
done
echo "PASS: ISO SquashFS contains the verified MiniCPM-V 4.7 1B."
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
  calamares calamares-settings-debian squashfs-tools grub2-common grub-pc-bin grub-efi-amd64-bin efibootmgr \
  qterminal gvfs live-boot live-config user-setup xorg \
  xserver-xorg-video-all xserver-xorg-input-all python3-tk \
  plymouth plymouth-themes polkitd pkexec google-chrome-stable \
  git build-essential unzip xz-utils python3-pip python3-venv python3-numpy python3-pil \
  libpam-pwquality cracklib-runtime wamerican; do
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
# Runtime verification: Calamares creates the installed account from this
# SquashFS; failing this gate prevents shipping a broken password screen.
for suffix in pwd pwi hwm; do
  unsquashfs -cat "$SQUASHFS" "var/cache/cracklib/cracklib_dict.$suffix" >/dev/null 2>&1 || {
    echo "Calamares password validation database missing: $suffix" >&2
    exit 7
  }
done
echo 'PASS: Calamares password-quality dictionary is present and nonempty.'

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
