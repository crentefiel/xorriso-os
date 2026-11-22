#!/usr/bin/env python3
"""Tests actual bounded agent orchestration without privileged side effects."""
import importlib.util
import pathlib
import tempfile

MODULE = pathlib.Path(__file__).with_name("xorriso-agent.py")
spec = importlib.util.spec_from_file_location("xorriso_agent", MODULE)
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)

def test_loop():
    plans = iter([
        {"tool": "package_info", "args": {"package": "pcmanfm-qt"}},
        {"tool": "install_package", "args": {"package": "pcmanfm-qt"}},
        {"tool": "open_application", "args": {"desktop_id": "pcmanfm-qt.desktop"}},
        {"tool": "finish", "message": "Aplicativo solicitado e aberto."}
    ])
    observed = []
    def planner(messages):
        observed.append(messages[-1]["content"])
        return next(plans)
    calls = []
    def execute(tool, args, approve):
        calls.append((tool, args))
        if tool == "package_info":
            return {"exit_code":0,"output":"candidate: pcmanfm-qt"}
        if tool == "install_package":
            assert approve("instalar?")
            return {"exit_code":0,"installed":True}
        if tool == "open_application":
            assert approve("abrir?")
            return {"exit_code":0,"launched":True}
        raise AssertionError(tool)
    result = agent.solve("Instale e abra gerenciador de arquivos", lambda _: True,
                         planner=planner, execute=execute)
    assert result["finished"]
    assert [x[0] for x in calls] == ["package_info", "install_package", "open_application"]
    assert "OBSERVACAO REAL" in observed[1]
    assert len(result["steps"]) == 3

def test_denial_stops():
    calls = []
    def planner(_messages):
        return {"tool":"install_package","args":{"package":"pcmanfm-qt"}}
    def execute(tool, args, approve):
        calls.append(tool)
        assert not approve("autorizacao?")
        return {"approved":False, "error":"cancelado"}
    result = agent.solve("Instale pcmanfm-qt", lambda _: False, planner=planner, execute=execute)
    assert not result["finished"]
    assert len(calls) == 1

def test_real_file_actions():
    with tempfile.TemporaryDirectory() as tmp:
        previous = agent.DOCUMENTS
        agent.DOCUMENTS = pathlib.Path(tmp) / "Documentos"
        try:
            assert not agent.action("create_folder",{"filename":"livros"},lambda _:False)["approved"]
            assert not (agent.DOCUMENTS/"livros").exists()
            assert agent.action("create_folder",{"filename":"livros"},lambda _:True)["created"]
            assert agent.action("create_file",{"filename":"nota.txt","content":"ola"},lambda _:True)["created"]
            assert agent.action("read_file",{"filename":"nota.txt"},lambda _:True)["content"] == "ola"
            assert "livros" in agent.action("list_files",{},lambda _:False)["files"]
            for name in ("../etc","/tmp/pwn","foo/bar","a\\b"):
                try:
                    agent.filename_path(name)
                    raise AssertionError(name)
                except ValueError:
                    pass
        finally:
            agent.DOCUMENTS = previous

def test_package_validation():
    for name in ("-y", "x;whoami", "apt-get install", "../x", "x\n"):
        try:
            agent.package_name(name)
            raise AssertionError(name)
        except ValueError:
            pass
    for name in ("http://example.com/v1","http://127.0.0.1:8080/v1@evil"):
        try:
            agent.local_api_url(name)
            raise AssertionError(name)
        except ValueError:
            pass
    assert agent.local_api_url("http://127.0.0.1:8080/v1").endswith("/chat/completions")
    assert agent.action("find_command",{"name":"sh"},lambda _:True)["path"]
    assert agent.action("package_info",{"package":"pcmanfm-qt"},lambda _:False,
                        runner=lambda argv: {"command":argv})["command"] == ["apt-cache","policy","pcmanfm-qt"]

def test_install_is_not_shell():
    import unittest.mock
    with unittest.mock.patch.object(agent.pathlib.Path,"is_file", return_value=True):
        calls = []
        def runner(argv, timeout):
            calls.append((argv,timeout))
            return {"exit_code":0,"output":"installed"}
        out = agent.action("install_package", {"package":"pcmanfm-qt"},lambda _:True,runner)
        assert out["installed"]
        assert calls[0][0] == ["pkexec",agent.ADMIN_HELPER,"pcmanfm-qt"]
        assert not agent.action("install_package",{"package":"pcmanfm-qt"},lambda _:False,runner)["approved"]
        assert len(calls)==1



