#!/bin/sh
# xorriso native desktop entrypoint.
# User requests go to the configured LLM; only the HUMAN confirms root proposals.
set -eu
PATH=/bin:/usr/bin:/sbin
AGENT=${XORRISO_AGENT_BIN:-/usr/lib/xorriso/ai-agent.sh}
ROOT_EXEC=${XORRISO_ROOT_EXEC_BIN:-/usr/lib/xorriso/root-exec.sh}
input=${1:-}
[ -n "$input" ] || { echo 'Escreva um pedido para a IA.'; exit 2; }
case "$input" in
 'desliga o sistema'|'desligue o sistema'|'desligar o sistema'|'desliga o computador'|'desligue o computador'|'desligar o computador')
  # Never report a shutdown that did not happen. Proposal requires human approval.
  exec /bin/sh "$ROOT_EXEC" --propose '/bin/busybox poweroff -f' ;;
 'autorizar '*)
  # This branch is only entered for literal text typed by the user.
  exec /bin/sh "$ROOT_EXEC" "--approve:${input#autorizar }" ;;
 'cancelar '*)
  exec /bin/sh "$ROOT_EXEC" "--cancel:${input#cancelar }" ;;
 'comando pendente'|'ver comando pendente')
  exec /bin/sh "$ROOT_EXEC" --status ;;
esac
# LLM responses cannot invoke approval; they only propose commands to review.
exec /bin/sh "$AGENT" "$input"
