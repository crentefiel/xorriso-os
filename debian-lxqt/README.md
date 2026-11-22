# xorriso OS — nova base Debian 13 + LXQt (em desenvolvimento)

Este caminho de compilação usa o Debian Live e o LXQt em vez de desenhar diretamente no framebuffer. A antiga ISO não é alterada.

## Interface
- Login gráfico automático da sessão `xorriso`.
- Desktop minimalista, sem barra de tarefas e com um único ícone "xorriso IA".
- Esse ícone abre uma interface Python/Tk que conversa com o servidor local OpenAI-compatível em `127.0.0.1:8080/v1`.
- O MiniCPM recebe o pedido em português e propõe uma ação em JSON. O sistema só executa ações conhecidas e verifica o resultado real.
- Ações disponíveis nesta fase: listar/criar/ler arquivos em `~/Documentos`, criar pastas, consultar informações do sistema. Criação exige confirmação do usuário; nunca sobrescreve arquivos.
- Perguntas de capacidade, como "você consegue criar uma pasta?", devem ser respondidas sem executar. Há instruções ao modelo, além da confirmação obrigatória na interface.
- Comandos root são **apenas propostas**. Não há executor root autenticado integrado a este Debian ainda.

## MiniCPM e discos VDI
O código opcional monta por label os discos ext4 existentes `XORRISO_DATA` e `XORRISO_RUNTIME` em `/data` e `/runtime-data`, respectivamente, **somente para leitura**, com `ro,noload,nosuid,nodev,noexec` para não reproduzir o journal nem executar binários do disco. Se não existirem, o desktop deve continuar a abrir, com a IA reportando indisponibilidade.

O serviço systemd confere hashes SHA-256 conhecidos para o modelo GGUF, o executável `llama-server` e, quando existir, o projetor; copia apenas o executável validado para `/run` e disponibiliza a API em `127.0.0.1:8080`. O processo roda sem capabilities Linux e com isolamento de systemd, porém ainda como root devido às permissões da estrutura antiga no VDI (um ponto a melhorar antes de chamar o ambiente de seguro para produção).

**Nenhum VDI deve ser formatado ou convertido.** Teste primeiro uma ISO nova em uma VM descartável sem anexar os VDI antigos.

## Compilação
Em máquina Linux de desenvolvimento, com internet:
```sh
sudo apt-get install -y live-build xorriso debootstrap
bash debian-lxqt/build.sh
```
O build deverá produzir `debian-lxqt/work/live-image-amd64.hybrid.iso` quando bem-sucedido. Esse arquivo ainda **não foi validado** no VirtualBox.

## Testes antes de distribuir
1. Testar compilação, ISO/GRUB e vários cold boots no QEMU e VirtualBox.
2. Confirmar LXQt e ícone único, clique, teclado ABNT2 e janela de conversa.
3. Confirmar que sem VDIs a interface abre e explica a indisponibilidade da IA.
4. Ligar primeiro cópias dos VDIs e confirmar montagem somente leitura; só depois usar os originais.
5. Testar o MiniCPM com modelo local, criação/listagem de arquivos, perguntas sem execução e autorização/cancelamento.
6. Implementar backend administrativo root com política por tarefa, logs de auditoria e confirmação confiável, além de instalação de programas, gerenciamento de janelas e sequência de ações da IA.

A etapa atual é um protótipo técnico, não uma versão final ou pronta para confiar dados sensíveis.
