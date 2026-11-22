#!/usr/bin/env python3
"""Non-privileged terminal bridge for xorriso. NEVER invokes a shell or root."""
import os
import pathlib
import shlex
import shutil
import subprocess
import time

MAX_OUTPUT = 6000
MAX_COMMAND = 400
HOME = pathlib.Path.home().resolve()
SERVICES = {"sddm.service", "NetworkManager.service", "xorriso-model.service", "xorriso-volumes.service"}

def checked_argv(command):
    """Only permit specific read-only diagnostics; all other commands are rejected."""
    if not isinstance(command, str) or not command.strip() or len(command) > MAX_COMMAND:
        raise ValueError("Comando ausente ou extenso demais")
    if any(ord(c) < 32 for c in command):
        raise ValueError("Controle ou quebra de linha nao permitido")
    try:
        args = shlex.split(command, posix=True)
    except ValueError as exc:
        raise ValueError("Comando malformado") from exc
    if not args or len(args) > 8:
        raise ValueError("Numero de argumentos invalido")
    name, rest = args[0], args[1:]
    if name in {"whoami", "pwd", "id", "uptime", "date"} and not rest:
        return args
    if name == "uname" and rest in ([], ["-a"], ["-r"], ["-s"]):
        return args
    if name == "free" and rest in ([], ["-h"], ["-m"]):
        return args
    if name == "df" and rest in ([], ["-h"], ["-h", "/"], ["/"]):
        return args
    if name == "ip" and rest in (["-brief", "address"], ["-brief", "link"]):
        return args
    if name == "systemctl" and len(rest) == 2 and rest[0] == "is-active" and rest[1] in SERVICES:
        return args
    if name == "journalctl" and rest in (["-b", "-n", "20", "--no-pager"],):
        return args
    if name == "ls":
        flags = {"-l", "-a", "-la", "-lh", "-lah"}
        remaining = rest[:]
        if remaining and remaining[0] in flags:
            remaining.pop(0)
        if len(remaining) <= 1:
            target = pathlib.Path(remaining[0]).expanduser() if remaining else HOME
            if not target.is_absolute():
                target = HOME / target
            target = target.resolve()
            # Keep the read-only AI probe within its regular user's own files.
            if target == HOME or HOME in target.parents:
                return [name] + rest
    raise ValueError(
        "Comando bloqueado. Use apenas consultas permitidas (whoami, ls, df, free, "
        "uname, ip, systemctl is-active etc.). Para outros comandos, abra o terminal manual.")

def run_readonly(command, approve=None, runner=subprocess.run):
    argv = checked_argv(command)
    # Only read-only tools from a fixed PATH; do not inherit a model-made PATH.
    program = shutil.which(argv[0], path="/usr/bin:/bin")
    if not program:
        return {"command": command, "exit_code": 127, "output": "Comando nao instalado"}
    output = runner([program, *argv[1:]], cwd=str(HOME), input="",
                    capture_output=True, text=True, timeout=12,
                    check=False, env={**os.environ, "PATH": "/usr/bin:/bin"})
    return {"command": command, "argv": argv, "exit_code": output.returncode,
            "output": (output.stdout + output.stderr)[:MAX_OUTPUT]}

def open_terminal(approve=lambda _: False):
    """Open a user-facing QTerminal; no root privileges or autocommands."""
    if not approve("Abrir um terminal interativo como usuario comum?"):
        return {"approved": False, "error": "Abertura cancelada"}
    binary = shutil.which("qterminal", path="/usr/bin:/bin")
    if not binary:
        return {"error": "QTerminal nao instalado"}
    process = subprocess.Popen([binary], stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    time.sleep(0.2)
    code = process.poll()
    return {"application": "qterminal", "launch_requested": code is None or code == 0,
            "pid": process.pid, "exit_code": code}
