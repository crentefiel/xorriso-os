#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CAT="$ROOT/src/command-catalog.sh"
sh -n "$CAT"
sh -n "$ROOT/src/ai-agent.sh"
if command -v busybox >/dev/null 2>&1; then
  sh "$CAT" --describe ls > /tmp/xorriso-help-test.$$
  grep -qi 'ls' /tmp/xorriso-help-test.$$
  rm -f /tmp/xorriso-help-test.$$
  if sh "$CAT" --describe 'ls;id' >/dev/null 2>&1; then
    echo 'FAIL: shell syntax in applet name accepted'; exit 1
  fi
  if sh "$CAT" --describe definitely-not-an-applet >/dev/null 2>&1; then
    echo 'FAIL: unknown applet accepted'; exit 1
  fi
fi
echo 'PASS: consulta de ajuda limitada a applets BusyBox reais'
