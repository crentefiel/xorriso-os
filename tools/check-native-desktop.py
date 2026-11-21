#!/usr/bin/env python3
"""Gate the xorriso ISO release on *actual* native graphical desktop support.

A passing HTML mock or console-only QEMU test is NOT proof of a graphical ISO.
This check intentionally fails until the real framebuffer program is in source
control, compiled into initramfs and launched by PID 1.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
builder = (root / "build-from-source.sh").read_text()
init = (root / "src/xorriso-gui-init.c").read_text()
failures = []

def require(cond, message):
    if not cond:
        failures.append(message)

native = root / "src/xorriso-desktop.c"
require(native.is_file(),
        "FALTA src/xorriso-desktop.c: o programa grafico da ISO testada nao esta versionado no GitHub.")
require("src/xorriso-desktop.c" in builder and "xorriso-desktop" in builder,
        "FALTA compilar e incluir o desktop nativo na imagem por build-from-source.sh.")
require("xorriso-desktop" in init and "fork" in init,
        "FALTA iniciar o programa grafico de verdade no PID1, com log de falhas.")
require("fb0" in init and "desktop" in init,
        "FALTA suporte/verificacao do framebuffer no inicializador.")
require("gfxterm" in builder and "set gfxpayload=keep" in builder,
        "FALTA configurar a inicializacao grafica/framebuffer no gerador de ISO.")

require((root / "tools/generate-font.py").exists(), "FALTA geracao dos glifos de fonte do desktop.")
require("init-old" in builder and "xorriso-gui-init.c" in builder, "FALTA fallback seguro para o PID1 antigo.")

if failures:
    print("\nXORRISO DESKTOP — PRE-FLIGHT FALHOU: estes itens ainda nao existem no codigo-fonte:")
    for i, message in enumerate(failures, 1):
        print(f"  {i}. {message}")
    print("\nNenhuma ISO deve ser anunciada como grafica enquanto este job falhar.")
    raise SystemExit(1)
print("Desktop grafico versionado e integrado: pre-flight OK.")
