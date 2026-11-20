#!/bin/sh
# DHCP is enabled only after net up.
PATH=/bin:/usr/bin:/sbin
case "${1:-}" in
 up)
  echo 'Ativando interfaces...'
  for mod in mii net_failover e1000 pcnet32 8139too virtio_net; do
   [ -r "/lib/xorriso/modules/$mod.ko" ] && insmod "/lib/xorriso/modules/$mod.ko" 2>/dev/null || :
  done
  ip link set lo up 2>/dev/null || :
  found=0
  for iface in /sys/class/net/*; do
   iface=${iface##*/}
   [ "$iface" = lo ] && continue
   found=1
   echo "DHCP em $iface..."
   ip link set "$iface" up || :
   if udhcpc -i "$iface" -s /etc/udhcpc.script -t 4 -T 2 -n -q; then
    echo 'Rede configurada.'; ip -4 addr show dev "$iface"; exit 0
   fi
  done
  [ "$found" = 0 ] && echo 'Nenhuma interface. Use VirtualBox Intel PRO/1000 MT Desktop.'
  echo 'Falha no DHCP.'; exit 1 ;;
 status)
  ip addr show
  echo 'Rota:';ip route show
  echo 'DNS:';cat /etc/resolv.conf 2>/dev/null || : ;;
 down)
  for iface in /sys/class/net/*; do
   iface=${iface##*/}
   [ "$iface" = lo ] && continue
   ip addr flush dev "$iface" 2>/dev/null || :
  done ;;
 *) echo 'Uso: net up | net status | net down' ;;
esac