def test_linux_inspection_tools():
    assert "system_resources" in agent.TOOLS
    assert "network_info" in agent.TOOLS
    assert "service_status" in agent.TOOLS
    assert "list_applications" in agent.TOOLS
    calls = []
    def spy(argv):
        calls.append(argv)
        return {"exit_code": 0, "output": "mocked"}
    resources = agent.action("system_resources", {}, lambda _:False, runner=spy)
    assert resources["memory"]["exit_code"] == 0
    assert resources["disk"]["exit_code"] == 0
    assert ["free", "-h"] in calls and ["df", "-h", "/"] in calls
    assert agent.action("network_info", {}, lambda _:False, runner=spy)["exit_code"] == 0
    assert agent.action("service_status", {"service":"sddm"}, lambda _:False, runner=spy)["service"] == "sddm"
    try:
        agent.action("service_status", {"service":"sshd; rm -rf /"}, lambda _:False, runner=spy)
        raise AssertionError("unsafe service accepted")
    except ValueError:
        pass
    assert isinstance(agent.action("list_applications", {}, lambda _:False)["desktop_ids"], list)


def test_nonblocking_file_manager_launch():
    from unittest.mock import patch
    with patch.object(agent.shutil, "which", return_value="/usr/bin/pcmanfm-qt"), \
         patch.object(agent.subprocess, "Popen") as mock_popen, \
         patch.object(agent.time, "sleep"):
        mock_popen.return_value.pid = 888
        mock_popen.return_value.poll.return_value = None
        result = agent.action("open_file_manager", {}, lambda _: False)
        assert result["launch_requested"] is True
        assert result["pid"] == 888
        command = mock_popen.call_args.args[0]
        assert command[0] == "/usr/bin/pcmanfm-qt"
        assert command[1] == str(pathlib.Path.home())
        assert "shell" not in mock_popen.call_args.kwargs


def test_safe_terminal_commands():
    # No shell, no root, and no raw arbitrary executable from model output.
    terminal = agent.xorriso_terminal
    assert agent.TOOLS["run_terminal_command"]
    assert agent.TOOLS["open_terminal"]
    out = agent.action("run_terminal_command", {"command": "whoami"}, lambda _:False)
    assert out["exit_code"] == 0
    assert out["argv"] == ["whoami"]
    for command in (
        "sudo id", "su -", "bash -c whoami", "sh -c whoami",
        "rm -rf /", "ls /data", "ls /runtime-data", "ls /etc",
        "ls -R", "whoami; rm -rf /", "python3 -c print(1)",
        "systemctl stop sddm.service", "ip link set eth0 down",
        "journalctl --vacuum-time=1s", "df -h ; echo x",
    ):
        try:
            terminal.checked_argv(command)
            raise AssertionError("Comando inseguro aceito: " + command)
        except ValueError:
            pass
    assert terminal.checked_argv("df -h") == ["df", "-h"]
    assert terminal.checked_argv("ls -la") == ["ls", "-la"]

def test_terminal_mkdir_requires_consent_and_stays_in_documents():
    terminal = agent.xorriso_terminal
    with tempfile.TemporaryDirectory() as tmp:
        previous_home, previous_docs = terminal.HOME, terminal.DOCUMENTS
        try:
            terminal.HOME = pathlib.Path(tmp).resolve()
            terminal.DOCUMENTS = terminal.HOME / "Documentos"
            denied = terminal.run_command("mkdir teste", lambda _:False)
            assert denied["approved"] is False
            assert not terminal.DOCUMENTS.exists()
            allowed = terminal.run_command("mkdir teste", lambda _:True)
            assert allowed["exit_code"] == 0 and allowed["created"]
            assert (terminal.DOCUMENTS / "teste").is_dir()
            try:
                terminal.run_command("mkdir teste", lambda _:True)
                raise AssertionError("mkdir overwrote existing directory")
            except FileExistsError:
                pass
            for name in ("../tmp", "/data", "-p", "foo/bar", ";echo"):
                try:
                    terminal.run_command("mkdir " + name, lambda _:True)
                    raise AssertionError("Unsafe mkdir name accepted: " + name)
                except ValueError:
                    pass
        finally:
            terminal.HOME, terminal.DOCUMENTS = previous_home, previous_docs


def test_interactive_terminal_requires_approval():
    from unittest.mock import patch
    terminal = agent.xorriso_terminal
    with patch.object(terminal.shutil, "which", return_value="/usr/bin/qterminal"), \
         patch.object(terminal.subprocess, "Popen") as popen, \
         patch.object(terminal.time, "sleep"):
        declined = agent.action("open_terminal", {}, lambda _:False)
        assert declined["approved"] is False
        assert popen.call_count == 0
        popen.return_value.pid = 314
        popen.return_value.poll.return_value = None
        approved = agent.action("open_terminal", {}, lambda _:True)
        assert approved["launch_requested"] and approved["pid"] == 314
        assert popen.call_args.args[0] == ["/usr/bin/qterminal"]
        assert popen.call_args.kwargs.get("shell") is not True


