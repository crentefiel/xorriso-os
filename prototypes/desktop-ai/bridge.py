#!/usr/bin/env python3
"""Local-only development bridge for xorriso text UI.

Not installed in the xorriso initramfs. No shell, sudo or arbitrary actions.
Run on a Linux development host with an OpenAI-compatible local server.
"""
import json
import os
import pathlib
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

HERE = pathlib.Path(__file__).resolve().parent
INDEX = HERE / "index.html"
HOST = "127.0.0.1"
PORT = int(os.environ.get("XORRISO_UI_PORT", "8765"))
API = os.environ.get("XORRISO_LLM_URL", "http://127.0.0.1:8080/v1").rstrip("/")
MODEL = os.environ.get("XORRISO_LLM_MODEL", "MiniCPM-V-4.7-1B")
LIMIT = 16_384
SYSTEM = "Voce e a IA local do xorriso OS. Responda em portugues brasileiro. Nao diga que executou comandos ou alterou arquivos: esta interface ainda nao tem executor Linux."

def valid_backend(url):
    p = urlsplit(url)
    return p.scheme == "http" and p.hostname in ("127.0.0.1", "localhost") and p.username is None and p.password is None and p.port is not None and p.path in ("/v1", "/v1/")

if not valid_backend(API):
    raise SystemExit("XORRISO_LLM_URL deve apontar para uma API HTTP em localhost com caminho /v1")

class Handler(BaseHTTPRequestHandler):
    def json_reply(self, status, value):
        payload = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'none'")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            data = INDEX.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Security-Policy", "default-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; object-src 'none'")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif self.path == "/api/status":
            self.json_reply(200, {"bridge": "online", "model": MODEL, "executor": "disabled"})
        else:
            self.json_reply(404, {"error": "Rota nao encontrada"})

    def do_POST(self):
        if self.path != "/api/chat":
            return self.json_reply(404, {"error": "Rota nao encontrada"})
        # A same-origin UI must request JSON. Reject browser form posts.
        if self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json":
            return self.json_reply(415, {"error": "Content-Type deve ser application/json"})
        origin = self.headers.get("Origin")
        if origin not in (None, f"http://{HOST}:{PORT}", f"http://localhost:{PORT}"):
            return self.json_reply(403, {"error": "Origem nao permitida"})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 1 <= size <= LIMIT:
                return self.json_reply(413, {"error": "Mensagem excede o limite"})
            request = json.loads(self.rfile.read(size))
            if not isinstance(request, dict) or not isinstance(request.get("message"), str):
                return self.json_reply(400, {"error": "Mensagem invalida"})
            message = request["message"].strip()
            if not message or len(message) > 2500:
                return self.json_reply(400, {"error": "Texto vazio ou longo demais"})
            previous = request.get("history", [])
            if not isinstance(previous, list):
                return self.json_reply(400, {"error": "Historico invalido"})
            msgs = [{"role": "system", "content": SYSTEM}]
            for item in previous[-8:]:
                if not isinstance(item, dict) or item.get("role") not in ("user", "assistant") or not isinstance(item.get("content"), str) or len(item["content"]) > 2500:
                    return self.json_reply(400, {"error": "Historico invalido"})
                msgs.append({"role": item["role"], "content": item["content"]})
            msgs.append({"role": "user", "content": message})
            payload = json.dumps({"model": MODEL, "messages": msgs, "stream": False, "max_tokens": 256, "temperature": 0.6}).encode("utf-8")
            req = urllib.request.Request(API + "/chat/completions", payload, {"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=120) as response:
                result = json.load(response)
            answer = result["choices"][0]["message"]["content"]
            if not isinstance(answer, str) or not answer.strip():
                raise ValueError("Resposta vazia")
            self.json_reply(200, {"answer": answer, "executed": False})
        except (ValueError, KeyError, IndexError, TypeError, json.JSONDecodeError):
            self.json_reply(400, {"error": "Formato invalido na requisicao ou resposta da IA"})
        except (TimeoutError, OSError, urllib.error.URLError):
            self.json_reply(503, {"error": "MiniCPM indisponivel ou sem resposta"})

def main():
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"xorriso desktop test: http://{HOST}:{PORT} (MiniCPM: {API}, executor desativado)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == "__main__":
    main()
