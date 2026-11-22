#!/usr/bin/env python3
"""Privileged, narrow pkexec entry point. NOT an arbitrary shell."""
import os
import re
import subprocess
import sys

PACKAGE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+._-]{0,79}$")

def main():
    if os.geteuid() != 0:
        print("Este instalador exige autenticacao de administrador via pkexec.", file=sys.stderr)
        return 3
    if len(sys.argv) != 2 or not PACKAGE.fullmatch(sys.argv[1]):
        print("Uso: admin-package NOME_DE_PACOTE", file=sys.stderr)
        return 2
    name = sys.argv[1]
    if name.startswith("-"):
        return 2
    # Absolute executable, argument array, no sh -c, no sudo NOPASSWD.
    print("Instalando pacote solicitado: " + name, flush=True)
    result = subprocess.run(
        ["/usr/bin/apt-get", "install", "-y", "--no-install-recommends", "--", name],
        stdin=subprocess.DEVNULL, timeout=175, check=False
    )
    if result.returncode != 0:
        return result.returncode
    installed = subprocess.run(["/usr/bin/dpkg-query", "-W", "-f=${Status}", name],
                               capture_output=True, text=True, timeout=10)
    if installed.returncode != 0 or "install ok installed" not in installed.stdout:
        print("apt-get terminou, mas o pacote nao foi verificado.", file=sys.stderr)
        return 4
    print("Pacote instalado e verificado: " + name)
    return 0

if __name__ == "__main__":
    sys.exit(main())
