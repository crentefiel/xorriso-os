#!/bin/sh
# Loopback must have IPv4 address before localhost-only AI server starts.
# Link UP alone does NOT guarantee 127.0.0.1/8 is assigned in an initramfs.
set -eu
PATH=/bin:/usr/bin:/sbin
case "${1:-up}" in
 up)
  if ! ip link set dev lo up; then
   echo 'Erro ao ativar lo.' >&2
   exit 1
  fi
  if ! ip -4 addr show dev lo | grep -q 'inet 127\.0\.0\.1/'; then
   if ! ip addr add 127.0.0.1/8 dev lo 2>/dev/null; then
    # Already configured by another process is acceptable.
    ip -4 addr show dev lo | grep -q 'inet 127\.0\.0\.1/' || {
      echo 'Falha ao configurar IPv4 127.0.0.1/8 em lo.' >&2
      exit 1
    }
   fi
  fi
  ;;
 status)
  ip -4 addr show dev lo
  ;;
 *)
  echo 'Uso: loopback up | loopback status' >&2
  exit 2
  ;;
esac
