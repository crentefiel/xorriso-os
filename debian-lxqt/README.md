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

## ISO minimalista — revisão experimental após auditoria de pacotes (22/11/2026)

**Motivação:** a Alpha 0.16 do commit `0ac2f6d3cbcb` passou o build e o QEMU, mas seu log mostrou que o tema recomendado `sddm-theme-debian-breeze` puxava `plasma-workspace`, `plasma-desktop`, `plasma-discover` e muitas dependências alheias ao desktop LXQt.

**Mudanças controladas:** o `live-build` agora é configurado com `--apt-recommends false`. Para preservar as funções necessárias, a lista inclui explicitamente `user-setup`, `sudo`, o tema de login `sddm-theme-maui`, `xserver-xorg-video-all` e `xserver-xorg-input-all`, além dos pacotes já existentes. O SDDM usa o tema `maui` em `10-xorriso-autologin.conf`, mantendo autologin do usuário Live `xorriso`.

**Aceitação automática:** o build extrai o `/var/lib/dpkg/status` do SquashFS real, salva `package-manifest.txt`, verifica a presença das funções obrigatórias e rejeita a ISO se `plasma-workspace`, `plasma-desktop`, `plasma-discover` ou `sddm-theme-debian-breeze` ainda estiverem instalados. O workflow publica o manifesto junto à ISO aprovada e preserva os diagnósticos de boot QEMU.

**Limitações:** desligar os pacotes recomendados pode remover funcionalidades úteis implícitas. A nova versão deve passar novamente todos os testes de build, login automático, SDDM, LXQt, janela da IA, gerenciador de arquivos, terminal e Plymouth. Não confundir tamanho reduzido com boot mais rápido sem medição real. Não montar nem modificar os VDIs originais `XORRISO_DATA` e `XORRISO_RUNTIME`, e não fazer merge automático.

Documentação oficial: https://live-team.pages.debian.net/live-manual/html/live-manual/customizing-package-installation.en.html , https://packages.debian.org/trixie/sddm-theme-maui e https://packages.debian.org/trixie/sddm-theme-debian-breeze .

## Histórico persistente de erros (XOS-) — 22/11/2026

O **banco de erros do projeto** agora é `debian-lxqt/errors.json`, versionado neste PR #27. Todo futuro assistente/colaborador deve ler esse arquivo **antes de corrigir um erro semelhante**, consultar os logs do SHA afetado e acrescentar ou atualizar registros com: ID estável, sintoma/fingerprint, causa comprovada ou hipótese, link de evidências do GitHub Actions, correção aplicada, testes realizados e status. Nunca marcar um erro como resolvido por simples commit sem evidência de CI/QEMU ou VirtualBox, conforme o caso. O teste `test-desktop-layout.py` verifica a existência e a estrutura do banco.

**Caso XOS-005 (ISO minimalista preta):** comparação dos logs do SHA `0ac2f6d3cbcb` (QEMU aprovado, `xfwm4` instalado) com SHA `694c73f168df` (QEMU falhou, `xfwm4` e `openbox` ausentes) mostrou que `--apt-recommends false` eliminou o gerenciador de janelas. A documentação do LXQt confirma a necessidade de window manager X11 externo e a sintaxe `[General] window_manager=xfwm4` em `session.conf`. O reparo reinstala `xfwm4` e `xdg-user-dirs`, configura explicitamente `xfwm4` e exige os processos `lxqt-session`, `xfwm4` e `pcmanfm-qt` antes de transmitir READY no QEMU. **Trata-se de causa provável, não comprovada até o novo teste gráfico.**

Docs: https://lxqt-project.org/wiki/Window-managers-(X11).html e https://wiki.debian.org/LXQt

As alterações mantêm o tema leve Maui e os recursos principais. Não montar os VDI `XORRISO_DATA` e `XORRISO_RUNTIME` com escrita e nunca fazer merge automático.

## Live → instalação em HD/SSD com IA integrada (22/11/2026)

