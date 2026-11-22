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
assert "WallpaperMode=color\n" in hook
assert "pcmanfm-qt" in packages
assert "username=xorriso" in build
assert '"open_file_manager"' in agent
assert 'runner(["pcmanfm-qt", str(pathlib.Path.home())], timeout=15)' in agent
assert "mkfs" not in hook and "wipefs" not in hook
print("PASS: two visible shortcuts, file manager installed, Live username and basic disk safety")
