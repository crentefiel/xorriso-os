#!/bin/sh
# xorriso desktop: every user message is interpreted by the configured LLM.
# No hard-coded sentence patterns or folder names in the desktop entrypoint.
# The model selects a typed action; a separate executor validates and performs it.
set -eu
PATH=/bin:/usr/bin:/sbin
AGENT=${XORRISO_AGENT_BIN:-/usr/lib/xorriso/ai-agent.sh}
input=${1:-}
[ -n "$input" ] || { echo 'Escreva um pedido para a IA.'; exit 2; }
exec /bin/sh "$AGENT" "$input"
