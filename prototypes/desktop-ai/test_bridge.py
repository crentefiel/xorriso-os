#!/usr/bin/env python3
"""Integration smoke test of the local-only xorriso UI bridge."""
import json
import os
import pathlib
import socket
import subprocess
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent

def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]

class FakeLLM(BaseHTTPRequestHandler):
    def log_message(self, *_):
        return
    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert req["messages"][-1]["content"] == "oi"
        response = json.dumps({"choices": [{"message": {"content": "Ola, sou o MiniCPM simulado."}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

class BridgeSmoke(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.llm = ThreadingHTTPServer(("127.0.0.1", 0), FakeLLM)
        cls.thread = threading.Thread(target=cls.llm.serve_forever, daemon=True)
        cls.thread.start()
        cls.port = free_port()
        env = {**os.environ, "XORRISO_UI_PORT": str(cls.port),
               "XORRISO_LLM_URL": f"http://127.0.0.1:{cls.llm.server_port}/v1"}
        cls.child = subprocess.Popen([sys.executable, str(HERE / "bridge.py")],
                                     cwd=HERE, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(60):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{cls.port}/api/status", timeout=0.2)
                break
            except (OSError, urllib.error.URLError):
                if cls.child.poll() is not None:
                    raise RuntimeError("bridge exited")
                time.sleep(0.05)
        else:
            raise RuntimeError("bridge did not start")

    @classmethod
    def tearDownClass(cls):
        cls.child.terminate()
        cls.child.wait(timeout=5)
        cls.llm.shutdown()
        cls.llm.server_close()

    def call(self, path, payload, headers=None):
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json", **(headers or {})})
        return urllib.request.urlopen(req, timeout=5)

    def test_serves_desktop(self):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/") as r:
            html = r.read().decode()
        self.assertIn('id="desktopAi"', html)
        self.assertIn('id="minimize"', html)
        self.assertIn('"/api/chat"', html)

    def test_chat_roundtrip(self):
        with self.call("/api/chat", {"message":"oi", "history":[]}) as r:
            answer = json.load(r)
        self.assertEqual(answer["answer"], "Ola, sou o MiniCPM simulado.")
        self.assertFalse(answer["executed"])

    def test_no_arbitrary_commands(self):
        with self.assertRaises(urllib.error.HTTPError) as err:
            self.call("/api/exec", {"command":"id"})
        self.assertEqual(err.exception.code, 404)

    def test_denies_untrusted_origin(self):
        with self.assertRaises(urllib.error.HTTPError) as err:
            self.call("/api/chat", {"message":"oi"}, {"Origin":"https://evil.example"})
        self.assertEqual(err.exception.code, 403)

if __name__ == "__main__":
    unittest.main()