**Modo Live:** a ISO continua iniciando o Debian 13 LXQt, desktop preto, dois atalhos (`xorriso IA` e `Arquivos`), Plymouth e a janela da IA por autostart. Agora inclui `calamares` e `calamares-settings-debian` com suporte planejado a BIOS/UEFI através de `grub-pc-bin`, `grub-efi-amd64-bin` e `efibootmgr`. **A instalação não ocorre automaticamente.** Há botão `Instalar xorriso no HD / SSD` somente no modo Live, e a IA dispõe da ferramenta `open_installer` para pedidos explícitos. O usuário confirma a abertura, seleciona o disco no Calamares e confirma as operações de partição diretamente no instalador. A automação da IA NUNCA recebe permissão para particionar ou formatar sozinha.

**Política de autorização Live:** a unidade `xorriso-install-mode.service` executa um script root fixo, antes do display manager. Se o kernel está em `boot=live`, ela instala na camada temporária Live uma regra PolicyKit que permite **somente** abrir `/usr/bin/calamares` ao usuário local `xorriso` mediante `AUTH_SELF`. Não dá acesso a shell root nem `NOPASSWD`. A ferramenta `xorriso-install` ainda bloqueia iniciar o Calamares caso `lsblk` encontre os labels protegidos `XORRISO_DATA` ou `XORRISO_RUNTIME`. **Desconectar esses discos antes de instalar é obrigatório.** Não usar a sessão com dados sensíveis ou como instalador de produção antes da validação real.

**Sistema instalado:** o Calamares trabalha sobre o conteúdo Debian Live, incluindo `/usr/local/bin/xorriso-agent.py`, `xorriso-ui.py`, ferramentas Linux e serviços de descoberta do MiniCPM. O arquivo `/etc/xdg/autostart/xorriso-ui.desktop` garante que a interface da IA se abra **automaticamente após o login de cada sessão LXQt**, mesmo se o usuário não copiar `/etc/skel`. Os dois atalhos também estão no `/etc/skel/Desktop`. Em um boot **sem** `boot=live`, o serviço `install-mode` remove o autologin temporário `xorriso` e a regra de instalação Live antes do SDDM abrir. O usuário e senha administrativos devem ser definidos na instalação, não reutilizar uma senha conhecida da mídia Live. O ícone automático `Install Debian` criado pelo pacote foi desativado para manter somente dois atalhos.

**IA como administrador seguro:** o agente decide, solicita ferramentas e recebe respostas verificadas. Consultas Linux de baixo risco podem ser executadas como usuário comum; ações que alteram o sistema exigem confirmação específica; privilégios administrativos exigem autenticação via `pkexec`/política por ferramenta. Não fornecer à IA `sudo` sem senha, shell root genérico ou um canal direto para comandos de formatação; novas capacidades serão implementadas em ferramentas auditáveis e testáveis, com controle do usuário para qualquer ação de risco.

**Limitação importante de instalação da IA:** o **código e a interface** estarão no HD após o Calamares, mas o peso MiniCPM-V 4.7 1B e o binário `llama-server` **não são incorporados nesta ISO minimalista**. Eles ainda dependem dos volumes externos protegidos ou de um futuro provisionamento autenticado e verificado de modelo/runtime para o HD. Não afirmar que a inferência offline funciona sem conectá-los/provisioná-los.

**Testes:** a compilação + boot QEMU agora exigem tanto o marcador da sessão gráfica quanto `XORRISO_INSTALL_MODE_LIVE`, demonstrando que o serviço instalador foi preparado. Esses testes **não substituem** uma instalação real em disco descartável: antes de distribuir como instalador final é necessário testar Calamares contra HD virtual **novo/descartável** (sem os discos VDI protegidos), escolher partições, criar o usuário, validar GRUB BIOS/UEFI, reiniciar SEM ISO, confirmar login com senha própria, IA abrindo automaticamente, atalhos e ausência da regra Live. O VirtualBox real e MiniCPM seguem pendentes.

Referências: https://www.debian.org/CD/live/index.html , https://packages.debian.org/trixie/calamares-settings-debian , https://calamares.codeberg.page/docs/deploy-configuration/ .

### Administração autenticada por ferramenta (complemento desta revisão)