def test_authenticated_admin_service_management():
    from unittest.mock import patch
    assert "manage_service" in agent.TOOLS
    for service, action in (("sddm", "stop"),
                            ("../../etc/passwd", "restart"),
                            ("xorriso-model", "shell"),
                            ("NetworkManager", "bash")):
        try:
            agent.action("manage_service",
                         {"operation": action, "service": service},
                         lambda _: True)
            raise AssertionError("Invalid service operation accepted")
        except ValueError:
            pass
    with patch.object(agent.pathlib.Path, "is_file", return_value=True):
        invoked = []
        def fake_runner(argv, timeout):
            invoked.append((argv, timeout))
            return {"exit_code": 0, "output": "ok"}
        refused = agent.action("manage_service",
                               {"operation":"restart", "service":"xorriso-model"},
                               lambda _: False, runner=fake_runner)
        assert refused["approved"] is False and not invoked
        approved = agent.action("manage_service",
                                {"operation":"restart", "service":"xorriso-model"},
                                lambda _: True, runner=fake_runner)
        assert approved["succeeded"] is True
        assert invoked == [(["pkexec", agent.ADMIN_SERVICE_HELPER,
                             "restart", "xorriso-model.service"], 120)]
    # The real privileged executable must reject arbitrary service names.
    import importlib.util
    helper = pathlib.Path(__file__).with_name("admin-service.py")
    spec = importlib.util.spec_from_file_location("xorriso_admin_service", helper)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    assert mod.checked("restart", "xorriso-model.service") == [
        "/usr/bin/systemctl", "restart", "xorriso-model.service"]
    for args in (("restart", "sddm.service"), ("rm", "xorriso-model.service"),
                 ("restart", "../../etc/shadow")):
        try:
            mod.checked(*args)
            raise AssertionError("Helper accepted unsafe argv")
        except ValueError:
            pass


def test_installer_requires_explicit_live_consent():
    from unittest.mock import patch
    assert agent.is_live_session(kernel_cmdline="BOOT_IMAGE=/live/vmlinuz boot=live quiet")
    assert not agent.is_live_session(kernel_cmdline="BOOT_IMAGE=/boot/vmlinuz quiet")
    assert not agent.is_live_session(kernel_cmdline="boot=livesystem")
    with patch.object(agent, "is_live_session", return_value=False):
        denied = agent.action("open_installer", {}, lambda _: True)
        assert "somente no modo Live" in denied["error"]
    with patch.object(agent, "is_live_session", return_value=True), \
         patch.object(agent, "start_installer") as start:
        assert not agent.action("open_installer", {}, lambda _: False)["approved"]
        assert start.call_count == 0
        start.return_value = {"application": "calamares", "launch_requested": True}
        approved = agent.action("open_installer", {}, lambda _: True)
        assert approved["launch_requested"]
        assert start.call_count == 1


def test_real_http_planning():
    import json
    import threading
    from http.server import BaseHTTPRequestHandler, HTTPServer

    seen = []
    class MockLocalMiniCPM(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            seen.append(body["messages"])
            if len(seen) == 1:
                decision = {"tool":"list_files","args":{}}
            else:
                assert "OBSERVACAO REAL" in body["messages"][-1]["content"]
                decision = {"tool":"finish","message":"A pasta foi consultada."}
            data = json.dumps({"choices":[{"message":{"content":json.dumps(decision)}}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.send_header("Content-Length",str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = HTTPServer(("127.0.0.1", 0), MockLocalMiniCPM)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        endpoint = "http://127.0.0.1:" + str(server.server_port) + "/v1"
        def planner(messages):
            return agent.next_plan(messages, endpoint=endpoint)
        result = agent.solve("Liste meus arquivos", lambda _:False, planner=planner,
                             execute=lambda tool,args,approve:{"files":["a.txt"]})
        assert result["finished"]
        assert len(result["steps"]) == 1
        assert len(seen) == 2
    finally:
        server.shutdown()
        server.server_close()

if __name__ == "__main__":
    test_loop()
    test_denial_stops()
    test_real_file_actions()
    test_package_validation()
    test_install_is_not_shell()
    test_linux_inspection_tools()
    test_nonblocking_file_manager_launch()
    test_safe_terminal_commands()
    test_terminal_mkdir_requires_consent_and_stays_in_documents()
    test_interactive_terminal_requires_approval()
    test_authenticated_admin_service_management()
    test_installer_requires_explicit_live_consent()
    test_real_http_planning()
    print("PASS: multi-etapas, observacao, autorizacao, filesystem, pkexec, comandos sem shell")
