#!/usr/bin/env python3
"""Cold-boot Debian Live; require a real LXQt session and collect boot evidence."""
import json
import os
import pathlib
import shutil
import socket
import subprocess
import sys
import tempfile
import time

READY = b"XORRISO_LXQT_DESKTOP_READY"
CHECKPOINTS = (12, 45, 100, 180, 265, 350, 455)


def monitor(sock, instruction):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(8)
        connection.connect(str(sock))
        connection.recv(4096)
        connection.sendall((instruction + "\n").encode("ascii"))
        time.sleep(0.8)
        try:
            return connection.recv(8192)
        except socket.timeout:
            return b""


def shot(sock, target):
    monitor(sock, "screendump " + str(target))


def image_has_content(path):
    from PIL import Image
    if not path.is_file():
        return False
    with Image.open(path) as im:
        im = im.convert("RGB")
        im.thumbnail((128, 128))
        pix = list(im.getdata())
        if not pix:
            return False
        nonblack = sum(max(r, g, b) > 35 for r, g, b in pix)
        palette = len({(r // 24, g // 24, b // 24) for r, g, b in pix})
        return nonblack / len(pix) > 0.15 and palette >= 10


def capture(sock, folder, name):
    from PIL import Image
    ppm = folder / (name + ".ppm")
    png = folder / (name + ".png")
    try:
        shot(sock, ppm)
        if not ppm.is_file():
            raise RuntimeError("QEMU did not generate screendump")
        content = image_has_content(ppm)
        with Image.open(ppm) as im:
            im.save(png)
        ppm.unlink()
        print(f"BOOT_SCREEN {png.name}: has_content={content}", flush=True)
        return content
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"BOOT_SCREEN {name}: capture error: {exc}", file=sys.stderr, flush=True)
        ppm.unlink(missing_ok=True)
        return False


def main():
    if len(sys.argv) != 2 or not pathlib.Path(sys.argv[1]).is_file():
        raise SystemExit("Uso: test-debian-qemu.py CAMINHO/ISO")
    iso = pathlib.Path(sys.argv[1]).resolve()
    out = pathlib.Path(os.environ.get("XORRISO_BOOT_DIAGNOSTICS_DIR", "debian-lxqt/work/boot-diagnostics")).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        sock = tmp / "monitor.sock"
        serial = tmp / "serial.log"
        command = [
            "qemu-system-x86_64", "-accel", "tcg,thread=multi", "-m", "3072", "-smp", "2", "-no-reboot",
            "-boot", "d", "-cdrom", str(iso), "-display", "none",
            "-vga", "std", "-nic", "none", "-serial", "file:" + str(serial),
            "-monitor", "unix:" + str(sock) + ",server,nowait",
        ]
        with (tmp / "qemu.log").open("wb") as logfile:
            process = subprocess.Popen(command, stdout=logfile, stderr=subprocess.STDOUT)
            beginning = time.monotonic()
            seen_session = False
            checkpoint = 0
            try:
                while time.monotonic() - beginning < 480:
                    elapsed = time.monotonic() - beginning
                    if process.poll() is not None:
                        raise RuntimeError("QEMU exited before LXQt started")
                    if checkpoint < len(CHECKPOINTS) and elapsed >= CHECKPOINTS[checkpoint]:
                        if checkpoint == 0:
                            # The Syslinux menu may wait for keyboard input in a headless VM.
                            # Select the default Live entry; this is never a disk installer.
                            try:
                                monitor(sock, "sendkey ret")
                                print("BOOT_ACTION selected default Live menu entry", flush=True)
                            except (OSError, ValueError) as exc:
                                print(f"BOOT_ACTION sendkey unavailable: {exc}", file=sys.stderr, flush=True)
                        capture(sock, out, "boot-%03ds" % CHECKPOINTS[checkpoint])
                        checkpoint += 1
                    if serial.is_file() and READY in serial.read_bytes():
                        seen_session = True
                        if capture(sock, out, "lxqt-desktop"):
                            print("PASS: LXQt autostart verified working X11 and nonblack desktop in QEMU", flush=True)
                            (out / "boot-status.json").write_text(
                                json.dumps({"session_ready": True, "seconds": round(elapsed, 1)}, indent=2))
                            return
                    time.sleep(4)
                if not seen_session:
                    raise RuntimeError("LXQt user session did not signal READY on serial within 480s")
                raise RuntimeError("LXQt signaled READY but graphical framebuffer was blank")
            except Exception as exc:
                (out / "boot-status.json").write_text(
                    json.dumps({"session_ready": seen_session,
                                "seconds": round(time.monotonic() - beginning, 1),
                                "error": str(exc)}, indent=2))
                print("QEMU boot diagnostic (serial tail):", file=sys.stderr)
                if serial.is_file():
                    print(serial.read_bytes()[-6000:].decode("utf-8", "replace"), file=sys.stderr)
                else:
                    print("No serial output; verify kernel boot and console", file=sys.stderr)
                print((tmp / "qemu.log").read_text(errors="replace")[-2000:], file=sys.stderr)
                raise
            finally:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                if serial.is_file():
                    shutil.copyfile(serial, out / "serial.log")
                if (tmp / "qemu.log").is_file():
                    shutil.copyfile(tmp / "qemu.log", out / "qemu.log")


if __name__ == "__main__":
    main()
