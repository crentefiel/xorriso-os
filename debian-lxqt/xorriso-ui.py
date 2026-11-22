#!/usr/bin/env python3
"""xorriso IA: desktop chat; model plans are untrusted, tools verify results."""
import json
import os
import pathlib
import platform
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import messagebox, scrolledtext, simpledialog
from urllib import request

HOME = pathlib.Path.home()
DOCS = HOME / "Documentos"
MODEL = os.environ.get("XORRISO_MODEL", "MiniCPM-V-4.7-1B")
ENDPOINT = os.environ.get("XORRISO_API_URL", "http://127.0.0.1:8080/v1")
SYSTEM = (
    "Voce e a IA administradora do xorriso OS. Responda sempre em portugues brasileiro. "
    "Perguntas sobre capacidade (por exemplo 'voce pode criar uma pasta?') NAO sao ordens: "
    "responda em texto usando action=none, sem executar nada. "
    "Quando o usuario der uma ordem explicita, use uma ferramenta real. "
    "Acoes: none, list_files, create_folder, read_file, create_file, system_info, propose_root. "
    "Em create_folder/create_file/read_file use filename como nome simples, sem caminho. "
    "Em create_file use content. Em propose_root proponha command mas NAO diga que executou. "
    "Nunca invente resultado, arquivo ou aplicativo. Uma resposta em formato JSON puro: "
    "{\"action\":\"none\",\"filename\":\"\",\"content\":\"\",\"command\":\"\",\"message\":\"\"}."
)

def safe_target(name):
    if not isinstance(name, str) or not name or len(name) > 120:
        raise ValueError("Informe um nome simples de 1 a 120 caracteres.")
    if name in (".", "..") or "/" in name or "\\" in name or any(ord(c) < 32 for c in name):
        raise ValueError("Nome invalido: caminhos e controles nao sao permitidos.")
    base = DOCS.resolve()
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = base / name
    if path.is_symlink():
        raise ValueError("Link simbolico nao permitido.")
    return path

def perform(plan, approve):
    if not isinstance(plan, dict):
        raise ValueError("O modelo nao retornou um objeto JSON.")
    action = plan.get("action", "none")
    name = plan.get("filename", "")
    if action == "none":
        return str(plan.get("message", "Nenhuma acao executada."))
    if action == "system_info":
        return "Linux: " + platform.platform() + "\nUsuario: " + str(HOME)
    if action == "list_files":
        DOCS.mkdir(parents=True, exist_ok=True)
        entries = sorted(p.name for p in DOCS.iterdir() if not p.is_symlink())
        return "Conteudo real de " + str(DOCS) + ":\n" + ("\n".join(entries) if entries else "(vazio)")
    if action in ("create_folder", "create_file", "read_file"):
        target = safe_target(name)
        if action == "read_file":
            if not target.is_file():
                raise FileNotFoundError("Arquivo nao encontrado.")
            if target.stat().st_size > 16_384:
                raise ValueError("Arquivo maior que 16 KB.")
            return "Conteudo real de " + target.name + ":\n" + target.read_text(encoding="utf-8")
        if target.exists():
            raise FileExistsError("Esse nome ja existe, nada foi sobrescrito.")
        if not approve("A IA propoe criar " + str(target) + ". Autorizar?"):
            return "Operacao cancelada pelo usuario. Nenhuma acao realizada."
        if action == "create_folder":
            target.mkdir(mode=0o700)
            return "Pasta criada e verificada: " + str(target) if target.is_dir() else "Erro ao criar pasta."
        contents = plan.get("content", "")
        if not isinstance(contents, str) or len(contents.encode("utf-8")) > 16_384:
            raise ValueError("Conteudo de arquivo invalido ou maior que 16 KB.")
        with target.open("x", encoding="utf-8") as handle:
            handle.write(contents)
        return "Arquivo criado e verificado: " + str(target) if target.is_file() else "Erro ao criar arquivo."
    if action == "propose_root":
        command = plan.get("command", "")
        if not isinstance(command, str) or not command or "\n" in command or len(command) > 500:
            raise ValueError("Proposta administrativa invalida.")
        return ("Comando administrativo PROPOSTO (NAO executado):\n" + command +
                "\nO executor root autenticado ainda nao esta integrado nesta nova base Debian.")
    raise ValueError("Ferramenta desconhecida. Nenhuma acao executada.")

