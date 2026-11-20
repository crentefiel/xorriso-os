#!/usr/bin/env python3
"""Boot the xorriso Linux guest without external NIC and verify TCP over 127.0.0.1."""
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "dist"
LOG = OUT / "qemu-loopback.log"

def main():
    LOG.unlink(missing_ok=True)
    cmd = ["qemu-system-x86_64", "-m", "1024", "-smp", "1", "-no-reboot",
           "-display", "none", "-monitor", "none", "-nic", "none",
           "-serial", "file:" + str(LOG),
           "-kernel", str(OUT / "vmlinuz"),
           "-initrd", str(OUT / "initramfs.cpio.gz"),
           "-append", "console=ttyS0 loglevel=1 rdinit=/init xorriso.ci=loopback"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                raise RuntimeError("QEMU terminated before loopback TCP check")
            log = LOG.read_text(errors="replace") if LOG.exists() else ""
            if "xorriso: loopback TCP PASS" in log:
                print("PASS: guest connected to its own 127.0.0.1 using TCP", flush=True)
                return
            if "xorriso: loopback TCP FAIL" in log:
                raise RuntimeError("Guest could not connect to localhost: " + log[-2500:])
            time.sleep(.4)
        raise RuntimeError("Timeout testing localhost: " + (
            LOG.read_text(errors="replace")[-2500:] if LOG.exists() else "missing log"))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=4)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("FAIL:", exc, file=sys.stderr)
        sys.exit(1)
