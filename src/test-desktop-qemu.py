#!/usr/bin/env python3
"""Boot the *real ISO* through BIOS GRUB, require native framebuffer render.

This is not a console-only smoke test. It only passes if xorriso-desktop
successfully opens /dev/fb0, mmap's the hardware framebuffer, and draws a frame.
The MiniCPM weights are intentionally not part of this small hardware smoke test.
"""
from pathlib import Path
import os
import subprocess
import sys
import time

iso = Path(sys.argv[1] if len(sys.argv) > 1 else "dist/xorriso-alpha-0155-desktop-ia.iso")
assert iso.is_file(), f"ISO not found: {iso}"
logfile = Path("dist/qemu-desktop-framebuffer.log")
cmd = [
    "qemu-system-x86_64", "-m", "2048", "-vga", "std",
    "-display", "none", "-monitor", "none", "-serial", "stdio",
    "-no-reboot", "-no-shutdown", "-cdrom", str(iso),
    "-nic", "none",
]
print("Booting real ISO with VGA and BIOS GRUB:", " ".join(cmd), flush=True)
with logfile.open("wb") as out:
    process = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 110
    marker = b"xorriso: desktop framebuffer rendered PASS"
    try:
        while time.monotonic() < deadline:
            time.sleep(2)
            data = logfile.read_bytes()
            if marker in data:
                print("PASS: actual native framebuffer desktop drew the first frame.")
                sys.exit(0)
            if process.poll() is not None:
                break
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
data = logfile.read_bytes().decode("utf-8", errors="replace")
print("FAILED: framebuffer desktop marker absent. Last serial messages:")
print(data[-4000:])
raise SystemExit(1)
