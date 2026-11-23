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
        if agent.is_live_session():
            tk.Button(self.root, text="Instalar xorriso no HD / SSD",
                      command=self.open_installer).pack(fill="x", padx=12, pady=(0, 10))
        else:
            tk.Button(self.root, text="Terminal root (requer sua senha)",
                      command=self.open_root_terminal).pack(fill="x", padx=12, pady=(0, 10))
        self.post("xorriso", "Interface pronta. Verificando o LFM2.5-350M local...")
        self._model_last_report = ""
        self.entry.focus_set()
        self.model_watchdog()

    def model_watchdog(self):
        # Model verification and startup must not block the chat window.
        threading.Thread(target=self.check_model, daemon=True).start()
        self.root.after(15000, self.model_watchdog)

    @staticmethod
    def installation_status():
        try:
            path = pathlib.Path("/var/lib/xorriso-model/status.json")
            with path.open(encoding="utf-8") as stream:
                data = json.load(stream)
            phase = data.get("phase")
            if phase == "downloading":
                total = data.get("bytes_total", 0)
                amount = data.get("bytes_received", 0)
                filename = pathlib.Path(str(data.get("file", ""))).name
                if isinstance(amount, int) and isinstance(total, int) and total > 0:
                    percent = min(100, max(0, round(100 * amount / total)))
                    return "Baixando LFM2.5-350M: " + filename + " (" + str(percent) + "%)."
                return "Baixando LFM2.5-350M pelo Hugging Face..."
            if phase == "checking":
                return "Conferindo RAM, disco e arquivos oficiais do LFM2.5-350M..."
            if phase == "ready":
                return "LFM2.5-350M verificado. Aguardando o servidor local iniciar."
            if phase == "error":
                return ("Nao foi possivel instalar a IA: " + str(data.get("detail", ""))[:210] +
                        ". O sistema tentara novamente. Use o terminal para consultar "
                        "journalctl -u xorriso-model-provision.")
        except (OSError, ValueError, TypeError):
            pass
        return "Preparando o LFM2.5-350M incluído na ISO para conversar sem internet."

    def check_model(self):
        """Show only observed API readiness and actual installation progress."""
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/v1/models", timeout=3) as response:
                models = json.load(response).get("data", [])
            available = [m.get("id", "") for m in models if isinstance(m, dict)]
            if not available:
                message = "Servidor local conectado, mas ainda nao anunciou um modelo."
            else:
                message = "Modelo carregado localmente: " + ", ".join(available)[:160]
        except (OSError, ValueError, KeyError, TypeError):
            message = self.installation_status()
        self.root.after(0, lambda: self.update_model_report(message))

    def update_model_report(self, message):
        if message != self._model_last_report:
            self._model_last_report = message
            self.post("xorriso", message)

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
        self.post("xorriso", "Verificando novamente o LFM2.5-350M...")
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

    def open_installer(self):
        # This event runs on Tk's main thread: do not use self.confirm here.
        if not agent.is_live_session():
            self.post("xorriso", "Instalador disponivel apenas na sessao Live.")
            return
        accepted = messagebox.askyesno(
            "Instalar xorriso OS no HD/SSD",
            "O instalador Calamares vai pedir o disco de destino e "
            "uma confirmacao final. A instalacao PODE APAGAR DADOS. "
            "Desconecte XORRISO_DATA e XORRISO_RUNTIME. "
            "Deseja abrir o instalador?", parent=self.root)
        if not accepted:
            self.post("xorriso", "Instalacao cancelada; nenhum disco alterado.")
            return
        try:
            result = agent.action("open_installer", {}, lambda _msg: True)
            if result.get("launch_requested"):
                self.post("xorriso", "Calamares iniciado. Escolha o disco e "
                          "confirme a instalacao somente apos revisar as particoes.")
            else:
                self.post("xorriso", "Instalador nao aberto: " + str(result))
        except Exception as exc:
            self.post("xorriso", "Falha ao iniciar instalador: " + str(exc))

    def open_root_terminal(self):
        if agent.is_live_session():
            self.post("xorriso", "Terminal root permitido somente apos instalar no HD.")
            return
        accepted = messagebox.askyesno(
            "Terminal administrador root",
            "Abrir um terminal root interativo? Voce precisa configurar uma "
            "senha root propria no sistema instalado. Digite a senha SOMENTE "
            "na janela do terminal. A IA nunca recebe sua senha.",
            parent=self.root)
        if not accepted:
            return
        try:
            result = agent.action("open_root_terminal", {}, lambda _message: True)
            self.post("xorriso", "Prompt de senha root solicitado no terminal."
                      if result.get("launch_requested") else str(result))
        except Exception as exc:
            self.post("xorriso", "Nao foi possivel abrir terminal root: " + str(exc))

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
                response = (self.installation_status() +
                            "\nDetalhe da solicitação: " + str(exc)[:200])
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
        assert "open_root_terminal" in agent.TOOLS
        assert "open_installer" in agent.TOOLS
        assert "finish" in agent.TOOLS
        assert agent.MAX_STEPS <= 8
        print("PASS: interface e modulo do agente carregam sem exigir servidor ou display.")
    else:
        Desktop().root.mainloop()
