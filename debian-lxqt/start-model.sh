#!/bin/sh
# Start the verified VDI llama-server in a confined, capability-free systemd service.
set -eu
PATH=/usr/bin:/bin
MODEL=/data/models/MiniCPM-V-4_7-1B-Q4_K_M.gguf
PROJECTOR=/data/models/mmproj-model-f16.gguf
SERVER_DISK=/runtime-data/runtime/llama-server
SERVER=/run/xorriso/llama-server
EXPECTED_MODEL=f18f594747e5317ab490cff9c06339c9cfb89acbe2f02ebc48a4e167bc23576d
EXPECTED_SERVER=3e5f1cf566de425ee2d5f0864050f20a14031b37daebe2aa7d638de4389ec2e1
EXPECTED_PROJECTOR=fb9cc047a3cdad5317fd8433a4aeda2d22f00f02ca4bd93b34ad84165b25a900
verify() {
 [ -f "$1" ] || { echo "Arquivo nao encontrado: $1" >&2; exit 2; }
 actual=$(sha256sum "$1")
 actual=${actual%% *}
 [ "$actual" = "$2" ] || { echo "Hash SHA-256 incorreto: $1" >&2; exit 3; }
}
verify "$MODEL" "$EXPECTED_MODEL"
verify "$SERVER_DISK" "$EXPECTED_SERVER"
mkdir -p /run/xorriso
cp "$SERVER_DISK" "$SERVER.tmp"
chmod 500 "$SERVER.tmp"
verify "$SERVER.tmp" "$EXPECTED_SERVER"
mv -f "$SERVER.tmp" "$SERVER"
set -- -m "$MODEL" --host 127.0.0.1 --port 8080 --alias MiniCPM-V-4.7-1B -c 2048 -t 2
if [ -f "$PROJECTOR" ]; then
 verify "$PROJECTOR" "$EXPECTED_PROJECTOR"
 set -- "$@" --mmproj "$PROJECTOR"
fi
echo 'Iniciando MiniCPM local (localhost:8080) com arquivos verificados.'
exec "$SERVER" "$@"
