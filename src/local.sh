#!/bin/sh
# MiniCPM is not included; it may run on the guest loopback or a trusted NAT host.
PATH=/bin:/usr/bin:/sbin
case "\${1:-status}" in
 status)
  echo 'MiniCPM nao esta embutido na ISO.'
  if curl -fsS --connect-timeout 2 --max-time 4 http://127.0.0.1:8080/health; then
   echo; echo 'Servidor dentro da VM encontrado: use api local.'
  elif curl -fsS --connect-timeout 2 --max-time 4 http://10.0.2.2:8080/health; then
   echo; echo 'Servidor no computador anfitriao encontrado: use api host.'
  else
   echo 'Nenhum servidor ativo. Use local help.'
  fi ;;
 help)
  echo 'Modelo oficial: openbmb/MiniCPM-V-4.7-1B-gguf:Q4_K_M'
  echo 'api host: servidor no host VirtualBox/QEMU NAT 10.0.2.2:8080 (SEM chave).'
  echo 'api local: servidor dentro da VM 127.0.0.1:8080 (ainda nao embarcado).'
  echo 'Veja docs/MINICPM.md no GitHub para iniciar o modelo no computador host.'
  echo 'Inferencia dentro do xorriso requer armazenamento persistente.' ;;
 *) echo 'Uso: local status | local help' ;;
esac
