# xorriso OS — nova base Debian 13 + LXQt (em desenvolvimento)

Este caminho de compilação usa o Debian Live e o LXQt em vez de desenhar diretamente no framebuffer. A antiga ISO não é alterada.

## Interface
- Login gráfico automático da sessão `xorriso`.
- Desktop minimalista, sem barra de tarefas, com apenas dois atalhos: **xorriso IA** e **Arquivos**.
- O ícone **xorriso IA** reabre a interface Python/Tk, que também inicia automaticamente na sessão LXQt. A interface verifica `127.0.0.1:8080/v1/models` e informa quando o MiniCPM local não está disponível.
- O ícone **Arquivos** abre o gerenciador `pcmanfm-qt`, preservado para navegação manual, pastas, documentos, cópia e organização. O agente também possui a ferramenta `open_file_manager`, executada como usuário comum, sem shell root.
- O perfil PCManFM-Qt omite os atalhos automáticos de Home, Trash, Computer e Network; desabilita a montagem automática de volumes e mantém a lixeira dentro do gerenciador. Não elimina o gerenciador de arquivos.
- O Debian Live agora recebe `username=xorriso` e o pacote `user-setup` cria o usuário **no boot**; os arquivos da sessão (atalhos, autostart e fundo) vêm de `/etc/skel`. Não se cria uma conta antecipada durante o build, pois `live-config` pula a criação da conta quando ela já existe. O parâmetro `live-config.nocomponents=sudo` impede a concessão automática de sudo sem senha ao usuário Live. A funcionalidade gráfica continua pendente de validação em QEMU/VirtualBox.
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

Ferramentas: `system_info`, `system_resources`, `network_info`, `list_applications`, `service_status`, `list_files`, `read_file`, `create_folder`, `create_file`, `find_command`, `package_info`, `install_package`, `open_application`, `open_file_manager`, `finish`. A interface mostra os resultados verificados, não apenas uma resposta generativa.

Instalar programas é um fluxo de **duas autorizações**: a pessoa confirma o nome exato do pacote na GUI e o `pkexec` solicita autenticação de administrador por PolicyKit. O helper `admin-package` é um programa separado, com argumentos validados, chama `apt-get install` sem shell e confere a instalação via `dpkg-query`. Nenhuma autorização é dada diretamente ao MiniCPM.

**Limitação bloqueante no protótipo live:** `live-config/user-setup` cria `xorriso` com credencial padrão de teste do Debian Live, mas a atribuição automática de sudo sem senha foi desabilitada e **não há um administrador autenticado e autorizado** configurado para a instalação de pacotes via `pkexec`. A Alpha 0.16 precisa de um assistente seguro de primeiro início, com credenciais administrativas próprias, antes de ser considerada uma release. Não usar esse protótipo com dados sensíveis.

**Persistência:** a imagem Debian Live utiliza uma camada temporária. Instalações via APT nesta sessão **não são garantidas após reiniciar**. Não escrevemos em `XORRISO_DATA` ou `XORRISO_RUNTIME` para persistir pacotes, porque os VDIs foram preservados somente para leitura. Uma camada persistente própria ou instalação em um terceiro disco deve ser implementada e testada depois.

Os testes de agente usam um modelo e executor simulados para verificar a sequência pacote → instalação → abertura, observações, cancelamento, proteção de caminhos e que não se executa `sh -c` como root. **Não comprovam ainda** que o MiniCPM real gerará os JSONs corretos nem que o PolicyKit autentica no VirtualBox.


## Regra de interface — 22/11/2026

Conservar **xorriso IA** e **Arquivos** como os únicos atalhos do desktop. O gerenciador PCManFM-Qt é componente essencial, não pode ser removido ao "limpar" o Debian. Configurações do sistema permanecem instaladas, mesmo sem painel. A IA pode pedir abertura da pasta pessoal, mas o usuário sempre mantém acesso direto aos seus arquivos pelo ícone **Arquivos**.

Ainda não há confirmação de que a ISO nova inicialize sem demora ou tela preta: corrigir a conta Live e reduzir atalhos são passos de implementação, não prova de boot. Nenhum dos discos `XORRISO_DATA` e `XORRISO_RUNTIME` deve ser formatado, remontado com escrita ou excluído.

## Diagnóstico de boot e validação

O teste QEMU agora seleciona a entrada Live quando o menu Syslinux precisar de Enter; durante o boot produz capturas PNG em intervalos de tempo e preserva `serial.log`, `qemu.log` e `boot-status.json`. O workflow publica um artefato **BOOT-DIAGNOSTICS** mesmo em caso de falha do teste, para identificar se a tela preta veio do menu, kernel, SDDM ou LXQt. Não se considera um desktop aprovado apenas por framebuffer não preto: ainda é preciso o marcador `XORRISO_LXQT_DESKTOP_READY` emitido por sessão X11 válida. Os artefatos de ISO somente são publicados quando o teste de boot passa.

A ausência do MiniCPM não deve impedir o desktop de abrir. A conta Live `xorriso` segue sem senha administrativa válida: o agente **não** recebe root por padrão e a instalação via APT depende de credenciais legítimas em etapa posterior. Para persistência, planejar volume separado **sem modificar os VDI protegidos**.

## Pesquisa e correção de boot (22/11/2026)

