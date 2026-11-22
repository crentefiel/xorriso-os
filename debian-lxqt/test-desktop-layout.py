#!/usr/bin/env python3
"""Static safety checks for xorriso LXQt live desktop integration."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
hook = (root / "020-xorriso-user.hook.chroot").read_text(encoding="utf-8")
packages = (root / "package-list.chroot").read_text(encoding="utf-8").splitlines()
build = (root / "build.sh").read_text(encoding="utf-8")
agent = (root / "xorriso-agent.py").read_text(encoding="utf-8")

shortcuts = re.findall(r"cat > /home/xorriso/Desktop/([^ ]+) <<'EOF'", hook)
assert sorted(shortcuts) == ["arquivos.desktop", "xorriso.desktop"], shortcuts
assert "Name=Arquivos\n" in hook and "Exec=pcmanfm-qt\n" in hook
assert "Name=xorriso IA\n" in hook
assert "DesktopShortcuts=\n" in hook
assert "xorriso-ui.desktop" in hook and "OnlyShowIn=LXQt;" in hook
assert "WallpaperMode=color\n" in hook
assert "pcmanfm-qt" in packages
assert "username=xorriso" in build
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