Além de `install_package`, a IA pode solicitar `manage_service` para operações `start`, `stop`, `restart`, `enable`, `disable` somente sobre `xorriso-model.service`, `xorriso-volumes.service` e `NetworkManager.service`. A GUI exige confirmação exata; o helper independente `admin-service` é invocado via `pkexec` com autenticação administrativa, valida os argumentos novamente antes de chamar `/usr/bin/systemctl` sem shell, verifica estado e registra a operação no syslog (facility auth). A IA não pode solicitar `sddm`, serviços arbitrários, comandos shell ou formatar partições por essa ferramenta.

O usuário quer que a IA seja o **pilar administrativo** do xorriso. Isso significa um orquestrador de ações reais, apoiado em políticas por capacidade, confirmações, autenticação e auditoria. Não equivale a entregar senha root ou uma interface que execute qualquer texto do modelo com privilégios. Novas categorias administrativas (rede, pacotes, arquivos de sistema, dispositivos e processos) podem ser implementadas com helpers separados, salvaguardas e testes, e devem ser registradas no banco de erros `errors.json` quando houver falhas.

**Estado de prova:** os helpers são reais e testáveis em código; sem instalação completa com credenciais no HD, não há comprovação do `pkexec` administrativo após instalar. QEMU Live não valida isso.

## Correção da IA local: download automático do MiniCPM-V 4.7 1B no primeiro boot do HD — 22/11/2026

**Pedido final do usuário:** manter MiniCPM-V 4.7 **1B** (não usar 35B-A3B). Ao iniciar o **sistema já instalado no HD**, baixar automaticamente pela internet os arquivos oficiais, verificar e instalar o modelo dentro do próprio HD, iniciar o servidor local e passar a responder na interface da IA. Em boots futuros, usar o cache verificado, mesmo offline. O Live serve para testar o sistema e instalar no HD; **não** baixar GBs para o RAM overlay descartável.

**Fonte oficial:** https://huggingface.co/openbmb/MiniCPM-V-4.7-1B-gguf . GGUF `MiniCPM-V-4_7-1B-Q4_K_M.gguf` (~672 MB) e projetor `mmproj-model-f16-4x.gguf` (~901 MB), total ~1,57 GB, API OpenAI-compatible de `llama-server` restrita a `127.0.0.1:8080`. O modelo raiz GGUF não emite traço de raciocínio e é o padrão recomendado pela OpenBMB.

**Provisionamento automático sem root:** `xorriso-model-provision.service` inicia em `multi-user.target` somente fora do Live, depois de network-online. Usuário Linux próprio `xorriso-model` criado por systemd-sysusers; arquivos em `/var/lib/xorriso-model` (StateDirectory). `xorriso-model-provision.py` consulta a revisão oficial do HF, metadata LFS sha256+size, seleciona **apenas** Q4_K_M + mmproj 4x, verifica RAM >=3 GiB, espaço livre com margem de 5 GiB e baixa em arquivos parciais retomáveis. Valida SHA-256 e tamanho antes do rename atômico e do manifesto `model.json`. Grava `status.json` para a interface. O serviço tenta novamente após falha de internet; se modelo e projetor já foram verificados, o boot seguinte não precisa acessar HF. Não grava nada nos VDI protegidos.

**Runtime incluído na ISO:** `build-llama-runtime.sh` compila em CI o `llama-server` CPU (sem `GGML_NATIVE` e sem GPU), de commit fixo do `ggml-org/llama.cpp` com suporte MiniCPM 4.7, verifica versão e links, e o build copia em `/opt/xorriso/llama-server`. O comando final `xorriso-run-model.py` valida outra vez o SHA-256 de ambos os GGUFs antes de executá-lo, sem shell e sem privilégios. A unidade `xorriso-model.service` inicia após provisionamento, bloqueia rede exceto localhost e aplica isolamento systemd.

**UI e agente:** interface `xorriso-ui.py` passa a mostrar fases de instalação (verificando/download com porcentagem/erro/pronto), verificando `/v1/models` periodicamente e sem informar falsa prontidão. No Live oferece instalar no HD; no instalado orienta aguardar download. Agente `xorriso-agent.py` usa modelo/alias `MiniCPM-V-4.7-1B`, planeja uma ferramenta por vez, usa JSON-constrained output no llama-server e mantém confirmação + `pkexec` para alterações administrativas. A IA é a administradora lógica do sistema, nunca root automático.

