#!/usr/bin/env python3
"""Verify and run the text-only LiquidAI LFM2.5-350M GGUF on localhost."""
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT=Path("/var/lib/xorriso-model")
BUNDLE=Path("/usr/share/xorriso/models")
BINARY=Path("/opt/xorriso/llama-server")
MODEL_FILE="LFM2.5-350M-Q4_K_M.gguf"
REPO="LiquidAI/LFM2.5-350M-GGUF"
REVISION="bb7ee58b243e4cede04187e323e760b04f8a0091"
PINNED_SHA="7e6f72643caafc9a68256686638c4d7916f2cec76d1df478d4c3ddcd95a6aed4"

def sha256(path):
    h=hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8*1024*1024),b""):
            h.update(chunk)
    return h.hexdigest()

def select_files(info, root=None):
    if info.get("repo")!=REPO or info.get("revision")!=REVISION:
        raise ValueError("Repositorio/revisao de modelo nao autorizados")
    if info.get("quant")!="Q4_K_M" or not isinstance(info.get("files"),dict):
        raise ValueError("Quantizacao/manifesto nao autorizados")
    if set(info["files"])!={MODEL_FILE}:
        raise ValueError("O modelo deve conter somente um GGUF oficial")
    spec=info["files"][MODEL_FILE]
    path=(ROOT if root is None else root)/MODEL_FILE
    if (path.is_symlink() or not path.is_file() or
        not isinstance(spec.get("size"),int) or
        spec.get("sha256")!=PINNED_SHA or
        path.stat().st_size!=spec["size"] or
        sha256(path)!=PINNED_SHA):
        raise ValueError("GGUF nao verificado ou corrompido")
    return path

def thread_count():
    try:
        n = os.cpu_count() or 2
    except Exception:
        n = 2
    # Leave one core free when possible; cap at 8 for small models.
    return str(max(1, min(n - 1 if n > 2 else n, 8)))

def main():
    if not BINARY.is_file() or not os.access(str(BINARY),os.X_OK):
        raise RuntimeError("Motor llama-server nao incluido na ISO")
    root=BUNDLE if BUNDLE.exists() else ROOT
    manifest=root/"model.json"
    if manifest.is_symlink() or not manifest.is_file():
        raise RuntimeError("Manifesto local do LFM2.5-350M ausente")
    model=select_files(json.loads(manifest.read_text(encoding="utf-8")), root)
    threads = thread_count()
    os.execv(str(BINARY),[str(BINARY),"-m",str(model),
              "--host","127.0.0.1","--port","8080",
              "--alias","LFM2.5-350M","--ctx-size","2048",
              "-t",threads,"-ngl","0","--mlock"])

if __name__=="__main__":
    try:
        main()
    except Exception as exc:
        print("xorriso-model: "+str(exc),file=sys.stderr)
        sys.exit(1)
