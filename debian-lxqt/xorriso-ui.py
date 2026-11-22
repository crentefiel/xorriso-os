#!/usr/bin/env python3
"""Minimal Tk chat for the verified xorriso multi-step agent."""
import importlib.util
import json
import pathlib
import sys
import threading
import urllib.request
import tkinter as tk
from tkinter import messagebox, scrolledtext

AGENT_PATH = pathlib.Path(__file__).with_name("xorriso-agent.py")
spec = importlib.util.spec_from_file_location("xorriso_agent", AGENT_PATH)
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)

class Desktop:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("xorriso IA — Alpha 0.16")
        self.root.geometry("850x575")
        self.history = scrolledtext.ScrolledText(self.root, wrap="word", state="disabled")
        self.history.pack(fill="both", expand=True, padx=12, pady=12)
        bar = tk.Frame(self.root)
        bar.pack(fill="x", padx=12, pady=(0,12))
        self.entry = tk.Entry(bar)
        self.entry.pack(side="left", fill="x", expand=True)
        self.entry.bind("<Return>", lambda _event: self.send())
        self.send_button = tk.Button(bar, text="Enviar", command=self.send)
        self.send_button.pack(side="left", padx=(8,0))
        terminal_row = tk.Frame(self.root)
        terminal_row.pack(fill="x", padx=12, pady=(0, 10))
        tk.Label(terminal_row, text="Terminal (consultas):").pack(side="left")
        self.command_entry = tk.Entry(terminal_row)
        self.command_entry.pack(side="left", fill="x", expand=True, padx=8)
        self.command_entry.bind("<Return>", lambda _event: self.execute_command())
        tk.Button(terminal_row, text="Executar", command=self.execute_command).pack(side="left")
        tk.Button(terminal_row, text="Terminal completo", command=self.open_terminal).pack(side="left", padx=(8,0))
        tk.Button(terminal_row, text="Arquivos", command=self.open_files).pack(side="left", padx=(8,0))
        tk.Button(terminal_row, text="Verificar IA", command=self.recheck_model).pack(side="left", padx=(8,0))
        self.post("xorriso", "Interface pronta. Verificando o servidor local MiniCPM...")
        self.entry.focus_set()
        threading.Thread(target=self.check_model, daemon=True).start()

    def check_model(self):
        """Show real local API health without blocking the desktop UI."""
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/v1/models", timeout=3) as response:
                models = json.load(response).get("data", [])
            available = [m.get("id", "") for m in models if isinstance(m, dict)]
            if not available:
                message = "Servidor respondeu, mas nao anunciou nenhum modelo. Verifique o MiniCPM."
            else:
                message = "Modelo local detectado: " + ", ".join(available)[:160]
        except (OSError, ValueError, KeyError, TypeError) as exc:
            message = ("MiniCPM local indisponivel. Conecte COPIAS dos VDIs "
                       "XORRISO_DATA e XORRISO_RUNTIME sem formatar, e confira o "
                       "servico xorriso-model. Terminal e Arquivos funcionam "
                       "sem IA. Detalhe: " + str(exc)[:180])
        self.root.after(0, lambda: self.post("xorriso", message))

    def post(self, name, text):
        self.history.configure(state="normal")
        self.history.insert("end", name + ": " + text + "\n\n")
        self.history.see("end")
        self.history.configure(state="disabled")

    def confirm(self, explanation):
        ready = threading.Event()
        confirmed = [False]
        def dialog():
            try:
                confirmed[0] = messagebox.askyesno(
                    "Autorizar acao real do xorriso", explanation, parent=self.root)
            finally:
                ready.set()
        self.root.after(0, dialog)
        ready.wait()
        return confirmed[0]

    def recheck_model(self):
        self.post("xorriso", "Verificando novamente o MiniCPM...")
        threading.Thread(target=self.check_model, daemon=True).start()

    def execute_command(self):
        command = self.command_entry.get().strip()
        if not command:
            return
        self.command_entry.delete(0, "end")
        self.post("Voce (terminal)", "$ " + command)
        def worker():
            try:
                result = agent.action("run_terminal_command", {"command": command}, self.confirm)
                output = ("Codigo: " + str(result.get("exit_code", "?")) + "\n" +
                          str(result.get("output", "")))
            except Exception as exc:
                output = "Comando nao executado: " + str(exc)
            self.root.after(0, lambda: self.post("Terminal", output))
        threading.Thread(target=worker, daemon=True).start()

    def open_terminal(self):
        try:
            result = agent.action("open_terminal", {}, lambda _message: True)
            self.post("xorriso", "Terminal aberto como usuario comum." if result.get("launch_requested")
                      else "Nao foi possivel abrir QTerminal: " + str(result))
        except Exception as exc:
            self.post("xorriso", "Falha ao abrir terminal: " + str(exc))

    def open_files(self):
        try:
            result = agent.action("open_file_manager", {}, lambda _message: True)
            self.post("xorriso", "Gerenciador de arquivos solicitado." if result.get("launch_requested")
                      else "Nao foi possivel abrir Arquivos: " + str(result))
        except Exception as exc:
            self.post("xorriso", "Falha ao abrir arquivos: " + str(exc))

    def send(self):
        message = self.entry.get().strip()
        if not message:
            return
        self.entry.delete(0, "end")
        self.post("Voce", message)
        self.send_button.configure(state="disabled")
        def worker():
            try:
                result = agent.solve(message, self.confirm)
                steps = "\n".join(
                    str(i+1) + ". " + step["tool"] + ": " +
                    json.dumps(step["result"], ensure_ascii=False)[:950]
                    for i,step in enumerate(result["steps"]))
                response = (steps + "\n" if steps else "") + result["answer"]
            except Exception as exc:
                response = "O agente nao concluiu o pedido: " + str(exc) + (
                    "\nVerifique se o servidor MiniCPM local esta ativo em 127.0.0.1:8080.")
            self.root.after(0, lambda: self.finish(response))
        threading.Thread(target=worker, daemon=True).start()

    def finish(self, response):
        self.post("xorriso", response)
        self.send_button.configure(state="normal")
        self.entry.focus_set()

if __name__ == "__main__":
    if "--selftest" in sys.argv:
        assert "install_package" in agent.TOOLS
        assert "run_terminal_command" in agent.TOOLS
        assert "open_terminal" in agent.TOOLS
        assert "finish" in agent.TOOLS
        assert agent.MAX_STEPS <= 8
        print("PASS: interface e modulo do agente carregam sem exigir servidor ou display.")
    else:
        Desktop().root.mainloop()
