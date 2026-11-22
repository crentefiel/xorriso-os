#!/usr/bin/env python3
"""Provision verified MiniCPM-V 4.7 35B-A3B GGUFs on the INSTALLED HD.

No shell, no block-device commands, no VDI writes, no root privileges.
Downloads only two pinned-revision official files into systemd StateDirectory.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import quote
from urllib.request import Request, urlopen

REPO = "openbmb/MiniCPM-V-4.7-35B-A3B-gguf"
API_ROOT = "https://huggingface.co/api/models/" + REPO
ROOT = Path("/var/lib/xorriso-model")
STATUS = ROOT / "status.json"
MANIFEST = ROOT / "model.json"
PROJECTOR = "mmproj-model-f16.gguf"
QUANT = {
    # (system RAM in GiB, file name) — model is 35B in both variants.
    "Q4_K_M": (32, "MiniCPM-V-4_7-35B-A3B-Q4_K_M.gguf"),
    "IQ3_XS": (20, "MiniCPM-V-4_7-35B-A3B-IQ3_XS.gguf"),
}
MIN_FREE_BUFFER = 5 * 1024**3
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
        return "Q4_K_M", QUANT["Q4_K_M"][1]
    if memory >= QUANT["IQ3_XS"][0]:
        return "IQ3_XS", QUANT["IQ3_XS"][1]
    raise RuntimeError(
        "O MiniCPM-V 4.7 35B-A3B precisa de cerca de 20 GiB de RAM "
        "na quantizacao menor, ou 32 GiB para Q4_K_M. "
        "Nao e possivel iniciar o 35B nesta maquina com seguranca.")

def protected_connected(runner=subprocess.run):
    proc = runner(["/usr/bin/lsblk", "-rno", "LABEL"],
                  capture_output=True, text=True, check=False, timeout=12)
    if proc.returncode:
        raise RuntimeError("Nao foi possivel identificar os discos")
    return bool({"XORRISO_DATA", "XORRISO_RUNTIME"} & set(proc.stdout.splitlines()))

def ensure_destination(path=ROOT):
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
    write_json(STATUS, {"phase": phase, "model": "MiniCPM-V-4.7-35B-A3B",
                        "updated_at": int(time.time()), **kwargs})

def get_json(url):
    req = Request(url, headers={"User-Agent": "xorriso-os-model-provision/0.17"})
    with urlopen(req, timeout=25) as r:
        if r.status != 200:
            raise RuntimeError("Erro de API Hugging Face: " + str(r.status))
        data = r.read(5_000_000)
    return json.loads(data)

def official_files():
    info = get_json(API_ROOT)
    commit = info.get("sha", "")
    if not COMMIT_RE.fullmatch(commit):
        raise RuntimeError("Hugging Face nao retornou revisao confiavel")
    # blobs=true includes LFS sha256 and exact sizes for this pinned revision.
    files = get_json(API_ROOT + "/tree/" + commit + "?blobs=true")
    if not isinstance(files, list):
        raise RuntimeError("Manifesto de arquivos HF invalido")
    specs = {}
    for item in files:
        name = item.get("path", "")
        meta = item.get("lfs", {})
        digest = meta.get("oid", "") or meta.get("sha256", "")
        size = item.get("size")
        if (name in {PROJECTOR, QUANT["Q4_K_M"][1], QUANT["IQ3_XS"][1]}
                and isinstance(size, int) and size > 10_000_000
                and SHA_RE.fullmatch(digest)):
            specs[name] = {"sha256": digest, "size": size}
    return commit, specs

def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(8 * 1024**2), b""):
            digest.update(chunk)
    return digest.hexdigest()

def validated(path, spec):
    return path.is_file() and not path.is_symlink() and \
           path.stat().st_size == spec["size"] and sha256_file(path) == spec["sha256"]

def fetch_verified(name, spec, revision, root=ROOT):
    if name not in {PROJECTOR, QUANT["Q4_K_M"][1], QUANT["IQ3_XS"][1]}:
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

def provision():
    if live():
        print("Modo Live: download de dezenas de GB desativado, instale no HD primeiro.")
        return 0
    if protected_connected():
        raise RuntimeError("VDIs protegidos detectados: desconecte-os para provisionar no HD")
    ensure_destination()
    memory = mem_gib()
    quant, model_file = choose_quant(memory)
    set_status("checking", memory_gib=round(memory, 1), quant=quant)
    commit, specs = official_files()
    for name in (model_file, PROJECTOR):
        if name not in specs:
            raise RuntimeError("Arquivo GGUF ausente no repo oficial: " + name)
    total = sum(specs[name]["size"] for name in (model_file, PROJECTOR))
    # Existing verified files count toward capacity. Do not download into Live.
    remaining = sum(0 if validated(ROOT / name, specs[name]) else specs[name]["size"]
                    for name in (model_file, PROJECTOR))
    if shutil.disk_usage(ROOT).free < remaining + MIN_FREE_BUFFER:
        raise RuntimeError("Espaco livre insuficiente no HD. Requer aproximadamente "
                           + str((remaining + MIN_FREE_BUFFER) // 1024**3 + 1) + " GiB.")
    for name in (model_file, PROJECTOR):
        set_status("downloading", file=name, quant=quant,
                   bytes_received=0, bytes_total=specs[name]["size"])
        fetch_verified(name, specs[name], commit)
    manifest = {"repo": REPO, "revision": commit, "quant": quant,
                "alias": "MiniCPM-V-4.7-35B-A3B", "files": {
                    name: {"sha256": specs[name]["sha256"], "size": specs[name]["size"]}
                    for name in (model_file, PROJECTOR)}}
    write_json(MANIFEST, manifest)
    set_status("ready", quant=quant, model_file=model_file,
               size_bytes=total, memory_gib=round(memory, 1))
    print("PASS: modelo 35B-A3B GGUF e mmproj oficiais verificados.")
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
        print("MiniCPM nao provisionado: " + str(exc), file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
