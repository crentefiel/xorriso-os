#!/usr/bin/env python3
"""Minimal Tk chat for the verified xorriso multi-step agent."""
import importlib.util
import json
import pathlib
import sys
import threading
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
        self.post("xorriso", "IA local. Consultas sao executadas no Linux real. Alteracoes pedem sua confirmacao.")
        self.entry.focus_set()

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
        assert "finish" in agent.TOOLS
        assert agent.MAX_STEPS <= 8
        print("PASS: interface e modulo do agente carregam sem exigir servidor ou display.")
    else:
        Desktop().root.mainloop()
