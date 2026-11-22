#!/usr/bin/env python3
"""Static safety checks for xorriso LXQt live desktop integration."""
from pathlib import Path
import json
import re
import subprocess

root = Path(__file__).resolve().parent
hook = (root / "020-xorriso-user.hook.chroot").read_text(encoding="utf-8")
packages = (root / "package-list.chroot").read_text(encoding="utf-8").splitlines()
build = (root / "build.sh").read_text(encoding="utf-8")
agent = (root / "xorriso-agent.py").read_text(encoding="utf-8")

shortcuts = re.findall(r"cat > /etc/skel/Desktop/([^ ]+) <<'EOF'", hook)
assert sorted(shortcuts) == ["arquivos.desktop", "xorriso.desktop"], shortcuts
assert "Name=Arquivos\n" in hook and "Exec=pcmanfm-qt\n" in hook
assert "Name=xorriso IA\n" in hook
assert "DesktopShortcuts=\n" in hook
assert "xorriso-ui.desktop" in hook and "OnlyShowIn=LXQt;" in hook
assert "WallpaperMode=color\n" in hook
assert "pcmanfm-qt" in packages
# The local AI must be installed *on the HD*, not fetched into ephemeral Live
# memory, and it must never depend on the protected legacy VDI volumes.
model_provision = (root / "xorriso-model-provision.py").read_text(encoding="utf-8")
model_server = (root / "xorriso-run-model.py").read_text(encoding="utf-8")
model_svc = (root / "xorriso-model.service").read_text(encoding="utf-8")
provision_svc = (root / "xorriso-model-provision.service").read_text(encoding="utf-8")
runtime_build = (root / "build-llama-runtime.sh").read_text(encoding="utf-8")
assert "openbmb/MiniCPM-V-4.7-1B-gguf" in model_provision
assert "MiniCPM-V-4_7-1B-Q4_K_M.gguf" in model_provision
assert "mmproj-model-f16-4x.gguf" in model_provision
assert "sha256_file" in model_provision and "verified_local_install" in model_provision
assert "ConditionKernelCommandLine=!boot=live" in model_svc
assert "ConditionKernelCommandLine=!boot=live" in provision_svc
assert "Restart=on-failure" in provision_svc
assert "OnSuccess=xorriso-model.service" in provision_svc
assert "User=xorriso-model" in model_svc and "User=xorriso-model" in provision_svc
assert "127.0.0.1" in model_server and '"8080"' in model_server
assert "openbmb/MiniCPM-V-4.7-1B-gguf" in model_server
assert "35B" not in model_provision and "35B" not in model_server
assert "XORRISO_DATA" not in model_provision and "XORRISO_RUNTIME" not in model_provision
assert "xorriso-volumes.service /etc/systemd/system/multi-user.target.wants" not in hook
assert "xorriso-model-provision.service /etc/systemd/system/multi-user.target.wants" in hook
assert "opt/xorriso/llama-server" in build
assert "model-provision.py" in build and "run-model.py" in build
assert "xorriso-model.conf" in build and "xorriso-model-provision.service" in build
assert "GGML_NATIVE=OFF" in runtime_build and "SOURCE_COMMIT=" in runtime_build
assert (root / "test-model-provision.py").is_file()

# Live-to-HD installation: Calamares is launched only by a deliberate,
# consented IA action, without exposing a third desktop shortcut.
assert all(x in packages for x in ("calamares", "calamares-settings-debian",
                                  "grub-pc-bin", "grub-efi-amd64-bin", "efibootmgr"))
assert all(x in build for x in ("usr/bin/calamares", "etc/calamares/settings.conf",
                               "xorriso-install.sh", "xorriso-install-mode.sh",
                               "xorriso-install-mode.service", "live-calamares.rules"))
assert "open_installer" in agent and "is_live_session" in agent
assert "manage_service" in agent and "ADMIN_SERVICE_HELPER" in agent
assert "usr/local/libexec/xorriso/admin-service" in build
assert (root / "admin-service.py").is_file()

assert "etc/xdg/autostart/xorriso-ui.desktop" in build
assert "cp /etc/skel/.config/autostart/xorriso-ui.desktop /etc/xdg/autostart/xorriso-ui.desktop" in hook
qemu = (root / "test-debian-qemu.py").read_text(encoding="utf-8")
assert "XORRISO_INSTALL_MODE_LIVE" in qemu and "INSTALLER_READY" in qemu
assert "XORRISO_INSTALL_MODE_LIVE" in (root / "xorriso-install-mode.sh").read_text(encoding="utf-8")
installer = (root / "xorriso-install.sh").read_text(encoding="utf-8")
bootmode = (root / "xorriso-install-mode.sh").read_text(encoding="utf-8")
policy = (root / "live-calamares.rules").read_text(encoding="utf-8")
service = (root / "xorriso-install-mode.service").read_text(encoding="utf-8")
assert "boot=live" in installer and "boot=live" in bootmode
assert "XORRISO_DATA" in installer and "XORRISO_RUNTIME" in installer
assert "/usr/bin/pkexec /usr/bin/calamares" in installer
assert "polkit.Result.AUTH_SELF" in policy
assert 'action.lookup("program") === "/usr/bin/calamares"' in policy
assert 'subject.user === "xorriso"' in policy
assert "rm -f --" in bootmode and "10-xorriso-autologin.conf" in bootmode
assert "Before=display-manager.service" in service
assert "Hidden=true" in hook and "calamares-desktop-icon.desktop" in hook
assert "mkfs" not in installer and "wipefs" not in installer
assert "parted " not in installer and "dd if=" not in installer

