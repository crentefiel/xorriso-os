#!/usr/bin/env python3
"""Polkit-authenticated, audited service operations. No root shell."""
import os
import subprocess
import sys
import syslog

ALLOWED = {"xorriso-model.service", "xorriso-volumes.service",
           "NetworkManager.service"}
OPERATIONS = {"start", "stop", "restart", "enable", "disable"}

def checked(operation, service):
    if operation not in OPERATIONS or service not in ALLOWED:
        raise ValueError("Servico ou operacao administrativa nao autorizada")
    return ["/usr/bin/systemctl", operation, service]

def main():
    if os.geteuid() != 0:
        print("Autenticacao administrativa via PolicyKit obrigatoria.", file=sys.stderr)
        return 3
    if len(sys.argv) != 3:
        print("Uso: admin-service OPERACAO SERVICO", file=sys.stderr)
        return 2
    try:
        command = checked(sys.argv[1], sys.argv[2])
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    syslog.openlog("xorriso-admin-service", syslog.LOG_PID, syslog.LOG_AUTH)
    syslog.syslog(syslog.LOG_NOTICE, "Operacao administrativa: " +
                  sys.argv[1] + " " + sys.argv[2])
    result = subprocess.run(command, timeout=90, check=False,
                            stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, env={"PATH": "/usr/bin:/bin"})
    print((result.stdout or "")[:3000], end="")
    probe = "is-enabled" if sys.argv[1] in {"enable", "disable"} else "is-active"
    verification = subprocess.run(["/usr/bin/systemctl", probe, sys.argv[2]],
                                  capture_output=True, text=True, timeout=12)
    print("Verificacao " + probe + ": " + verification.stdout.strip())
    syslog.syslog(syslog.LOG_NOTICE if result.returncode == 0 else syslog.LOG_WARNING,
                  "Resultado " + str(result.returncode) + ": " + sys.argv[2])
    return result.returncode

if __name__ == "__main__":
    sys.exit(main())
