#!/bin/sh
# Verify shutdown requests only PROPOSE an action, never power off on their own.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
cat > "$TEMP/mock-root.sh" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$XORRISO_TEST_LOG"
if [ "$1" = '--propose' ]; then
 echo "COMANDO (NAO executou): $2"
fi
MOCK
chmod +x "$TEMP/mock-root.sh"
export XORRISO_ROOT_EXEC_BIN="$TEMP/mock-root.sh"
export XORRISO_TEST_LOG="$TEMP/actions.log"
for input in 'desliga o sistema' 'desligue o sistema' 'desligar o computador'; do
 sh "$ROOT/src/chat-actions.sh" "$input" > "$TEMP/output"
 grep -F 'COMANDO (NAO executou): /bin/busybox poweroff -f' "$TEMP/output" >/dev/null
done
test "$(wc -l < "$TEMP/actions.log")" -eq 3
if grep -E -- '--approve|--cancel' "$TEMP/actions.log" >/dev/null; then
 echo 'FAIL: request self-approved a root operation'; exit 1
fi
echo 'PASS: shutdown goes to approval proposal, never to text-only response'
