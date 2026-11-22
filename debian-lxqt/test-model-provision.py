#!/usr/bin/env python3
"""Offline LFM2.5-350M install and safety regression tests."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
from unittest.mock import patch
BASE=Path(__file__).resolve().parent

def load(name,file):
    spec=importlib.util.spec_from_file_location(name,BASE/file)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
download=load("lfm25_download","xorriso-model-provision.py")
runtime=load("lfm25_runtime","xorriso-run-model.py")

def main():
    assert download.REPO == runtime.REPO == "LiquidAI/LFM2.5-350M-GGUF"
    assert download.REVISION == runtime.REVISION
    assert download.PINNED_SHA == runtime.PINNED_SHA
    assert download.MODEL_FILE == runtime.MODEL_FILE
    assert download.choose_quant(2.0)==("Q4_K_M",download.MODEL_FILE)
    assert download.live("boot=live quiet") and not download.live("root=UUID=test")
    try:
        download.choose_quant(1.0)
        raise AssertionError("RAM check missing")
    except RuntimeError:
        pass
    with tempfile.TemporaryDirectory() as d:
        root=Path(d)
        download.ROOT=root
        download.STATUS=root/"status.json"
        download.MANIFEST=root/"model.json"
        runtime.ROOT=root
        runtime.MANIFEST=root/"model.json"
        body=b"synthetic small test GGUF"
        digest=hashlib.sha256(body).hexdigest()
        download.PINNED_SHA=runtime.PINNED_SHA=digest
        (root/download.MODEL_FILE).write_bytes(body)
        manifest={"repo":download.REPO,"revision":download.REVISION,
                  "quant":"Q4_K_M","alias":"LFM2.5-350M",
                  "files":{download.MODEL_FILE:{"size":len(body),"sha256":digest}}}
        download.write_json(download.MANIFEST,manifest)
        assert download.verified_local_install()
        assert runtime.select_files(manifest)==root/download.MODEL_FILE
        with patch.object(download,"live",return_value=False), \
             patch.object(download,"mem_gib",return_value=2.0), \
             patch.object(download,"official_files",side_effect=AssertionError("internet")):
            assert download.provision()==0
        assert json.loads(download.STATUS.read_text())["phase"]=="ready"
        (root/download.MODEL_FILE).write_bytes(b"corrupt")
        assert not download.verified_local_install()
        try:
            runtime.select_files(manifest)
            raise AssertionError("Tampered GGUF accepted")
        except ValueError:
            pass
    download.PINNED_SHA="7e6f72643caafc9a68256686638c4d7916f2cec76d1df478d4c3ddcd95a6aed4"
    with patch.object(download,"get_json",return_value=[
        {"path":download.MODEL_FILE,"size":229000000,"lfs":{"oid":"f"*64}}
    ]):
        try:
            download.official_files()
            raise AssertionError("Remote hash mismatch accepted")
        except RuntimeError:
            pass
    with patch.object(download,"get_json",return_value=[
        {"path":download.MODEL_FILE,"size":229000000}
    ]):
        revision,files=download.official_files()
        assert revision==download.REVISION
        assert files[download.MODEL_FILE]["sha256"]==download.PINNED_SHA
    assert "--mmproj" not in (BASE/"xorriso-run-model.py").read_text()
    print("PASS: LFM2.5-350M SHA256, offline reuse, RAM and no vision projector")

if __name__=="__main__":
    main()
