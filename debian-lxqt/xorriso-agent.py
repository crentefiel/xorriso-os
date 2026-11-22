#!/usr/bin/env python3
"""Bounded agent loop. Model requests are untrusted; every tool returns observations."""
import json
import os
import pathlib
import re
import shutil
import subprocess
import time
import xorriso_terminal
from urllib import request
from urllib.parse import urlsplit

MODEL = os.environ.get("XORRISO_MODEL", "MiniCPM-V-4.7-1B")
API = os.environ.get("XORRISO_API_URL", "http://127.0.0.1:8080/v1")
DOCUMENTS = pathlib.Path.home() / "Documentos"
MAX_STEPS = 6
MAX_RESPONSE = 12000
ADMIN_HELPER = "/usr/local/libexec/xorriso/admin-package"
INSTALLER_WRAPPER = "/usr/local/bin/xorriso-install"

TOOLS = {
    "list_files": "Lista arquivos reais na pasta Documentos",
    "create_folder": "Cria uma pasta na pasta Documentos, somente com autorizacao",
    "create_file": "Cria arquivo texto sem sobrescrever, com autorizacao",
    "read_file": "Le arquivo texto existente ate 16 KiB",
    "system_info": "Mostra kernel, usuario e informacoes do sistema",
    "system_resources": "Consulta memoria e espaco do disco principal, sem modificar o Linux",
    "network_info": "Consulta interfaces de rede sem alterar configuracoes",
    "list_applications": "Lista aplicativos instalados por seus arquivos .desktop",
    "service_status": "Consulta o estado de um servico permitido do Debian, sem modifica-lo",
    "find_command": "Localiza um comando instalado, sem executa-lo",
    "package_info": "Consulta apt-cache policy para um pacote Debian",
    "install_package": "Pede autorizacao e autenticacao administrativa via pkexec para instalar pacote",
    "open_application": "Abre um aplicativo instalado pelo seu arquivo .desktop, com autorizacao",
    "open_file_manager": "Abre o gerenciador de arquivos PCManFM-Qt na pasta pessoal, sem privilegios root",
    "run_terminal_command": "Executa comandos Linux reais sem shell/root: consultas permitidas ou mkdir NOME em Documentos com confirmacao; args.command",
    "open_terminal": "Abre terminal interativo QTerminal como usuario comum; requer confirmacao",
    "open_installer": "Abre o instalador grafico Calamares SOMENTE no modo Live, com consentimento; a pessoa escolhe o HD/SSD e confirma a instalacao",
    "finish": "Conclui a tarefa em portugues, sem afirmar resultados nao observados",
}
SYSTEM = (
    "Voce e o agente administrador do xorriso OS, Debian LXQt. O usuario fala portugues do Brasil. "
    "Planeje UMA proxima ferramenta por vez, com base nas observacoes reais que receber. "
    "Responda SOMENTE JSON puro no formato "
    "{\"tool\":\"finish\",\"args\":{},\"message\":\"resposta\"}. "
    "Ferramentas disponiveis: " + json.dumps(TOOLS, ensure_ascii=False) + ". "
    "Perguntas sobre capacidade NAO autorizam operacoes: responda com finish. "
    "Somente ordens explicitas de instalar/criar/abrir permitem ferramentas que alteram estado. "
    "Nao invente sucesso; consulte observacoes e somente afirme resultados verificados. "
    "Se uma acao falhar, explique o erro ou use ferramentas de leitura para investigar. "
    "Nao repita uma acao que ja foi negada. Em install_package args.package, somente nome do pacote apt. "
    "Em open_application args.desktop_id, arquivo .desktop instalado. "
    "Para mostrar os arquivos e pastas ao usuario, use open_file_manager com args vazios. "
    "Para comandos Linux de consulta permitidos, use run_terminal_command com args.command. "
    "Nunca use shell, sudo, bash, rm, dd, mkfs ou scripts como parametro do terminal da IA; "
    "para outros comandos oriente a pessoa a abrir o QTerminal manualmente. "
    "Nao confunda permissao para diagnosticar com permissao para alterar o sistema. "
    "Em create_folder/create_file/read_file args.filename, sem barras; create_file args.content. "
    "Em find_command args.name, em package_info args.package. "
    "Para criar pasta via terminal, use mkdir NOME e espere confirmacao. "
    "Quando a pessoa ordenar explicitamente instalar o sistema no HD, ofereca open_installer; "
    "NUNCA execute comandos de formatacao ou particionamento pela IA. "
    "Somente a pessoa escolhe e confirma o disco no instalador Calamares. "
    "XORRISO_DATA e XORRISO_RUNTIME devem permanecer protegidos. "
    "Nao execute shell arbitrario. No maximo seis etapas."
)
NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+._-]{0,79}$")
DESKTOP_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,110}[.]desktop$")

