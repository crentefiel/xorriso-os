#!/usr/bin/env python3
"""Build and verify the bundled MiniCPM-V 4.7 1B. Support existing HD caches."""
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

REPO = "openbmb/MiniCPM-V-4.7-1B-gguf"
API_ROOT = "https://huggingface.co/api/models/" + REPO
ROOT = Path("/var/lib/xorriso-model")
BUNDLE = Path("/usr/share/xorriso/models")
STATUS = ROOT / "status.json"
MANIFEST = ROOT / "model.json"
MODEL_FILE = "MiniCPM-V-4_7-1B-Q4_K_M.gguf"
PROJECTOR = "mmproj-model-f16-4x.gguf"
REVISION = "e81247fa2eac0d99e43aeac55da199221959af15"
PINNED_SHA = "f18f594747e5317ab490cff9c06339c9cfb89acbe2f02ebc48a4e167bc23576d"
PROJECTOR_SHA = "1e0ab439877e6896ded59ff24cdd242fdffb236394f6fc4a5b019cbd60bb5f4a"
QUANT = {"Q4_K_M": (2.5, MODEL_FILE)}

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
    raise RuntimeError("MiniCPM-V 4.7 1B precisa de pelo menos 2.5 GiB de RAM, prefira 4 GiB ou mais.")


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
    write_json(STATUS, {"phase": phase, "model": "MiniCPM-V-4.7-1B",
                        "updated_at": int(time.time()), **kwargs})

def get_json(url):
    req = Request(url, headers={"User-Agent": "xorriso-os-model-provision/0.17"})
    with urlopen(req, timeout=25) as r:
        if r.status != 200:
            raise RuntimeError("Erro de API Hugging Face: " + str(r.status))
        data = r.read(5_000_000)
    return json.loads(data)

def official_files():
    """Only the pinned official MiniCPM GGUF and its 4x projector are allowed."""
    items = get_json(API_ROOT + "/tree/" + REVISION + "?blobs=true")
    if not isinstance(items, list):
        raise RuntimeError("Manifesto GGUF invalido")
    wanted = {MODEL_FILE: PINNED_SHA, PROJECTOR: PROJECTOR_SHA}
    found = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        name = item.get("path")
        if name not in wanted:
            continue
        size = item.get("size")
        meta = item.get("lfs") or {}
        sha = meta.get("oid") or meta.get("sha256")
        if sha and sha != wanted[name]:
            raise RuntimeError("SHA remoto diverge da versao oficial aprovada")
        if not isinstance(size, int) or not 10_000_000 < size < 2_000_000_000:
            raise RuntimeError("Tamanho do arquivo oficial invalido")
        found[name] = {"size": size, "sha256": wanted[name]}
    if set(found) != set(wanted):
        raise RuntimeError("GGUF oficial MiniCPM-V 4.7 1B nao encontrado")
    return REVISION, found


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(8 * 1024**2), b""):
            digest.update(chunk)
    return digest.hexdigest()

def validated(path, spec):
    expected = PINNED_SHA if path.name == MODEL_FILE else PROJECTOR_SHA
    return path.is_file() and not path.is_symlink() and spec["sha256"] == expected and \
           path.stat().st_size == spec["size"] and sha256_file(path) == spec["sha256"]

def fetch_verified(name, spec, revision, root=None, report_progress=True):
    expected = PINNED_SHA if name == MODEL_FILE else PROJECTOR_SHA if name == PROJECTOR else ""
    if name not in (MODEL_FILE, PROJECTOR) or revision != REVISION or spec["sha256"] != expected:
        raise ValueError("Arquivo de modelo nao aprovado")
    if root is None:
        root = ROOT
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
                if report_progress and time.monotonic() - last_update >= 3:
                    set_status("downloading", file=name, bytes_received=current,
                               bytes_total=spec["size"])
                    last_update = time.monotonic()
    if part.stat().st_size != spec["size"] or sha256_file(part) != spec["sha256"]:
        raise RuntimeError("Falhou validacao SHA-256 do modelo: " + name)
    os.chmod(part, 0o644)
    os.replace(part, target)
    return target

