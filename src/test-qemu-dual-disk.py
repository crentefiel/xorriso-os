#!/usr/bin/env python3
"""CI: preserve GGUF data on /data while mounting a distinct read-only runtime VDI."""
from pathlib import Path
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/"dist"
DATA=OUT/"qemu-two-data.raw"
RUNTIME=OUT/"qemu-two-runtime.raw"

def cmd(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)

def make_img(path,label,dir_name,filename,payload):
    path.unlink(missing_ok=True)
    cmd("truncate","-s","96M",str(path))
    cmd("mkfs.ext4","-F","-q","-L",label,str(path))
    temp=OUT/("ci-fixture-"+label+".txt")
    temp.write_text(payload)
    try:
        cmd("debugfs","-w","-R","mkdir /"+dir_name,str(path))
        cmd("debugfs","-w","-R",
            "write "+str(temp)+" /"+dir_name+"/"+filename,str(path))
    finally:
        temp.unlink(missing_ok=True)

def boot(stage):
    log=OUT/("qemu-dual-"+stage+".log")
    log.unlink(missing_ok=True)
    qemu=["qemu-system-x86_64","-m","1024","-smp","1",
          "-display","none","-no-reboot","-monitor","none",
          "-serial","file:"+str(log),"-nic","none",
          "-kernel",str(OUT/"vmlinuz"),"-initrd",str(OUT/"initramfs.cpio.gz"),
          "-append","console=ttyS0 loglevel=1 rdinit=/init xorriso.ci=dual-"+stage,
          "-device","ich9-ahci,id=sata",
          "-drive","file="+str(DATA)+",format=raw,if=none,id=datadisk",
          "-device","ide-hd,drive=datadisk,bus=sata.0",
          "-drive","file="+str(RUNTIME)+",format=raw,if=none,id=runtimedisk",
          "-device","ide-hd,drive=runtimedisk,bus=sata.1"]
    proc=subprocess.Popen(qemu,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        deadline=time.monotonic()+65
        while time.monotonic()<deadline:
            if proc.poll() is not None:
                raise RuntimeError("QEMU exited before check")
            data=log.read_text(errors="replace") if log.exists() else ""
            if "xorriso: dual volume "+stage+" PASS" in data:
                assert "Disco de modelos montado em /data" in data
                assert "Disco de runtime montado em /runtime-data" in data
                print("PASS: two SATA disks mounted; runtime read-only; "+stage,flush=True)
                return
            if "xorriso: dual volume FAIL" in data:
                raise RuntimeError("Guest rejected volumes: "+data[-3000:])
            time.sleep(.5)
        raise RuntimeError("Timeout: "+(log.read_text(errors="replace")[-4000:] if log.exists() else "no boot"))
    finally:
        proc.terminate()
        try: proc.wait(timeout=5)
        except subprocess.TimeoutExpired: proc.kill();proc.wait()

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    make_img(DATA,"XORRISO_DATA","models","ci-weight.txt","MODEL_STAYS\n")
    make_img(RUNTIME,"XORRISO_RUNTIME","runtime","llama-server","RUNTIME_SEPARATE\n")
    boot("write")
    boot("read")
    print("PASS: GGUF volume preserved across reboot with independently attached runtime")

if __name__=="__main__":
    try:main()
    except Exception as exc:
        print("FAIL:",exc,file=sys.stderr)
        sys.exit(1)
