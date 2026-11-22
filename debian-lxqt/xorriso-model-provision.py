#!/usr/bin/env python3
"""Automatically provision verified LFM2.5-350M GGUFs on the INSTALLED HD.

No shell, no block-device commands, no VDI writes, no root privileges.
Downloads only two pinned-revision official files into systemd StateDirectory.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time
from urllib.parse import quote
from urllib.request import Request, urlopen

REPO = "LiquidAI/LFM2.5-350M-GGUF"
API_ROOT = "https://huggingface.co/api/models/" + REPO
ROOT = Path("/var/lib/xorriso-model")
STATUS = ROOT / "status.json"
MANIFEST = ROOT / "model.json"
MODEL_FILE = "LFM2.5-350M-Q4_K_M.gguf"
REVISION = "bb7ee58b243e4cede04187e323e760b04f8a0091"
PINNED_SHA = "7e6f72643caafc9a68256686638c4d7916f2cec76d1df478d4c3ddcd95a6aed4"
QUANT = {"Q4_K_M": (1.5, MODEL_FILE)}

MIN_FREE_BUFFER = 1024**3
SHA_RE = re.compile(r"^[a-f0-9]{64}$")
COMMIT_RE = re.compile(r"^[a-f0-9]{40}$")

def live(kernel_cmdline=None):
    if kernel_cmdline is None:
        kernel_cmdline = Path("/proc/cmdline").read_text(encoding="utf-8")
    return "boot=live" in kernel_cmdline.split()

def mem_gib(meminfo=None):
    text = meminfo if meminfo is not None else Path("/proc/meminfo").read_text()
    match = re.search(r"^MemTotal:\s+(\d+)\s+kB$", text, re.M)
    if not match:
        raise RuntimeError("Nao foi possivel verificar RAM")
    return int(match.group(1)) * 1024 / 1024**3

def choose_quant(memory):
    if memory >= QUANT["Q4_K_M"][0]:
        return "Q4_K_M", MODEL_FILE
    raise RuntimeError("LFM2.5-350M precisa de pelo menos 1.5 GiB de RAM, prefira 2 GiB ou mais.")


def ensure_destination(path=None):
    if path is None:
        path = ROOT
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        raise RuntimeError("Armazenamento do modelo nao e diretorio confiavel")
    path.mkdir(mode=0o755, parents=True, exist_ok=True)
    if path.is_symlink():
        raise RuntimeError("Pasta de modelos e um link simbolico")

def write_json(target, data):
    # Only writes in our own StateDirectory, never protected VDI volumes.
    temp = target.with_name(target.name + ".tmp")
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o644)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        raise
    os.replace(temp, target)

def set_status(phase, **kwargs):
    write_json(STATUS, {"phase": phase, "model": "LFM2.5-350M",
                        "updated_at": int(time.time()), **kwargs})

def get_json(url):
    req = Request(url, headers={"User-Agent": "xorriso-os-model-provision/0.17"})
    with urlopen(req, timeout=25) as r:
        if r.status != 200:
            raise RuntimeError("Erro de API Hugging Face: " + str(r.status))
        data = r.read(5_000_000)
    return json.loads(data)

def official_files():
    """Only the pinned official LFM2.5-350M GGUF is allowed."""
    items = get_json(API_ROOT + "/tree/" + REVISION + "?blobs=true")
    if not isinstance(items, list):
        raise RuntimeError("Manifesto GGUF invalido")
    for item in items:
        if not isinstance(item, dict) or item.get("path") != MODEL_FILE:
            continue
        size = item.get("size")
        meta = item.get("lfs") or {}
        sha = meta.get("oid") or meta.get("sha256")
        if sha and sha != PINNED_SHA:
            raise RuntimeError("SHA remoto diverge da versao oficial aprovada")
        if not isinstance(size, int) or not 10_000_000 < size < 2_000_000_000:
            raise RuntimeError("Tamanho do arquivo oficial invalido")
        return REVISION, {MODEL_FILE: {"size": size, "sha256": PINNED_SHA}}
    raise RuntimeError("GGUF oficial LFM2.5-350M Q4_K_M nao encontrado")


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(8 * 1024**2), b""):
            digest.update(chunk)
    return digest.hexdigest()

def validated(path, spec):
    return path.is_file() and not path.is_symlink() and spec["sha256"] == PINNED_SHA and \
           path.stat().st_size == spec["size"] and sha256_file(path) == spec["sha256"]

def fetch_verified(name, spec, revision, root=ROOT):
    if name != MODEL_FILE or revision != REVISION or spec["sha256"] != PINNED_SHA:
        raise ValueError("Arquivo de modelo nao aprovado")
    target = root / name
    if validated(target, spec):
        return target
    if target.exists() or target.is_symlink():
        raise RuntimeError("Arquivo local existente com hash divergente: " + name)
    # Partial content is revision- and sha256-specific; no cross-revision reuse.
    part = root / (name + "." + spec["sha256"][:16] + ".part")
    if part.is_symlink():
        raise RuntimeError("Download parcial e um link simbolico")
    previous = part.stat().st_size if part.exists() else 0
    if previous > spec["size"]:
        raise RuntimeError("Download parcial maior que tamanho esperado")
    url = "https://huggingface.co/" + REPO + "/resolve/" + revision + "/" + quote(name)
    headers = {"User-Agent": "xorriso-os-model-provision/0.17"}
    if previous:
        headers["Range"] = "bytes=" + str(previous) + "-"
    with urlopen(Request(url, headers=headers), timeout=80) as response:
        status = response.status
        if previous:
            expected_range = "bytes " + str(previous) + "-"
            if status != 206 or not response.headers.get("Content-Range", "").startswith(expected_range):
                raise RuntimeError("Servidor nao respeitou retomada de download")
        elif status != 200:
            raise RuntimeError("Download do modelo retornou HTTP " + str(status))
        fd = os.open(part, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "ab") as out:
            current = previous
            last_update = time.monotonic()
            while True:
                chunk = response.read(4 * 1024**2)
                if not chunk:
                    break
                out.write(chunk)
                current += len(chunk)
                if current > spec["size"]:
                    raise RuntimeError("Resposta maior que arquivo HF autenticado")
                if time.monotonic() - last_update >= 3:
                    set_status("downloading", file=name, bytes_received=current,
                               bytes_total=spec["size"])
                    last_update = time.monotonic()
    if part.stat().st_size != spec["size"] or sha256_file(part) != spec["sha256"]:
        raise RuntimeError("Falhou validacao SHA-256 do modelo: " + name)
    os.chmod(part, 0o644)
    os.replace(part, target)
    return target

def verified_local_install():
    """Offline reuse only when pinned model and manifest match."""
    if MANIFEST.is_symlink() or not MANIFEST.is_file():
        return False
    try:
        info = json.loads(MANIFEST.read_text(encoding="utf-8"))
        spec = info["files"][MODEL_FILE]
        return (info.get("repo") == REPO and info.get("revision") == REVISION
                and info.get("quant") == "Q4_K_M"
                and set(info["files"]) == {MODEL_FILE}
                and validated(ROOT / MODEL_FILE, spec))
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return False


def provision():
    if live():
        print("Modo Live: o LFM2.5-350M sera instalado automaticamente apos a instalacao no HD.")
        return 0
    ensure_destination()
    memory = mem_gib()
    quant, model_file = choose_quant(memory)
    if verified_local_install():
        set_status("ready", quant=quant, model_file=model_file,
                   memory_gib=round(memory, 1), source="local_verified_cache")
        print("PASS: LFM2.5-350M local verificado; nenhum download necessario.")
        return 0
    set_status("checking", memory_gib=round(memory, 1), quant=quant)
    revision, specs = official_files()
    spec = specs[model_file]
    remaining = 0 if validated(ROOT / model_file, spec) else spec["size"]
    if shutil.disk_usage(ROOT).free < remaining + MIN_FREE_BUFFER:
        raise RuntimeError("Espaco no HD insuficiente para GGUF + 1 GiB de folga")
    set_status("downloading", file=model_file, quant=quant,
               bytes_received=0, bytes_total=spec["size"])
    fetch_verified(model_file, spec, revision)
    write_json(MANIFEST, {"repo": REPO, "revision": revision, "quant": quant,
                          "alias": "LFM2.5-350M", "files": {model_file: spec}})
    set_status("ready", quant=quant, model_file=model_file,
               size_bytes=spec["size"], memory_gib=round(memory, 1))
    print("PASS: LFM2.5-350M oficial instalado no HD e verificado por SHA256.")
    return 0


def main():
    try:
        return provision()
    except Exception as exc:
        try:
            ensure_destination()
            set_status("error", detail=str(exc)[:400])
        except OSError:
            pass
        print("LFM2.5-350M nao provisionado: " + str(exc), file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
