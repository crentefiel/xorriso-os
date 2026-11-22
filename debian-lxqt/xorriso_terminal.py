#!/usr/bin/env python3
"""Non-privileged terminal bridge for xorriso. NEVER invokes a shell or root."""
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import time

MAX_OUTPUT = 6000
MAX_COMMAND = 400
HOME = pathlib.Path.home().resolve()
DOCUMENTS = HOME / "Documentos"
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
        # An unrecognized flag must not masquerade as a filename.
        if remaining and remaining[0].startswith("-"):
            raise ValueError("Opcao ls nao permitida")
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

def run_command(command, approve=lambda _: False):
    """Run diagnostics, or a narrowly scoped user-approved mkdir operation."""
    try:
        return run_readonly(command)
    except ValueError as readonly_error:
        # No generic shell or arbitrary command fallback.
        if (not isinstance(command, str) or len(command) > MAX_COMMAND or
                any(ord(c) < 32 for c in command)):
            raise readonly_error
        try:
            parts = shlex.split(command)
        except ValueError:
            raise readonly_error
        if len(parts) != 2 or parts[0] != "mkdir":
            raise readonly_error
        name = parts[1]
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", name) or name in {".", ".."}:
            raise ValueError("mkdir aceita somente nome simples sem caminhos")
        if DOCUMENTS.is_symlink() or DOCUMENTS.resolve() != HOME / "Documentos":
            raise ValueError("Pasta Documentos redirecionada: operacao bloqueada")
        target = DOCUMENTS / name
        if target.exists() or target.is_symlink():
            raise FileExistsError("Pasta ja existe; nada foi sobrescrito")
        if not approve("Autoriza executar mkdir -- " + name + " dentro de " + str(DOCUMENTS) + "?"):
            return {"command": command, "approved": False, "error": "Pessoa cancelou a operacao"}
        DOCUMENTS.mkdir(mode=0o700, parents=True, exist_ok=True)
        binary = shutil.which("mkdir", path="/usr/bin:/bin")
        if not binary:
            return {"command": command, "error": "mkdir nao instalado"}
        result = subprocess.run([binary, "--", name], cwd=str(DOCUMENTS),
                                capture_output=True, text=True, input="", check=False, timeout=12,
                                env={**os.environ, "PATH": "/usr/bin:/bin"})
        return {"command": command, "approved": True,
                "exit_code": result.returncode, "created": target.is_dir(),
                "path": str(target), "output": (result.stdout + result.stderr)[:MAX_OUTPUT]}

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


def open_root_terminal(approve=lambda _: False, installed=None):
    """Open a human-controlled root login prompt. The model never sees a password.

    The AI itself stays unprivileged and must use the existing PKExec tools
    for bounded administrative actions. No preconfigured root password.
    """
    if installed is None:
        try:
            installed = "boot=live" not in pathlib.Path("/proc/cmdline").read_text().split()
        except OSError:
            installed = False
    if not installed:
        return {"approved": False, "error": "Terminal root disponivel apenas apos instalar no HD"}
    if not approve("Abrir terminal root interativo? A senha root sera digitada por voce no terminal, nunca na IA."):
        return {"approved": False, "error": "Operacao cancelada"}
    terminal = shutil.which("qterminal", path="/usr/bin:/bin")
    su = shutil.which("su", path="/usr/bin:/bin")
    if not terminal or not su:
        return {"error": "QTerminal ou su nao instalado"}
    # Fixed argv: no shell, no command generated by the model, no auto-login.
    process = subprocess.Popen([terminal, "-e", su, "-"],
                               stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    time.sleep(0.2)
    code = process.poll()
    return {"application": "qterminal-root-login",
            "launch_requested": code is None or code == 0,
            "pid": process.pid, "exit_code": code,
            "note": "Digite somente no terminal a senha root que voce configurou no HD"}
