#!/usr/bin/env python3
"""Static safety checks for xorriso LXQt live desktop integration."""
from pathlib import Path
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
    assert result.stdout == b"XORRISO_LXQT_DESKTOP_READY\\n", repr(result.stdout)

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
print("PASS: two visible shortcuts, file manager installed, Live username and basic disk safety")