**Requisito e limite:** precisa internet na primeira inicialização do HD, cerca de 1,57 GB para download mais armazenamento livre, e RAM de preferência **4 GiB ou mais** (script exige 3 GiB). VirtualBox com 3 GB pode não servir ao modelo + GUI; recomenda-se 4–6 GB ou mais. Nenhum resultado de inferência real é alegado até ter teste com pesos baixados, `llama-server` respondendo à API e texto `oi` gerando resposta válida. O usuário enviou imagem de Live em que GUI abriu e `127.0.0.1:8080` deu `Errno 111`, consequência da ausência do backend antigo na ISO. A instalação do HD, primeiro download, reboot offline e MiniCPM real ainda requerem validação.

**Proteção:** `XORRISO_DATA` e `XORRISO_RUNTIME` permanecem intocados, sem automontagem no novo fluxo. Não formatar, converter, apagar, escrever ou montar RW. O código de montagem legado permanece apenas inativo para fins históricos e avaliação posterior.

**Testes:** `test-model-provision.py` simula o cache local, falha de RAM e rejeição de hash adulterado sem internet. `test-desktop-layout.py` exige inclusão do motor, conta, serviço, ausência do 35B no runtime e ausência da montagem automática dos VDIs. O GitHub Actions agora compila o runtime antes de gerar a ISO. É fundamental aguardar **foundation checks + build + boot QEMU + artifacts do mesmo HEAD**; depois testar instalação HD e inferência local real. **Não distribuir a ISO antiga como se a IA 1B já estivesse integrada.**

**Nota:** a revisão inicial do usuário pediu 35B, mas ele alterou expressamente para MiniCPM-V 4.7 1B. Arquivos `xorriso-model-provision.py` e `xorriso-run-model.py` foram corrigidos para evitar conflito de modelos. Os testes para 1B não implicam que o 35B funcione ou esteja instalado.

## Correção Calamares pedindo senha root no Live — XOS-010 (22/11/2026)

**Sintoma real no VirtualBox:** diálogo `Authentication Required`, mensagem `Authentication is required to run the installation program`, seletor com apenas `unix-user:root`, sem senha root definida. O usuário confirmou que não existe a opção `xorriso` na lista. **Não existe senha root predefinida do xorriso**; orientar `live` não resolve o diálogo como está. O erro foi identificado por comparação do ID real da política do Calamares Debian, `com.github.calamares.calamares.pkexec.run`, com o ID errado `org.freedesktop.policykit.exec` usado na nossa regra. Em Debian 13, a política original Calamares pede `auth_admin`.

**Correção na branch:** `xorriso-calamares.policy` registra uma ação própria `org.xorriso.install.launch` com `org.freedesktop.policykit.exec.path` fixado no helper `/usr/local/libexec/xorriso/calamares-root` e `exec.allow_gui=true`. A unidade `xorriso-install-mode.service` copia `live-calamares.rules` **apenas em boot=live**. A regra permite a execução **somente para o usuário local e ativo xorriso**, **somente** do helper exato, com `polkit.Result.YES` (a conta Live pode não ter senha). Fora do Live a regra não é concedida e a unidade remove a cópia residual antes do login. Não há senha root, senha universal, sudo NOPASSWD, shell root fornecido ao modelo ou autorização para outros comandos `pkexec`.

**Proteção adicional dos VDIs:** o helper executado após o `pkexec` valida EUID root, `boot=live`, zero argumentos e os rótulos `XORRISO_DATA` e `XORRISO_RUNTIME` com `lsblk` **novamente antes de abrir Calamares**; se os discos estiverem visíveis, recusa, inclusive contra chamadas diretas fora da UI. O usuário ainda precisa escolher/confirmar as partições dentro do Calamares; nunca automatizar formatação.

**Prova pendente:** o teste estático, compilação ISO, QEMU e arquivo de download **devem** ser aprovados no mesmo HEAD. A passagem do QEMU prova integração/boot, **não** que o diálogo no VirtualBox desapareceu: confirmar visualmente a execução de `pkexec` e a abertura efetiva do Calamares com disco virtual descartável. Referência da política original: https://sources.debian.org/src/calamares/3.3.14-1/com.github.calamares.calamares.policy . Banco de erros: `debian-lxqt/errors.json`, caso `XOS-010`.
