# MiniCPM-V 4.7 1B — integração prevista

A Alpha 0.7 **não contém** pesos GGUF nem motor de inferência local.

- Modelo: https://huggingface.co/openbmb/MiniCPM-V-4.7-1B
- GGUF: https://huggingface.co/openbmb/MiniCPM-V-4.7-1B-gguf

A futura implementação deverá instalar llama.cpp e os pesos somente sob demanda, em armazenamento persistente, validar os arquivos baixados e rodar o servidor em 127.0.0.1:8080. O comando `api local` irá selecionar `http://127.0.0.1:8080/v1`, porém NÃO inicia o modelo nem instala seus arquivos. Dentro do VirtualBox o loopback da VM é diferente do loopback do host.
