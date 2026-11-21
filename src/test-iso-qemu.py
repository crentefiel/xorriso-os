#!/usr/bin/env python3
"""Smoke test the generated BIOS/GRUB ISO itself (not a direct kernel boot)."""
import json
from pathlib import Path
import socket
import subprocess
import sys
import time

def ppm_lit_pixels(path):
    with open(path, "rb") as f:
        if f.readline().strip() != b"P6":
            raise RuntimeError("Invalid PPM screenshot")
        dims = f.readline().strip()
        while dims.startswith(b"#"):
            dims = f.readline().strip()
        w, h = map(int, dims.split())
        if f.readline().strip() != b"255":
            raise RuntimeError("Invalid PPM depth")
        data = f.read()
    if len(data) != w*h*3:
        raise RuntimeError("Incomplete screenshot")
    return sum(max(data[i:i+3]) > 32 for i in range(0, len(data), 3))

class QMP:
    def __init__(self, sock):
        self.sock = sock
        self.file = sock.makefile("rwb", buffering=0)
        self.read()
        self.run("qmp_capabilities")

    def read(self):
        line = self.file.readline()
        if not line:
            raise RuntimeError("QMP disconnected")
        return json.loads(line)

    def run(self, name, **args):
        msg = {"execute": name}
        if args:
            msg["arguments"] = args
        self.file.write((json.dumps(msg)+"\n").encode())
        while True:
            res = self.read()
            if "event" in res:
                continue
            if "error" in res:
                raise RuntimeError("QMP error: "+str(res["error"]))
            if "return" in res:
                return res["return"]

def main():
    root = Path(__file__).resolve().parent.parent
    out = root / "dist"
    iso = Path(sys.argv[1]).resolve() if len(sys.argv)>1 else out / "xorriso-alpha-07-grub.iso"
    if not iso.is_file():
        raise RuntimeError("ISO absent: "+str(iso))
    qmp_sock = Path("/tmp/xorriso-qmp-iso.sock")
    qmp_sock.unlink(missing_ok=True)
    process_log = out / "qemu-iso-process.log"
    serial_log = out / "qemu-iso-serial.log"
    cmd = ["qemu-system-x86_64", "-m", "1024", "-smp", "1",
           "-boot", "d", "-cdrom", str(iso), "-no-reboot",
           "-display", "none", "-vga", "std", "-nic", "none",
           "-monitor", "none", "-serial", "file:"+str(serial_log),
           "-qmp", "unix:"+str(qmp_sock)+",server=on,wait=off"]
    print("Booting ISO with BIOS and GRUB:", iso, flush=True)
    with process_log.open("wb") as log:
        proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
        try:
            conn = None
            for _ in range(100):
                if proc.poll() is not None:
                    raise RuntimeError("QEMU exited early")
                try:
                    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    conn.connect(str(qmp_sock))
                    conn.settimeout(12)
                    break
                except OSError:
                    conn.close()
                    time.sleep(.2)
            if conn is None:
                raise RuntimeError("QMP socket never became available")
            with conn:
                qmp = QMP(conn)
                time.sleep(22)
                if proc.poll() is not None:
                    raise RuntimeError("QEMU exited while booting")
                screens = {s:out/("qemu-iso-"+s+".ppm") for s in ("start","chat","chat-blank","console","blank")}
                qmp.run("screendump", filename=str(screens["start"]))
                qmp.run("send-key", keys=[{"type":"qcode", "data":"f3"}])
                time.sleep(3)
                qmp.run("screendump", filename=str(screens["chat"]))
                qmp.run("send-key", keys=[{"type":"qcode", "data":"esc"}])
                time.sleep(2)
                qmp.run("screendump", filename=str(screens["chat-blank"]))
                qmp.run("send-key", keys=[{"type":"qcode", "data":"f2"}])
                time.sleep(3)
                qmp.run("screendump", filename=str(screens["console"]))
                qmp.run("send-key", keys=[{"type":"qcode", "data":"esc"}])
                time.sleep(2)
                qmp.run("screendump", filename=str(screens["blank"]))
                counts = {k: ppm_lit_pixels(v) for k,v in screens.items()}
                (out/"qemu-iso-screen.log").write_text(
                    "\n".join(f"{k}: nonblack pixels={v}" for k,v in counts.items())+"\n")
                print("Screens:", counts, flush=True)
                if counts["chat"] < 350 or counts["chat"] < counts["start"] + 200:
                    raise RuntimeError("F3 chat UI did not appear")
                if counts["chat-blank"] > max(100, int(counts["chat"]*.12)):
                    raise RuntimeError("Esc did not close the chat UI")
                if counts["console"] < 160 or counts["console"] < counts["start"] + 120:
                    raise RuntimeError("F2 console did not appear")
                if counts["blank"] > max(100, int(counts["console"]*.12)):
                    raise RuntimeError("Esc did not return to blank screen")
                print("PASS: real ISO GRUB; F3 chat UI; Esc blank; F2 console; Esc blank", flush=True)
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)
            qmp_sock.unlink(missing_ok=True)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("FAIL:", e, file=sys.stderr)
        sys.exit(1)
