#!/usr/bin/env bash
# Verify real root-command proposals/confirmations using a disposable directory.
# NEVER run these tests against /data or attached disks.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir "$T/run"
export XORRISO_CONF_DIR="$T/run"
export XORRISO_ROOT_EXEC_BIN="$HERE/root-exec.sh"
export XORRISO_AGENT_BIN="$T/mock-agent"
export XORRISO_BUSYBOX_BIN="$(command -v busybox)"
printf '#!/bin/sh\necho "AGENT-ROUTED"\n' > "$XORRISO_AGENT_BIN"
chmod +x "$XORRISO_AGENT_BIN"

ROOT="$HERE/root-exec.sh"
CHAT="$HERE/chat-actions.sh"
COMMAND="printf 'executou de verdade' > '$T/resultado.txt'"
sh "$ROOT" --propose "$COMMAND" > "$T/out"
grep -q 'NAO executou' "$T/out"
test ! -e "$T/resultado.txt"
TOKEN="$(cat "$T/run/root-pending/token")"
test "$(printf '%s' "$TOKEN" | wc -c)" -eq 16

# Model cannot execute by just sending another prompt. Only exact human token.
sh "$CHAT" 'criar uma rotina no Linux' > "$T/out"
grep -q 'AGENT-ROUTED' "$T/out"
test ! -e "$T/resultado.txt"
if sh "$CHAT" 'autorizar 0000000000000000' > "$T/out"; then
 echo 'Accepted wrong root approval token'; exit 50
fi
test ! -e "$T/resultado.txt"
sh "$CHAT" "autorizar $TOKEN" > "$T/out"
grep -q 'Codigo de saida: 0' "$T/out"
test "$(cat "$T/resultado.txt")" = 'executou de verdade'
test ! -e "$T/run/root-pending"
grep -q "APPROVE | $TOKEN" "$T/run/root-audit.log"
grep -q "RESULT | $TOKEN exit=0" "$T/run/root-audit.log"

if sh "$CHAT" "autorizar $TOKEN" > "$T/out"; then
 echo 'Reused root token'; exit 51
fi

# Cancellation does not run a pending command.
sh "$ROOT" --propose "touch '$T/cancelado'" > "$T/out"
TOKEN="$(cat "$T/run/root-pending/token")"
sh "$CHAT" "cancelar $TOKEN" > "$T/out"
test ! -e "$T/cancelado"
test ! -d "$T/run/root-pending"

# Expiration invalidates the token.
sh "$ROOT" --propose "touch '$T/expirado'" > "$T/out"
TOKEN="$(cat "$T/run/root-pending/token")"
echo 1 > "$T/run/root-pending/created"
if sh "$CHAT" "autorizar $TOKEN" > "$T/out"; then
 echo 'Accepted expired root token'; exit 52
fi
grep -q 'expirou' "$T/out"
test ! -e "$T/expirado"

# No silent replacement of pending proposal.
sh "$ROOT" --propose "touch '$T/um'" > "$T/out"
if sh "$ROOT" --propose "touch '$T/dois'" > "$T/out"; then
 echo 'Replaced unapproved command'; exit 53
fi
test ! -e "$T/dois"
TOKEN="$(cat "$T/run/root-pending/token")"
sh "$CHAT" "cancelar $TOKEN" > "$T/out"

# Newlines hide additional commands in previews, so proposals reject them.
if sh "$ROOT" --propose "$(printf 'true\nfalse')" > "$T/out"; then
 echo 'Accepted multi-line command'; exit 54
fi
sh "$ROOT" --status > "$T/out"
grep -q 'Nenhum comando root pendente' "$T/out"
echo 'PASS: human-approved real Linux root commands, logs, cancel, expiry, no replay'
