#!/bin/sh
# Probe only: MiniCPM and llama.cpp are NOT packaged into Alpha 0.7.
PATH=/bin:/usr/bin:/sbin
case "${1:-status}" in
 status)
  echo 'MiniCPM local nao incluso nesta ISO. Procurando llama.cpp em 127.0.0.1:8080 ...'
  if curl -fsS --connect-timeout 2 --max-time 4 http://127.0.0.1:8080/health; then
   echo; echo 'Servidor ativo. Use api local ; api test ; ask Ola'
  else
   echo 'Servidor local indisponivel. Use local help.'
  fi ;;
 help)
  echo 'MiniCPM-V 4.7 1B GGUF: openbmb/MiniCPM-V-4.7-1B-gguf'
  echo 'Instalacao futura: llama.cpp e pesos fora da ISO minima.'
  echo 'api local usa localhost DENTRO da VM, nao localhost do host.' ;;
 *) echo 'Uso: local status | local help' ;;
esac
