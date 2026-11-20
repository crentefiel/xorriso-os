#!/usr/bin/env python3
"""CI: boot Linux guest with E1000 DHCP and reach a mock local AI server through NAT."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import threading
import time
import sys

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "dist"
LOG = OUT / "qemu-host-bridge.log"

class Mock(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        if data.get("model") != "MiniCPM-V-4.7-1B" or self.headers.get("Authorization"):
            self.send_error(400)
            return
        reply = json.dumps({"choices": [{"message": {"content": "Resposta da IA local simulada no host."}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

def main():
    server = ThreadingHTTPServer(("127.0.0.1", 8080), Mock)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    cmd = ["qemu-system-x86_64", "-m", "1024", "-smp", "1", "-no-reboot",
           "-display", "none", "-monitor", "none", "-serial", "file:" + str(LOG),
           "-kernel", str(OUT / "vmlinuz"), "-initrd", str(OUT / "initramfs.cpio.gz"),
           "-append", "console=ttyS0 loglevel=1 rdinit=/init xorriso.ci=hostapi",
           "-nic", "user,model=e1000"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 65
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                raise RuntimeError("QEMU terminou antes da resposta")
            log = LOG.read_text(errors="replace") if LOG.exists() else ""
            if "xorriso: host api bridge PASS" in log:
                assert "Resposta da IA local simulada no host." in log
                print("PASSOU: Linux convidado fez DHCP e consultou API simulada no anfitriao")
                return
            if "xorriso: host api bridge FAIL" in log:
                raise RuntimeError("Falha reportada pela VM: " + log[-3000:])
            time.sleep(0.5)
        raise RuntimeError("Timeout: " + (LOG.read_text(errors="replace")[-3000:] if LOG.exists() else "sem log"))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=4)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        server.shutdown()
        server.server_close()

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("FALHOU:", error, file=sys.stderr)
        sys.exit(1)
