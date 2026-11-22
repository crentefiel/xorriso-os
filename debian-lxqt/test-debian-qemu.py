#!/usr/bin/env python3
"""Cold-boot Debian Live in QEMU and REQUIRE a running LXQt X11 session."""
import pathlib
import socket
import subprocess
import sys
import tempfile
import time

READY = b"XORRISO_LXQT_DESKTOP_READY"


def shot(sock, target):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(8)
        s.connect(str(sock))
        s.recv(4096)
        s.sendall(("screendump " + str(target) + "\n").encode("ascii"))
        time.sleep(1)
        try:
            s.recv(8192)
        except socket.timeout:
            pass


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


def main():
    if len(sys.argv) != 2 or not pathlib.Path(sys.argv[1]).is_file():
        raise SystemExit("Uso: test-debian-qemu.py CAMINHO/ISO")
    iso = pathlib.Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        sock = tmp / "monitor.sock"
        serial = tmp / "serial.log"
        command = [
            "qemu-system-x86_64", "-m", "3072", "-smp", "2", "-no-reboot",
            "-boot", "d", "-cdrom", str(iso), "-display", "none",
            "-vga", "std", "-nic", "none", "-serial", "file:" + str(serial),
            "-monitor", "unix:" + str(sock) + ",server,nowait",
        ]
        with (tmp / "qemu.log").open("wb") as logfile:
            process = subprocess.Popen(command, stdout=logfile, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 280
                seen_session = False
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError("QEMU exited before LXQt started")
                    # Screens containing BIOS, kernel messages or SDDM alone are
                    # NOT success. An autostart process inside LXQt must confirm
                    # the active user session and working X11 display over serial.
                    if serial.is_file() and READY in serial.read_bytes():
                        seen_session = True
                        path = tmp / "lxqt-desktop.ppm"
                        shot(sock, path)
                        if image_has_content(path):
                            print("PASS: LXQt autostart verified working X11 and nonblack desktop in QEMU")
                            return
                    time.sleep(4)
                if not seen_session:
                    raise RuntimeError("LXQt user session did not signal READY on serial within 280s")
                raise RuntimeError("LXQt signaled READY but graphical framebuffer was blank")
            except Exception:
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


if __name__ == "__main__":
    main()