def ask_model(text, endpoint=ENDPOINT, model=MODEL):
    url = endpoint.rstrip("/") + "/chat/completions"
    if not (url.startswith("http://127.0.0.1:") or url.startswith("http://localhost:")):
        raise ValueError("Nesta fase, apenas API local e permitida.")
    payload = json.dumps({"model": model, "temperature": 0, "stream": False,
                          "messages": [{"role": "system", "content": SYSTEM},
                                       {"role": "user", "content": text}]}).encode("utf-8")
    req = request.Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
    with request.urlopen(req, timeout=90) as response:
        body = json.load(response)
    raw = body["choices"][0]["message"]["content"]
    try:
        return json.loads(raw)
    except (ValueError, TypeError):
        raise ValueError("A IA nao respondeu com JSON valido; nenhuma acao executada.")

class Desktop:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("xorriso IA")
        self.root.geometry("780x540")
        self.history = scrolledtext.ScrolledText(self.root, wrap="word", state="disabled")
        self.history.pack(fill="both", expand=True, padx=12, pady=12)
        bar = tk.Frame(self.root)
        bar.pack(fill="x", padx=12, pady=(0, 12))
        self.input = tk.Entry(bar)
        self.input.pack(side="left", fill="x", expand=True)
        self.input.bind("<Return>", lambda _event: self.send())
        self.send_button = tk.Button(bar, text="Enviar", command=self.send)
        self.send_button.pack(side="left", padx=(8, 0))
        self.post("xorriso", "Bem-vindo. Converse com o MiniCPM local. Acoes que alteram arquivos pedem confirmacao.")
        self.input.focus_set()

    def post(self, author, msg):
        self.history.configure(state="normal")
        self.history.insert("end", author + ": " + msg + "\n\n")
        self.history.see("end")
        self.history.configure(state="disabled")

    def send(self):
        text = self.input.get().strip()
        if not text:
            return
        self.input.delete(0, "end")
        self.post("Voce", text)
        self.send_button.configure(state="disabled")
        def worker():
            try:
                plan = ask_model(text)
                self.root.after(0, lambda: self.execute(plan))
            except Exception as exc:
                msg = "Falha na API local: " + str(exc) + "\nConfira se o MiniCPM esta ativo."
                self.root.after(0, lambda: self.finish(msg))
        threading.Thread(target=worker, daemon=True).start()

    def execute(self, plan):
        try:
            result = perform(plan, lambda text: messagebox.askyesno("Autorizar operacao", text, parent=self.root))
        except Exception as exc:
            result = "Nao foi executado: " + str(exc)
        self.finish(result)

    def finish(self, result):
        self.post("xorriso", result)
        self.send_button.configure(state="normal")
        self.input.focus_set()

    def run(self):
        self.root.mainloop()

def selftest():
    import tempfile
    global DOCS
    with tempfile.TemporaryDirectory() as directory:
        DOCS = pathlib.Path(directory) / "Documentos"
        assert "vazio" in perform({"action":"list_files"}, lambda _: True)
        assert "cancelada" in perform({"action":"create_folder","filename":"nao"}, lambda _: False)
        assert not (DOCS / "nao").exists()
        assert "criada" in perform({"action":"create_folder","filename":"livros"}, lambda _: True)
        assert (DOCS / "livros").is_dir()
        assert "criado" in perform({"action":"create_file","filename":"notas.txt","content":"ola"}, lambda _: True)
        assert "ola" in perform({"action":"read_file","filename":"notas.txt"}, lambda _: False)
        assert "livros" in perform({"action":"list_files"}, lambda _: False)
        assert "NAO executado" in perform({"action":"propose_root","command":"id"}, lambda _: True)
        for bad in ("../etc", "/tmp", "a/b", "a\\b"):
            try:
                safe_target(bad)
                raise AssertionError("bad path accepted: " + bad)
            except ValueError:
                pass
    print("PASS: executor com arquivos reais, autorizacao, protecao de caminhos e root nao executado")

if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        Desktop().run()