# Minimal ISO still needs a real X11 window manager. The prior build dropped
# XFWM4 and produced an X11 login with a black framebuffer.
assert "xfwm4" in packages and "xdg-user-dirs" in packages
assert "window_manager=xfwm4" in hook
assert "etc/skel/.config/lxqt/session.conf" in build
assert "lxqt-session" in hook and "pgrep -u" in hook
assert "pcmanfm-qt" in hook
assert "xfwm4" in build
# The optimized image must not pull KDE Plasma through SDDM recommends.
assert "--apt-recommends false" in build
assert "sddm-theme-maui" in packages
assert "sddm-theme-debian-breeze" not in packages
sddm = (root / "10-xorriso-autologin.conf").read_text(encoding="utf-8")
assert "User=xorriso" in sddm
assert "[Theme]" in sddm and "Current=maui" in sddm

assert "xserver-xorg-video-all" in packages
assert "xserver-xorg-input-all" in packages
assert "xorriso-dpkg-status.txt" in build
assert "package-manifest.txt" in build
assert 'grep -Fxq "$unwanted" "$MANIFEST"' in build
assert all(x in build for x in ("plasma-workspace", "plasma-desktop",
                              "plasma-discover", "sddm-theme-debian-breeze"))

assert all(p in packages for p in ("qterminal", "gvfs", "plymouth", "plymouth-themes"))
assert "quiet splash" in build
assert "plymouth-set-default-theme tribar" in hook
assert "etc/skel/.config/autostart/xorriso-trust-launchers.desktop" in build
assert "gio set" in hook and "metadata::trusted true" in hook
assert "QuickExec=true" not in hook
assert "usr/local/bin/xorriso_terminal.py" in build
assert "run_terminal_command" in agent and "open_terminal" in agent

assert "username=xorriso" in build
# Avoid Debian Live component that grants unconditional root via passwordless sudo.
assert "live-config.nocomponents=sudo" in build
assert "user-setup" in packages
assert "useradd -m" not in hook
assert "passwd -l xorriso" not in hook
assert "mkdir -p /etc/skel/.config" in hook
assert "etc/skel/Desktop/xorriso.desktop" in build
assert "usr/lib/live/config/0030-user-setup" in build
assert "XORRISO_LXQT_DESKTOP_TIMEOUT" in hook

# Regression check: the old hook used printf '%s\\\\n', which emits a literal
# backslash+n. The root relay expects a newline-terminated exact marker.
# Evaluate the actual printf expression taken from the generated shell source.
marker_printfs = re.findall(r"printf\s+'[^']+'\s+'XORRISO_LXQT_DESKTOP_READY'", hook)
assert len(marker_printfs) == 2, marker_printfs
for command in marker_printfs:
    result = subprocess.run(["/bin/sh", "-c", command], capture_output=True, check=True)
    assert result.stdout == b"XORRISO_LXQT_DESKTOP_READY\n", repr(result.stdout)

# Ubuntu 24.04 live-build 3.x ignores config/hooks/normal: require legacy detection.
assert "HOOK_HELPER=/usr/lib/live/build/lb_chroot_hooks" in build
assert "HOOK_DEST=config/hooks" in build
assert "HOOK_DEST=config/hooks/normal" in build
assert 'unsquashfs -cat "$SQUASHFS" "$expected"' in build
assert "XORRISO_CHROOT_HOOK_EXECUTED" in hook
assert "After=graphical.target" not in hook
assert '"open_file_manager"' in agent
assert "def start_file_manager():" in agent
assert 'subprocess.Popen([executable, str(pathlib.Path.home())]' in agent
assert 'return start_file_manager()' in agent
assert "mkfs" not in hook and "wipefs" not in hook
# The QEMU test deliberately has no VDI disks; absence must not fail the boot.
volume_script = (root / "mount-volumes.sh").read_text(encoding="utf-8")
assert 'return 0' in volume_script
assert "ro,noload,nosuid,nodev,noexec" in volume_script
assert "mkfs " not in volume_script and "wipefs " not in volume_script

# The error database belongs to the repository (not just a chat).
# A future build should fail if the archive is removed or malformed.
errors = json.loads((root / "errors.json").read_text(encoding="utf-8"))
assert errors["schema_version"] == 1
entries = errors["errors"]
assert len(entries) >= 7
ids = [entry["id"] for entry in entries]
assert len(set(ids)) == len(ids)
assert "XOS-005" in ids
assert all(entry.get("status") and entry.get("cause") and
           entry.get("evidence") and entry.get("fix") and
           entry.get("verification") and entry.get("root_cause_status")
           for entry in entries)
print("PASS: two visible shortcuts, file manager installed, Live username and basic disk safety")
