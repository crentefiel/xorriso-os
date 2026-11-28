#!/usr/bin/env python3
"""Verify and run the bundled MiniCPM-V 4.7 1B on localhost."""
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT=Path("/var/lib/xorriso-model")
BUNDLE=Path("/usr/share/xorriso/models")
BINARY=Path("/opt/xorriso/llama-server")
MODEL_FILE="MiniCPM-V-4_7-1B-Q4_K_M.gguf"
PROJECTOR="mmproj-model-f16-4x.gguf"
REPO="openbmb/MiniCPM-V-4.7-1B-gguf"
REVISION="e81247fa2eac0d99e43aeac55da199221959af15"
PINNED_SHA="f18f594747e5317ab490cff9c06339c9cfb89acbe2f02ebc48a4e167bc23576d"
PROJECTOR_SHA="1e0ab439877e6896ded59ff24cdd242fdffb236394f6fc4a5b019cbd60bb5f4a"

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
    if set(info["files"])!={MODEL_FILE, PROJECTOR}:
        raise ValueError("O MiniCPM precisa do GGUF oficial e do projetor 4x")
    base=ROOT if root is None else root
    paths=[]
    for name, pin in ((MODEL_FILE, PINNED_SHA), (PROJECTOR, PROJECTOR_SHA)):
        spec=info["files"][name]
        path=base/name
        if (path.is_symlink() or not path.is_file() or
            not isinstance(spec.get("size"),int) or
            spec.get("sha256")!=pin or
            path.stat().st_size!=spec["size"] or
            sha256(path)!=pin):
            raise ValueError("GGUF nao verificado ou corrompido")
        paths.append(path)
    return tuple(paths)

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
        raise RuntimeError("Manifesto local do MiniCPM-V 4.7 1B ausente")
    model, projector=select_files(json.loads(manifest.read_text(encoding="utf-8")), root)
    threads = thread_count()
    # --jinja applies the chat template stored in the GGUF. The root file
    # keeps thinking disabled, so the reply stays in message.content.
    os.execv(str(BINARY),[str(BINARY),"-m",str(model),
              "--mmproj",str(projector),
              "--host","127.0.0.1","--port","8080",
              "--alias","MiniCPM-V-4.7-1B","--ctx-size","2048",
              "-t",threads,"-ngl","0","-n","160",
              "--jinja","--reasoning","off",
              "--temp","0.4","--top-k","40","--repeat-penalty","1.2"])

if __name__=="__main__":
    try:
        main()
    except Exception as exc:
        print("xorriso-model: "+str(exc),file=sys.stderr)
        sys.exit(1)