def verified_local_install(root=None):
    """Accept only the pinned model, size, SHA-256 and matching manifest."""
    if root is None:
        root = ROOT
    manifest = root / "model.json"
    if manifest.is_symlink() or not manifest.is_file():
        return False
    try:
        info = json.loads(manifest.read_text(encoding="utf-8"))
        names = (MODEL_FILE, PROJECTOR)
        return (info.get("repo") == REPO and info.get("revision") == REVISION
                and info.get("quant") == "Q4_K_M"
                and set(info["files"]) == set(names)
                and all(validated(root / name, info["files"][name]) for name in names))
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return False


def model_manifest(specs):
    return {"repo": REPO, "revision": REVISION, "quant": "Q4_K_M",
            "alias": "MiniCPM-V-4.7-1B",
            "files": {name: specs[name] for name in (MODEL_FILE, PROJECTOR)}}


def build_bundle(directory):
    ensure_destination(directory)
    revision, specs = official_files()
    for name in (MODEL_FILE, PROJECTOR):
        fetch_verified(name, specs[name], revision, directory, report_progress=False)
    readme_url = "https://huggingface.co/" + REPO + "/resolve/" + revision + "/README.md"
    with urlopen(readme_url, timeout=45) as response:
        license_text = response.read(256 * 1024).decode("utf-8")
    if "apache-2.0" not in license_text or "MiniCPM" not in license_text:
        raise RuntimeError("Ficha oficial do MiniCPM incompleta")
    (directory / "LICENSE").write_text(license_text, encoding="utf-8")
    write_json(directory / "model.json", model_manifest(specs))
    print("Bundled " + MODEL_FILE + " and " + PROJECTOR)


def provision():
    ensure_destination()
    memory = mem_gib()
    quant, model_file = choose_quant(memory)
    if BUNDLE.exists():
        if not verified_local_install(BUNDLE):
            raise RuntimeError("O modelo incluído na ISO falhou na verificação de integridade")
        set_status("ready", quant=quant, model_file=model_file,
                   memory_gib=round(memory, 1), source="bundled_iso")
        print("PASS: modelo da ISO verificado sem rede.")
        return 0
    if live():
        raise RuntimeError("O modelo incluído na ISO está ausente")
    if verified_local_install():
        set_status("ready", quant=quant, model_file=model_file,
                   memory_gib=round(memory, 1), source="local_verified_cache")
        print("PASS: MiniCPM-V 4.7 1B local verificado; nenhum download necessario.")
        return 0
    set_status("checking", memory_gib=round(memory, 1), quant=quant)
    revision, specs = official_files()
    names = (MODEL_FILE, PROJECTOR)
    remaining = sum(0 if validated(ROOT / name, specs[name]) else specs[name]["size"] for name in names)
    if shutil.disk_usage(ROOT).free < remaining + MIN_FREE_BUFFER:
        raise RuntimeError("Espaco no HD insuficiente para o MiniCPM e o projetor")
    for name in names:
        set_status("downloading", file=name, quant=quant,
                   bytes_received=0, bytes_total=specs[name]["size"])
        fetch_verified(name, specs[name], revision)
    write_json(MANIFEST, model_manifest(specs))
    set_status("ready", quant=quant, model_file=model_file,
               size_bytes=sum(specs[name]["size"] for name in names),
               memory_gib=round(memory, 1))
    print("PASS: MiniCPM-V 4.7 1B oficial instalado no HD e verificado por SHA256.")
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
        print("MiniCPM-V 4.7 1B nao provisionado: " + str(exc), file=sys.stderr)
        return 1

if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--bundle":
        build_bundle(Path(sys.argv[2]))
    elif len(sys.argv) == 1:
        sys.exit(main())
    else:
        sys.exit("Uso: model-provision.py [--bundle DIRETÓRIO]")
