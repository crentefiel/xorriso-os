#!/usr/bin/env python3
"""Offline MiniCPM-V 4.7 1B install and safety regression tests."""
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
download=load("minicpm_download","xorriso-model-provision.py")
runtime=load("minicpm_runtime","xorriso-run-model.py")

def main():
    assert download.REPO == runtime.REPO == "openbmb/MiniCPM-V-4.7-1B-gguf"
    assert download.REVISION == runtime.REVISION
    assert download.PINNED_SHA == runtime.PINNED_SHA
    assert download.PROJECTOR_SHA == runtime.PROJECTOR_SHA
    assert download.MODEL_FILE == runtime.MODEL_FILE
    assert download.PROJECTOR == runtime.PROJECTOR
    assert download.choose_quant(4.0)==("Q4_K_M",download.MODEL_FILE)
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
        download.BUNDLE=root/"bundle"
        body=b"synthetic small test GGUF"
        digest=hashlib.sha256(body).hexdigest()
        download.PINNED_SHA=runtime.PINNED_SHA=digest
        download.PROJECTOR_SHA=runtime.PROJECTOR_SHA=digest
        (root/download.MODEL_FILE).write_bytes(body)
        (root/download.PROJECTOR).write_bytes(body)
        file_spec={"size":len(body),"sha256":digest}
        manifest={"repo":download.REPO,"revision":download.REVISION,
                  "quant":"Q4_K_M","alias":"MiniCPM-V-4.7-1B",
                  "files":{download.MODEL_FILE:file_spec, download.PROJECTOR:file_spec}}
        download.write_json(download.MANIFEST,manifest)
        assert download.verified_local_install()
        assert runtime.select_files(manifest)==(root/download.MODEL_FILE, root/download.PROJECTOR)
        with patch.object(download,"live",return_value=False), \
             patch.object(download,"mem_gib",return_value=4.0), \
             patch.object(download,"official_files",side_effect=AssertionError("internet")):
            assert download.provision()==0
        assert json.loads(download.STATUS.read_text())["phase"]=="ready"
        download.BUNDLE.mkdir()
        (download.BUNDLE/download.MODEL_FILE).write_bytes(body)
        (download.BUNDLE/download.PROJECTOR).write_bytes(body)
        download.write_json(download.BUNDLE/"model.json", manifest)
        for is_live in (True, False):
            with patch.object(download,"live",return_value=is_live), \
                 patch.object(download,"mem_gib",return_value=4.0), \
                 patch.object(download,"official_files",side_effect=AssertionError("internet")):
                assert download.provision()==0
            assert json.loads(download.STATUS.read_text())["source"]=="bundled_iso"
            assert runtime.select_files(manifest, download.BUNDLE)==(
                download.BUNDLE/download.MODEL_FILE, download.BUNDLE/download.PROJECTOR)
        (download.BUNDLE/download.MODEL_FILE).write_bytes(b"damaged")
        with patch.object(download,"mem_gib",return_value=4.0), \
             patch.object(download,"official_files",side_effect=AssertionError("internet")):
            try:
                download.provision()
                raise AssertionError("Corrupt bundled model accepted")
            except RuntimeError:
                pass
        (root/download.MODEL_FILE).write_bytes(b"corrupt")
        assert not download.verified_local_install()
        try:
            runtime.select_files(manifest)
            raise AssertionError("Tampered GGUF accepted")
        except ValueError:
            pass
    download.PINNED_SHA="f18f594747e5317ab490cff9c06339c9cfb89acbe2f02ebc48a4e167bc23576d"
    download.PROJECTOR_SHA="1e0ab439877e6896ded59ff24cdd242fdffb236394f6fc4a5b019cbd60bb5f4a"
    with patch.object(download,"get_json",return_value=[
        {"path":download.MODEL_FILE,"size":672003680,"lfs":{"oid":"f"*64}},
        {"path":download.PROJECTOR,"size":901033888,"lfs":{"oid":download.PROJECTOR_SHA}},
    ]):
        try:
            download.official_files()
            raise AssertionError("Remote hash mismatch accepted")
        except RuntimeError:
            pass
    with patch.object(download,"get_json",return_value=[
        {"path":download.MODEL_FILE,"size":672003680},
        {"path":download.PROJECTOR,"size":901033888},
    ]):
        revision,files=download.official_files()
        assert revision==download.REVISION
        assert files[download.MODEL_FILE]["sha256"]==download.PINNED_SHA
        assert files[download.PROJECTOR]["sha256"]==download.PROJECTOR_SHA
    assert "--mmproj" in (BASE/"xorriso-run-model.py").read_text()
    print("PASS: MiniCPM-V 4.7 1B SHA256, offline reuse, RAM and projector")

if __name__=="__main__":
    main()
