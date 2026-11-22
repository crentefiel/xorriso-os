#!/bin/sh
# Root-owned boot one-shot: LIVE gets scoped installer auth;
# INSTALLED system removes Live autologin before SDDM starts.
# Never touch any block device, partition, or user data.
set -eu
RULE=/etc/polkit-1/rules.d/49-xorriso-live-calamares.rules
TEMPLATE=/usr/local/share/xorriso/live-calamares.rules
AUTLOGIN=/etc/sddm.conf.d/10-xorriso-autologin.conf
if grep -Eq '(^|[[:space:]])boot=live([[:space:]]|$)' /proc/cmdline; then
    test -s "$TEMPLATE" || exit 11
    mkdir -p /etc/polkit-1/rules.d
    install -m 0644 "$TEMPLATE" "$RULE"
    # Prevent a false QEMU READY when the installer could not unpack the ISO.
    # Debian Live's initramfs exposes the root SquashFS at this read-only path.
    test -x /usr/bin/unsquashfs || {
        echo 'XORRISO_INSTALL_PRECHECK_FAILED: unsquashfs missing' >&2
        exit 12
    }
    test -s /run/live/medium/live/filesystem.squashfs || {
        echo 'XORRISO_INSTALL_PRECHECK_FAILED: rootfs image missing' >&2
        exit 13
    }
    /usr/bin/unsquashfs -s /run/live/medium/live/filesystem.squashfs >/dev/null 2>&1 || {
        echo 'XORRISO_INSTALL_PRECHECK_FAILED: rootfs image unreadable' >&2
        exit 14
    }
    echo 'XORRISO_INSTALL_MODE_LIVE: scoped Calamares authentication ready'
    echo 'XORRISO_INSTALL_MODE_LIVE' > /dev/ttyS0 2>/dev/null || true
else
    # This is installed OS; never retain the Live user's autologin.
    rm -f -- "$AUTLOGIN" "$RULE"
    echo 'XORRISO_INSTALL_MODE_INSTALLED: Live-only login and installer policy disabled'
fi
