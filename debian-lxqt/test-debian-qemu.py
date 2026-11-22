#!/usr/bin/env python3
"""Cold-boot a Debian live ISO and check graphical framebuffer in QEMU."""
import pathlib
import socket
import subprocess
import sys
import tempfile
import time

def shot(sock, target):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(8)
        s.connect(str(sock))
        s.recv(4096)
        s.sendall(("screendump " + str(target) + "\n").encode("ascii"))
        time.sleep(2)
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
        nonblack = sum(max(r,g,b) > 35 for r,g,b in pix)
        palette = len({((r//24),(g//24),(b//24)) for r,g,b in pix})
        return nonblack / len(pix) > 0.15 and palette >= 10

def main():
    if len(sys.argv) != 2 or not pathlib.Path(sys.argv[1]).is_file():
        raise SystemExit("Uso: test-debian-qemu.py CAMINHO/ISO")
    image = pathlib.Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        sock = tmp / "monitor.sock"
        command = ["qemu-system-x86_64", "-m", "2048", "-smp", "2",
                   "-no-reboot", "-boot", "d", "-cdrom", str(image),
                   "-display", "none", "-vga", "std", "-nic", "none",
                   "-monitor", "unix:" + str(sock) + ",server,nowait"]
        with (tmp / "qemu.log").open("wb") as logfile:
            process = subprocess.Popen(command, stdout=logfile, stderr=subprocess.STDOUT)
            try:
                # Avoid confusing early BIOS/GRUB frames with the desktop.
                time.sleep(55)
                for attempt in range(13):
                    if process.poll() is not None:
                        raise RuntimeError("QEMU finalizou antes de abrir a area grafica")
                    path = tmp / ("screen-%d.ppm" % attempt)
                    try:
                        shot(sock, path)
                        if image_has_content(path):
                            print("PASS: imagem grafica nao-preta apos boot da ISO no QEMU")
                            return
                    except (OSError, ValueError):
                        pass
                    time.sleep(9)
                raise RuntimeError("Nenhum frame grafico nao-preto detectado em aproximadamente 3 minutos")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
if __name__ == "__main__":
    main()
