#!/usr/bin/env bash
# Test fixture injected into the Live overlay, never into the shipped system.
set -euo pipefail
export LC_ALL=C DEBIAN_FRONTEND=noninteractive
target=${1:?missing disposable target}
test "$(cat /sys/class/block/vda/serial)" = XOS015TARGET
test "$(findmnt -n -o SOURCE --mountpoint "$target")" = /dev/vda1
test "$(blkid -s LABEL -o value /dev/vda1)" = XOS015TEST
cmp /etc/calamares/modules/packages.conf "$target/etc/calamares/modules/packages.conf"
mountpoint -q -- /run/live/medium
mountpoint -q -- "$target/run/live/medium"
ci=$(mktemp -d /run/xorriso-ci-calamares-XXXXXX)
live_packages=(live-boot live-boot-doc live-config live-config-doc live-config-systemd
               live-tools live-task-localisation live-task-recommended calamares-settings-debian)
# Report which names cause the old transaction to fail with this actual disk and
# offline index. Future images may have records for all names, which is valid.
if ! chroot "$target" apt-get -s --purge -q -y remove "${live_packages[@]}" >"$ci/old-apt.log" 2>&1; then
    grep -F 'Unable to locate package' "$ci/old-apt.log"
fi

# Use Calamares itself: the project packages.conf, its apt backend and the
# native follow-up jobs. Only the GUI input (the pre-mounted disk) and the
# completion notification are supplied by two test-only Python jobs.
mkdir -p "$ci/jobs/xorrisocitarget" "$ci/jobs/xorrisocicomplete"
for name in xorrisocitarget xorrisocicomplete; do
    printf 'type: job\nname: %s\ninterface: python\nscript: main.py\n' "$name" > "$ci/jobs/$name/module.desc"
done
cat > "$ci/jobs/xorrisocitarget/main.py" <<'PY'
import os
import libcalamares

def run():
    gs = libcalamares.globalstorage
    gs.insert("rootMountPoint", os.environ["XORRISO_CI_TARGET"])
    gs.insert("partitions", [{"device": "/dev/vda1", "mountPoint": "/", "fs": "ext4"}])
    gs.insert("hasInternet", False)
PY
cat > "$ci/jobs/xorrisocicomplete/main.py" <<'PY'
import os
from pathlib import Path

def run():
    Path(os.environ["XORRISO_CI_DONE"]).touch()
PY
cat > "$ci/settings.conf" <<SETTINGS
modules-search: [ local, /usr/lib/calamares/modules, "$ci/jobs" ]
branding: debian
dont-chroot: false
prompt-install: false
sequence:
  - exec:
      - xorrisocitarget
SETTINGS
awk '$1 == "-" && $2 == "packages" { active = 1 }
     active && $1 == "-" { print "      - " $2 }
     active && $2 == "sources-final" { exit }' /etc/calamares/settings.conf >> "$ci/settings.conf"
grep -Fxq '      - packages' "$ci/settings.conf"
grep -Fxq '      - initramfs' "$ci/settings.conf"
grep -Fxq '      - sources-final' "$ci/settings.conf"
echo '      - xorrisocicomplete' >> "$ci/settings.conf"

export XORRISO_CI_TARGET="$target" XORRISO_CI_DONE="$ci/completed"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_OPENGL=software
# Override only the orchestration sequence in this temporary Live session.
# A Calamares -c override would also replace the Debian QML and data paths.
mount --bind "$ci/settings.conf" /etc/calamares/settings.conf
calamares -d > "$ci/calamares.log" 2>&1 &
pid=$!
cleanup() {
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    umount /etc/calamares/settings.conf
}
trap cleanup EXIT
deadline=$((SECONDS + 720))
while ! test -f "$XORRISO_CI_DONE"; do
    if ! kill -0 "$pid" 2>/dev/null || (( SECONDS >= deadline )) ||
        grep -Eiq 'FATAL:|Installation Failed|Job .* finished with error|Failed to load modules' "$ci/calamares.log"; then
        tail -n 150 "$ci/calamares.log" >&2
        exit 1
    fi
    sleep 2
done
grep -E 'apt-get.*(exact-name|autoremove)|Removing (live-|calamares-settings-debian)' "$ci/calamares.log" || :
tail -n 55 "$ci/calamares.log"
chroot "$target" dpkg-query -W -f='${Package} ${db:Status-Status}\n' > "$ci/target-packages"
for name in "${live_packages[@]}"; do
    if grep -Fxq "$name installed" "$ci/target-packages"; then
        echo "Calamares left Live package installed: $name" >&2
        exit 1
    fi
done
for name in linux-image-amd64 grub-pc sddm lxqt-session python3-tk; do
    if ! grep -Fx "$name installed" "$ci/target-packages"; then
        echo "Required installed package missing after Calamares cleanup: $name" >&2
        exit 1
    fi
done
chroot "$target" /usr/bin/python3 /usr/local/bin/xorriso-ui.py --selftest
chroot "$target" apt-get check
chroot "$target" dpkg --audit > "$ci/dpkg-audit"
if test -s "$ci/dpkg-audit"; then
    cat "$ci/dpkg-audit" >&2
    exit 1
fi
test ! -e "$target/etc/dpkg/dpkg.cfg.d/calamares-force-unsafe-io"
test ! -e "$target/etc/apt/sources.list.d/debian-live-media.list"
if mountpoint -q -- "$target/run/live/medium"; then
    echo 'Calamares left the ISO mounted inside the installed system' >&2
    exit 1
fi
mountpoint -q -- /run/live/medium
test "$(findmnt -n -o SOURCE --mountpoint "$target")" = /dev/vda1
echo XORRISO_CI_TARGET_MEDIUM_UNMOUNTED
echo XORRISO_CI_CALAMARES_PACKAGES_AND_INITRAMFS_OK
