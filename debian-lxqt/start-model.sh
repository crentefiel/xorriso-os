#!/bin/sh
# Start the locally provisioned LFM2.5-350M model as the unprivileged model user.
# The real weight SHA-256 is checked during download; do not run from a VDI.
set -eu
EXPECTED_MODEL=LFM2.5-350M
export XORRISO_EXPECTED_MODEL="$EXPECTED_MODEL"
exec /usr/bin/python3 /usr/local/libexec/xorriso/run-model.py