O manual oficial do Debian descreve os **hooks de build**, o uso de `/etc/skel` e o `live-config` durante o boot. O componente de usuário `0030-user-setup` contém `if grep -q "^${LIVE_USERNAME}:" /etc/passwd; then exit 0; fi`, razão pela qual criar o usuário `xorriso` no chroot era conflitante. Nesta revisão, o hook só configura `/etc/skel` e systemd e deixa `live-config` criar o usuário Live no boot. O serviço de diagnóstico é o responsável por emitir o marcador serial após a sessão gráfica depositar confirmação em `/tmp`; a conta comum não precisa ter permissão de escrita no `ttyS0`.

Fontes: https://live-team.pages.debian.net/live-manual/html/live-manual/customizing-contents.en.html ; https://sources.debian.org/src/live-config/11.0.3/components/0030-user-setup/ ; https://manpages.debian.org/trixie/live-config-doc/live-config.7.en.html

**Ainda depende de boot real:** o CI deve comprovar conta criada, SDDM ativo, LXQt iniciado, janela de IA e dois atalhos. Sem isso, não anunciar ISO corrigida ou solução do VirtualBox.

## Corrigido após o teste 45037305528 — sinaleiro LXQt

O QEMU mostrou **LXQt com a janela xorriso IA aberta** na captura `boot-455s.png`, mas o workflow marcou falha após 480 segundos. O motivo confirmado no hook era `printf '%s\\\\n'` (emissão dos caracteres literais barra invertida e n) em vez de `printf '%s\\n'` (quebra de linha real); consequentemente, a checagem `grep -Fxq` do marcador não era satisfeita. O hook foi corrigido e o teste de layout passou a executar os comandos `printf` extraídos do shell para impedir regressão.

A ausência de `XORRISO_DATA` / `XORRISO_RUNTIME` no QEMU é esperada: o script de montagem não falha quando o rótulo não existe. **Os volumes continuam somente leitura** quando presentes, e não há criação, formatação ou escrita automática. Sem volumes, a interface deve apenas informar indisponibilidade da IA local. O teste no VirtualBox e a execução real do MiniCPM continuam pendentes.

Execução diagnóstica: https://github.com/crentefiel/xorriso-os/actions/runs/45037305528

## Terminal e carregamento visual — 22/11/2026 (nova revisão experimental)

**Interface:** mantém **apenas os atalhos xorriso IA e Arquivos** na área de trabalho, mas a janela da IA passa a ter um campo `Terminal (consultas)`, um botão **Executar**, outro **Terminal completo** (abre QTerminal como usuário `xorriso`, não root), **Arquivos** e **Verificar IA**. O terminal por comandos funciona mesmo se a API MiniCPM não estiver conectada; o MiniCPM **não é necessário** para abrir as ferramentas locais.

**Ferramenta real de terminal da IA:** `run_terminal_command` executa um subconjunto definido de consultas Linux (exemplos: `whoami`, `ls -la` na pasta pessoal, `free -h`, `df -h`, `ip -brief address`, `systemctl is-active xorriso-model.service`) por `subprocess.run(..., shell=False)`, sem executar strings de shell ou comandos arbitrários. A operação `mkdir NOME` é permitida apenas em `~/Documentos`, **somente após confirmação**, e confere o resultado real. O QTerminal completo permanece disponível para uso humano; a IA não recebe acesso indiscriminado a root. Não usar `sudo` automático nem executar código fornecido pelo modelo sem validação.

**Confirmação do atalho:** a documentação oficial do PCManFM-Qt explica que executáveis não confiáveis pedem confirmação e que `QuickExec=true` desativa a proteção globalmente, o que NÃO é desejado. Esta revisão instala `gvfs` e tenta marcar como confiáveis **apenas** `~/Desktop/xorriso.desktop` e `~/Desktop/arquivos.desktop` na sessão pessoal via `gio set ... metadata::trusted true`. Esse comportamento **ainda precisa de confirmação visual no VirtualBox**. Fonte: https://lxqt-project.org/wiki/Pcmanfm-qt.html#trusting-executables

**Carregamento no boot:** adiciona `plymouth` e `plymouth-themes`, seleciona o tema de progresso `tribar` durante a construção da ISO e acrescenta `quiet splash` à linha do kernel. A tela de carregamento é o Plymouth real, com estado visual sem porcentagem artificial. O splash não deve ser usado como substituto do teste verdadeiro de sessão LXQt ou como alegação de que a demora foi resolvida. Fontes: https://wiki.debian.org/plymouth e https://manpages.debian.org/trixie/plymouth/plymouth-set-default-theme.1.en.html

**MiniCPM:** o usuário já enviou vídeo de uma ISO anterior em que a janela abriu, mas `127.0.0.1:8080` recusou conexão. Sem os VDI e modelos, o servidor local não pode ser executado. A interface nova explica a indisponibilidade e oferece **Verificar IA**; a conexão real ao `llama-server` e aos pesos depende de testes com cópias dos discos. Nunca formatar `XORRISO_DATA` ou `XORRISO_RUNTIME`.

**Testes:** os testes estáticos e de agente foram ampliados para bloquear opções não previstas (por exemplo `ls -R`), validação do `mkdir` autorizado e empacotamento das ferramentas e tema. As verificações básicas e a ISO da nova revisão ainda têm que ser aprovadas em CI; QEMU aprovado não é sinônimo de teste no VirtualBox.
