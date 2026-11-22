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

if __name__ == "__main__":
    test_loop()
    test_denial_stops()
    test_real_file_actions()
    test_package_validation()
    test_install_is_not_shell()
    print("PASS: multi-etapas, observacao, autorizacao, filesystem, pkexec, comandos sem shell")
