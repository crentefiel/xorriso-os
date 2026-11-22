#!/bin/sh
# Start the locally provisioned 35B model as the unprivileged model user.
# The real weight SHA-256 is checked during download; do not run from a VDI.
set -eu
EXPECTED_MODEL=MiniCPM-V-4_7-35B-A3B
export XORRISO_EXPECTED_MODEL="$EXPECTED_MODEL"
exec /usr/bin/python3 /usr/local/libexec/xorriso/run-model.py