def simple_name(name):
    if not isinstance(name, str) or not name or len(name) > 120:
        raise ValueError("Nome ausente ou longo demais")
    if name in {".", ".."} or "/" in name or "\\" in name or any(ord(c) < 32 for c in name):
        raise ValueError("Somente um nome simples, sem caminhos")
    return name

def filename_path(name):
    name = simple_name(name)
    DOCUMENTS.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory = DOCUMENTS.resolve()
    path = directory / name
    if path.is_symlink():
        raise ValueError("Links simbolicos nao sao permitidos")
    return path

def package_name(name):
    if not isinstance(name, str) or not NAME_PATTERN.fullmatch(name):
        raise ValueError("Nome de pacote Debian invalido")
    if name.startswith("-"):
        raise ValueError("Opcoes de linha de comando nao sao pacotes")
    return name

def run_readonly(argv, timeout=8):
    out = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
    return {"exit_code": out.returncode, "output": (out.stdout + out.stderr)[:3500]}

def desktop_path(name):
    if not isinstance(name, str) or not DESKTOP_PATTERN.fullmatch(name):
        raise ValueError("ID .desktop invalido")
    for base in (pathlib.Path("/usr/share/applications"), pathlib.Path("/usr/local/share/applications")):
        candidate = base / name
        if candidate.is_file() and not candidate.is_symlink():
            return candidate
    raise FileNotFoundError("Aplicativo nao instalado: " + name)

