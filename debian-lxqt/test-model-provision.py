#!/usr/bin/env python3
"""No-network tests of official 1B auto-provision and verified execution."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
from unittest.mock import patch

BASE = Path(__file__).resolve().parent

def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, BASE / filename)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj

download = load("xorriso_provision_test", "xorriso-model-provision.py")
runtime = load("xorriso_runtime_test", "xorriso-run-model.py")

def main():
    assert download.REPO == "openbmb/MiniCPM-V-4.7-1B-gguf"
    assert download.PROJECTOR == "mmproj-model-f16-4x.gguf"
    assert download.choose_quant(4.0) == (
        "Q4_K_M", "MiniCPM-V-4_7-1B-Q4_K_M.gguf")
    assert download.live("quiet boot=live username=xorriso")
    assert not download.live("root=UUID=test quiet")
    try:
        download.choose_quant(1.5)
    except RuntimeError:
        pass
    else:
        raise AssertionError("Low-memory machine must get actionable error")

    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        download.ROOT = root
        download.STATUS = root / "status.json"
        download.MANIFEST = root / "model.json"
        runtime.ROOT = root
        runtime.MANIFEST = root / "model.json"
        payload = {
            download.QUANT["Q4_K_M"][1]: b"gguf-model-test-content",
            download.PROJECTOR: b"gguf-projector-test-content",
        }
        specs = {}
        for name, content in payload.items():
            (root / name).write_bytes(content)
            specs[name] = {"size": len(content), "sha256":
                           hashlib.sha256(content).hexdigest()}
        manifest = {"repo": download.REPO, "revision": "a" * 40,
                    "quant": "Q4_K_M", "alias": "MiniCPM-V-4.7-1B",
                    "files": specs}
        download.write_json(download.MANIFEST, manifest)
        assert download.verified_local_install()
        model, mmproj = runtime.select_files(manifest)
        assert model.name == download.QUANT["Q4_K_M"][1]
        assert mmproj.name == download.PROJECTOR
        # Installed boot must NOT reach Hugging Face when files are verified.
        with patch.object(download, "live", return_value=False), \
             patch.object(download, "mem_gib", return_value=4.0), \
             patch.object(download, "official_files",
                          side_effect=AssertionError("Unnecessary online API")):
            assert download.provision() == 0
        assert json.loads(download.STATUS.read_text())["phase"] == "ready"
        # Tampering is detected, not silently accepted as an installed model.
        (root / model.name).write_bytes(b"tampered")
        assert not download.verified_local_install()
        try:
            runtime.select_files(manifest)
        except ValueError:
            pass
        else:
            raise AssertionError("Tampered GGUF was accepted")

    assert runtime.REPO == "openbmb/MiniCPM-V-4.7-1B-gguf"
    assert "35B" not in (BASE / "xorriso-model-provision.py").read_text()
    assert "35B" not in (BASE / "xorriso-run-model.py").read_text()
    print("PASS: first installed boot downloads 1B, offline reuse, SHA256 and RAM safety")

if __name__ == "__main__":
    main()
