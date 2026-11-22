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
    echo 'XORRISO_INSTALL_MODE_LIVE: scoped Calamares authentication ready'
else
    # This is installed OS; never retain the Live user's autologin.
    rm -f -- "$AUTLOGIN" "$RULE"
    echo 'XORRISO_INSTALL_MODE_INSTALLED: Live-only login and installer policy disabled'
fi