def start_file_manager():
    """Request the graphical file manager without blocking the assistant chat."""
    executable = shutil.which("pcmanfm-qt")
    if not executable:
        return {"application": "pcmanfm-qt", "error": "Gerenciador de arquivos nao instalado"}
    # PCManFM-Qt may remain open for hours. Do not use subprocess.run(timeout=15).
    # This launch uses only desktop-user privileges and no shell command string.
    process = subprocess.Popen([executable, str(pathlib.Path.home())],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(0.2)
    code = process.poll()
    return {"application": "pcmanfm-qt", "launch_requested": code is None or code == 0,
            "pid": process.pid, "exit_code": code}


def is_live_session(kernel_cmdline=None):
    """Only the live boot from our ISO may offer the disk installer."""
    try:
        cmdline = (kernel_cmdline if kernel_cmdline is not None else
                   pathlib.Path("/proc/cmdline").read_text(encoding="utf-8"))
    except OSError:
        return False
    return "boot=live" in cmdline.split()

def start_installer():
    """Launch a fixed wrapper as the desktop user; Calamares asks for polkit."""
    executable = pathlib.Path(INSTALLER_WRAPPER)
    if not executable.is_file() or not os.access(str(executable), os.X_OK):
        return {"launched": False, "error": "Instalador Live nao disponivel"}
    p = subprocess.Popen([str(executable)], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    time.sleep(0.2)
    code = p.poll()
    return {"application": "calamares", "launch_requested": code is None,
            "pid": p.pid, "exit_code": code}

def action(tool, args, approve, runner=run_readonly):
    if not isinstance(args, dict):
        raise ValueError("Argumentos JSON invalidos")
    if tool == "system_info":
        return runner(["uname", "-a"])
    if tool == "system_resources":
        return {"memory": runner(["free", "-h"]), "disk": runner(["df", "-h", "/"])}
    if tool == "network_info":
        return runner(["ip", "-brief", "address"])
    if tool == "list_applications":
        bases = (pathlib.Path("/usr/share/applications"), pathlib.Path("/usr/local/share/applications"))
        ids = sorted({p.name for base in bases if base.is_dir()
                      for p in base.glob("*.desktop") if p.is_file() and not p.is_symlink()})
        return {"desktop_ids": ids[:120], "truncated": len(ids) > 120}
    if tool == "service_status":
        service = args.get("service")
        allowed = {"sddm", "NetworkManager", "xorriso-model", "xorriso-volumes"}
        if not isinstance(service, str) or service not in allowed:
            raise ValueError("Servico nao permitido; consulte o catalogo")
        return {"service": service, **runner(["systemctl", "is-active", service + ".service"])}
    if tool == "list_files":
        DOCUMENTS.mkdir(parents=True, exist_ok=True)
        return {"files": sorted(p.name for p in DOCUMENTS.iterdir() if not p.is_symlink())[:100]}
    if tool == "find_command":
        name = args.get("name", "")
        if not isinstance(name, str) or not NAME_PATTERN.fullmatch(name):
            raise ValueError("Nome de comando invalido")
        return {"name": name, "path": shutil.which(name)}
    if tool == "package_info":
        name = package_name(args.get("package"))
        return runner(["apt-cache", "policy", name])
    if tool in ("create_folder", "create_file", "read_file"):
        target = filename_path(args.get("filename"))
        if tool == "read_file":
            if not target.is_file() or target.stat().st_size > 16384:
                raise ValueError("Arquivo ausente ou maior que 16 KiB")
            return {"filename": target.name, "content": target.read_text(encoding="utf-8")}
        if target.exists():
            raise FileExistsError("Arquivo ou pasta ja existe; nada foi sobrescrito")
        content = args.get("content", "")
        if tool == "create_file" and (not isinstance(content, str) or len(content.encode("utf-8")) > 16384):
            raise ValueError("Conteudo invalido ou maior que 16 KiB")
        if not approve("Autoriza criar " + str(target) + "?"):
            return {"approved": False, "error": "Pessoa cancelou a operacao"}
        if tool == "create_folder":
            target.mkdir(mode=0o700)
            return {"created": target.is_dir(), "path": str(target)}
        with target.open("x", encoding="utf-8") as out:
            out.write(content)
        return {"created": target.is_file(), "path": str(target)}
    if tool == "install_package":
        name = package_name(args.get("package"))
        # Package name only, NEVER a model-authored shell string.
        if not approve("Instalar pacote Debian " + name + " com privilegios administrativos?"):
            return {"approved": False, "error": "Pessoa cancelou a instalacao"}
        if not pathlib.Path(ADMIN_HELPER).is_file():
            return {"approved": True, "error": "Instalador administrativo nao esta instalado"}
        result = runner(["pkexec", ADMIN_HELPER, name], timeout=180)
        return {"package": name, **result, "installed": result["exit_code"] == 0}
    if tool == "open_file_manager":
        # This is a desktop-user operation, never a privileged root command.
        return start_file_manager()
    if tool == "run_terminal_command":
        return xorriso_terminal.run_command(args.get("command"), approve)
    if tool == "open_terminal":
        return xorriso_terminal.open_terminal(approve)
    if tool == "open_installer":
        if not is_live_session():
            return {"error": "Instalacao em HD disponivel somente no modo Live"}
        if not approve("Abrir Calamares para instalar em HD/SSD? "
                       "O instalador pode APAGAR dados, exige selecionar e "
                       "confirmar o destino. Desconecte os VDIs protegidos."):
            return {"approved": False, "error": "Instalacao cancelada"}
        return start_installer()
    if tool == "open_application":
        name = args.get("desktop_id")
        desktop_path(name)
        if not approve("Abrir aplicativo instalado " + name + "?"):
            return {"approved": False, "error": "Pessoa cancelou a abertura"}
        # gtk-launch takes a DESKTOP file identifier, not executable shell text.
        result = runner(["gtk-launch", name], timeout=15)
        return {"desktop_id": name, **result, "launched": result["exit_code"] == 0}
    raise ValueError("Ferramenta indisponivel: " + str(tool))

def local_api_url(base):
    parsed = urlsplit(base)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise ValueError("Por seguranca, somente API HTTP local e aceita nesta versao")
    if parsed.username or parsed.password or parsed.query or parsed.fragment or not parsed.port:
        raise ValueError("URL da API malformada")
    if parsed.path not in ("", "/", "/v1", "/v1/"):
        raise ValueError("Base da API deve terminar em /v1")
    return "http://" + parsed.netloc + "/v1/chat/completions"

def next_plan(messages, endpoint=API, model=MODEL):
    payload = json.dumps({"model": model, "temperature": 0, "stream": False,
                          "messages": messages}, ensure_ascii=False).encode("utf-8")
    req = request.Request(local_api_url(endpoint), data=payload,
                          headers={"Content-Type": "application/json"}, method="POST")
    with request.urlopen(req, timeout=100) as result:
        data = result.read(150000)
    raw = json.loads(data)["choices"][0]["message"]["content"]
    if not isinstance(raw, str) or len(raw) > MAX_RESPONSE:
        raise ValueError("Resposta invalida ou extensa demais")
    try:
        plan = json.loads(raw)
    except ValueError as exc:
        raise ValueError("MiniCPM nao forneceu JSON valido") from exc
    if not isinstance(plan, dict) or plan.get("tool") not in TOOLS:
        raise ValueError("Ferramenta da IA nao reconhecida")
    return plan

def solve(prompt, approve, planner=next_plan, execute=action):
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("Pedido vazio")
    messages = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": prompt}]
    trace = []
    for step in range(MAX_STEPS):
        plan = planner(messages)
        tool = plan["tool"]
        if tool == "finish":
            reply = plan.get("message", "")
            return {"answer": reply if isinstance(reply, str) else "", "steps": trace, "finished": True}
        args = plan.get("args", {})
        try:
            result = execute(tool, args, approve)
        except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
            result = {"error": str(exc)}
        trace.append({"tool": tool, "result": result})
        messages.append({"role": "assistant", "content": json.dumps(plan, ensure_ascii=False)})
        messages.append({"role": "user", "content": "OBSERVACAO REAL DA FERRAMENTA: " +
                         json.dumps(result, ensure_ascii=False)[:4500]})
        if result.get("approved") is False:
            return {"answer": "Operacao cancelada. Nenhuma nova acao sera executada.",
                    "steps": trace, "finished": False}
    return {"answer": "Limite de seis etapas alcancado. Confira os resultados antes de continuar.",
            "steps": trace, "finished": False}
