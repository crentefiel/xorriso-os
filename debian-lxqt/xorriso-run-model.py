#!/usr/bin/env python3
"""Load SHA256-verified local MiniCPM V 4.7 1B in an isolated llama-server."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path("/var/lib/xorriso-model")
MANIFEST = ROOT / "model.json"
BINARY = Path("/opt/xorriso/llama-server")
MODEL = {"Q4_K_M": "MiniCPM-V-4_7-1B-Q4_K_M.gguf"}
PROJECTOR = "mmproj-model-f16-4x.gguf"
REPO = "openbmb/MiniCPM-V-4.7-1B-gguf"

def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(8 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def select_files(manifest):
    if manifest.get("repo") != REPO:
        raise ValueError("Repositorio de modelo incorreto")
    quant = manifest.get("quant")
    if quant not in MODEL or not re.fullmatch("[a-f0-9]{40}", manifest.get("revision", "")):
        raise ValueError("Manifesto da IA nao autenticado")
    expected = {MODEL[quant], PROJECTOR}
    files = manifest.get("files", {})
    if not isinstance(files, dict) or set(files) != expected:
        raise ValueError("Arquivos esperados nao coincidem com o manifesto")
    for name in expected:
        file = ROOT / name
        spec = files[name]
        if (file.is_symlink() or not file.is_file() or
                not isinstance(spec.get("size"), int) or
                not isinstance(spec.get("sha256"), str) or
                not re.fullmatch("[a-f0-9]{64}", spec["sha256"]) or
                file.stat().st_size != spec["size"] or
                sha256(file) != spec["sha256"]):
            raise ValueError("GGUF invalido/corrompido: " + name)
    return ROOT / MODEL[quant], ROOT / PROJECTOR

def main():
    if not BINARY.is_file() or not os.access(str(BINARY), os.X_OK):
        raise RuntimeError("Motor llama-server nao instalado na ISO")
    if MANIFEST.is_symlink() or not MANIFEST.is_file():
        raise RuntimeError("Modelo ainda nao provisionado")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    model, projector = select_files(manifest)
    os.execv(str(BINARY), [str(BINARY), "-m", str(model),
                          "--mmproj", str(projector),
                          "--host", "127.0.0.1", "--port", "8080",
                          "--alias", "MiniCPM-V-4.7-1B",
                          "--ctx-size", "2048", "-t", "4",
                          "-ngl", "0"])

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("xorriso-model: " + str(exc), file=sys.stderr)
        sys.exit(1)
