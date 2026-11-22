# xorriso OS — nova base Debian 13 + LXQt (em desenvolvimento)

Este caminho de compilação usa o Debian Live e o LXQt em vez de desenhar diretamente no framebuffer. A antiga ISO não é alterada.

## Interface
- Login gráfico automático da sessão `xorriso`.
- Desktop minimalista, sem barra de tarefas, com apenas dois atalhos: **xorriso IA** e **Arquivos**.
- O ícone **xorriso IA** abre uma interface Python/Tk que conversa com o servidor local OpenAI-compatível em `127.0.0.1:8080/v1`.
- O ícone **Arquivos** abre o gerenciador `pcmanfm-qt`, preservado para navegação manual, pastas, documentos, cópia e organização. O agente também possui a ferramenta `open_file_manager`, executada como usuário comum, sem shell root.
- O perfil PCManFM-Qt omite os atalhos automáticos de Home, Trash, Computer e Network; desabilita a montagem automática de volumes e mantém a lixeira dentro do gerenciador. Não elimina o gerenciador de arquivos.
- O boot Live agora especifica `username=xorriso` para evitar que a personalização seja aplicada só em `/home/xorriso` enquanto a sessão gráfica entre com o usuário padrão `user`. Essa mudança ainda exige validação na ISO e no VirtualBox.
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
2. Confirmar LXQt e apenas os dois ícones (xorriso IA e Arquivos), clique, teclado ABNT2, PCManFM-Qt e janela de conversa.
3. Confirmar que sem VDIs a interface abre e explica a indisponibilidade da IA.
4. Ligar primeiro cópias dos VDIs e confirmar montagem somente leitura; só depois usar os originais.
5. Testar o MiniCPM com modelo local, criação/listagem de arquivos, perguntas sem execução e autorização/cancelamento.
6. Implementar backend administrativo root com política por tarefa, logs de auditoria e confirmação confiável, além de instalação de programas, gerenciamento de janelas e sequência de ações da IA.

A etapa atual é um protótipo técnico, não uma versão final ou pronta para confiar dados sensíveis.


## Alpha 0.16 — agente Linux administrativo (PR experimental)

A janela `xorriso IA` agora chama `xorriso-agent.py`, que consulta o MiniCPM local para selecionar ferramentas **por significado** e, depois de cada ferramenta, devolve ao modelo uma observação real. O ciclo tem limite de seis etapas. Não existem regras de texto que associem frases fixas a comandos; há um catálogo pequeno de ferramentas validadas, para não executar texto arbitrário da IA como root.

Ferramentas: `system_info`, `list_files`, `read_file`, `create_folder`, `create_file`, `find_command`, `package_info`, `install_package`, `open_application`, `finish`. A interface mostra os resultados verificados, não apenas uma resposta generativa.

Instalar programas é um fluxo de **duas autorizações**: a pessoa confirma o nome exato do pacote na GUI e o `pkexec` solicita autenticação de administrador por PolicyKit. O helper `admin-package` é um programa separado, com argumentos validados, chama `apt-get install` sem shell e confere a instalação via `dpkg-query`. Nenhuma autorização é dada diretamente ao MiniCPM.

**Limitação bloqueante no protótipo live:** a conta `xorriso` é criada com senha bloqueada. Sem a configuração posterior de uma credencial administrativa válida, a autenticação do `pkexec` falhará e o agente **não poderá instalar aplicativos** na VM. A Alpha 0.16 ainda não tem um assistente seguro de primeira inicialização para configurar credenciais; isso precisa ser resolvido antes de uma release utilizável.

**Persistência:** a imagem Debian Live utiliza uma camada temporária. Instalações via APT nesta sessão **não são garantidas após reiniciar**. Não escrevemos em `XORRISO_DATA` ou `XORRISO_RUNTIME` para persistir pacotes, porque os VDIs foram preservados somente para leitura. Uma camada persistente própria ou instalação em um terceiro disco deve ser implementada e testada depois.

Os testes de agente usam um modelo e executor simulados para verificar a sequência pacote → instalação → abertura, observações, cancelamento, proteção de caminhos e que não se executa `sh -c` como root. **Não comprovam ainda** que o MiniCPM real gerará os JSONs corretos nem que o PolicyKit autentica no VirtualBox.


## Regra de interface — 22/11/2026

Conservar **xorriso IA** e **Arquivos** como os únicos atalhos do desktop. O gerenciador PCManFM-Qt é componente essencial, não pode ser removido ao "limpar" o Debian. Configurações do sistema permanecem instaladas, mesmo sem painel. A IA pode pedir abertura da pasta pessoal, mas o usuário sempre mantém acesso direto aos seus arquivos pelo ícone **Arquivos**.

Ainda não há confirmação de que a ISO nova inicialize sem demora ou tela preta: corrigir a conta Live e reduzir atalhos são passos de implementação, não prova de boot. Nenhum dos discos `XORRISO_DATA` e `XORRISO_RUNTIME` deve ser formatado, remontado com escrita ou excluído.
