#!/usr/bin/env python3
"""CI: verify ext4 data persist across two real Linux guest boots."""
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "dist"
DISK = OUT / "qemu-persistence.img"

def once(stage):
    log = OUT / ("qemu-persistence-" + stage + ".log")
    cmd = ["qemu-system-x86_64", "-m", "1024", "-smp", "1",
           "-no-reboot", "-display", "none", "-monitor", "none",
           "-serial", "file:" + str(log), "-nic", "none",
           "-kernel", str(OUT / "vmlinuz"),
           "-initrd", str(OUT / "initramfs.cpio.gz"),
           "-append", "console=ttyS0 loglevel=1 rdinit=/init xorriso.ci=persist-" + stage,
           "-drive", "file=" + str(DISK) + ",format=raw,if=virtio"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        limit = time.monotonic() + 45
        while time.monotonic() < limit:
            if proc.poll() is not None:
                raise RuntimeError("QEMU exited early in " + stage)
            text = log.read_text(errors="replace") if log.exists() else ""
            if "xorriso: persistence " + stage + " PASS" in text:
                print("PASS: persistence " + stage)
                return
            if "xorriso: persistence FAIL" in text:
                raise RuntimeError("Disk not working (" + stage + "): " + text[-3000:])
            time.sleep(0.5)
        raise RuntimeError("Timed out in " + stage + ": " + (log.read_text(errors="replace")[-3000:] if log.exists() else "empty"))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=4)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=4)

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if DISK.exists():
        DISK.unlink()
    subprocess.run(["truncate", "-s", "96M", str(DISK)], check=True)
    subprocess.run(["mkfs.ext4", "-F", "-q", "-L", "XORRISO_DATA", str(DISK)], check=True)
    once("write")
    once("read")
    print("PASS: ext4 notes survived guest reboot without modifying other disks")

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("FAIL:", exc, file=sys.stderr)
        sys.exit(1)
