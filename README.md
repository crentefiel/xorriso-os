# xorriso OS — Alpha 0.15 (IA inicia sozinha + primeiras acoes reais)

Sistema operacional Linux experimental centrado em IA, desenvolvido para testar no VirtualBox.

## Como inicia

**Nao ha mais comandos obrigatorios para abrir a IA.** Ao ligar:

1. O Linux detecta e monta automaticamente os dois discos virtuais ja existentes: `XORRISO_DATA` (pesos do MiniCPM e dados) e `XORRISO_RUNTIME` (motor `llama-server`).
2. A tela dedicada da IA aparece **automaticamente**, sem pressionar F2 ou F3.
3. Em segundo plano, o xorriso configura a API local `127.0.0.1:8080`, verifica os componentes existentes e inicia o MiniCPM. A tela informa `preparando`, `pronta` ou a causa de indisponibilidade.
4. Quando a IA estiver pronta, o usuário digita normalmente. O console administrativo F2 continua opcional.

A interface ainda é **textual**, não um desktop gráfico; **voz/microfone ainda não foram implementados**. Esc fecha a conversa e deixa a tela completamente preta; F3 reabre, F2 mostra o console, F1 mostra o estado.

## Primeiras ações no Linux

No painel que abre automaticamente, o usuário já pode escrever:

```text
Crie uma pasta chamada Meus Projetos
Liste minhas pastas
```

A pasta é criada de verdade em `/data/Documentos/Meus Projetos` e confirmada **somente após o Linux verificar que existe**. A pasta e seu conteúdo persistem no VDI `XORRISO_DATA`. Se não houver disco montado, a IA informa o problema sem gravar na RAM.

Para esse primeiro fluxo, pedidos comuns de criação/listagem são reconhecidos por regras simples do próprio sistema, garantindo confiabilidade. O comando administrativo `agent` também permite ao MiniCPM **propor essas ações em JSON**, que são validadas e executadas pelo mesmo helper. O xorriso ainda **não entende e executa qualquer pedido arbitrário**.

O processo de inicialização e o executor rodam com privilégios do sistema Linux, mas **não** transformam texto do modelo em um shell root irrestrito. As operações disponíveis nesta etapa são limitadas, validadas e não destrutivas. Alterações administrativas amplas, instalação de programas, mudanças de aparência e operações destrutivas serão módulos posteriores, com autorização do usuário e recuperação.

## Teste no VirtualBox

Preserve os dois VDIs que já estavam funcionando: **não reformate nem substitua esses discos**. Troque somente a ISO pela `xorriso-alpha-015-grub.iso`. Inicie a VM normalmente.

1. A tela de conversa deverá aparecer sozinha.
2. Aguarde o status da IA ficar **pronta**. O carregamento pode demorar conforme memória e CPU.
3. Digite `Ola, MiniCPM!` e veja a resposta da IA local.
4. Digite `Crie uma pasta chamada Meus Projetos`; o sistema deverá mostrar `Pasta criada e verificada: /data/Documentos/Meus Projetos`.
5. Digite `Liste minhas pastas`; o nome deve aparecer.
6. Pressione Esc: a tela ficará preta. F3 abre a conversa e F2 abre o console.

No console administrativo opcional, `ai status`, `runtime status`, `storage status` e `action Crie uma pasta chamada Teste` continuam disponíveis. Se a IA não carregar, use `ai status` e `runtime log` para diagnosticar. `/ready` consulta o carregamento na tela de conversa.

## Testes automatizados

GitHub Actions verifica scripts, executor com pastas reais em um diretório isolado, validação contra travessia de caminhos e links simbólicos, inicialização automática simulada com cenários de pronto/ausente/falha, integração de ações propostas pelo modelo em JSON simulado, boot real da ISO pelo GRUB no QEMU **abrindo o chat automaticamente**, Esc, F3, F2, rede, TCP localhost e dois discos SATA com persistência.

**Os testes automatizados não comprovam o carregamento do MiniCPM real nesta ISO.** O último teste do modelo real foi na versão anterior, e a Alpha 0.15 precisa ser validada pelo usuário no VirtualBox.

O sistema continua experimental, sem criptografia do VDI, microfone, ambiente gráfico completo ou instalador genérico. Não utilize para dados sensíveis. Código próprio sob MIT, respeitando licenças dos componentes de terceiros.

## Alpha 0.15.1 — inicialização automática (correção em PR)

Ao iniciar, o xorriso procura novamente os VDI `XORRISO_DATA` e `XORRISO_RUNTIME`
caso o VirtualBox demore a disponibilizá-los; informa a falta de cada componente
e dá até cerca de quatro minutos para a API do MiniCPM responder. A tela mostra
`carregando MiniCPM` até a resposta HTTP de saúde ou uma falha diagnosticável.

Para testar, preserve os dois discos VDI originais e use **4 GiB ou mais de RAM**
na VM, se disponíveis. Em F2: `ai status`, `storage status`, `runtime status`,
`runtime log`. Os testes automatizados simulam o servidor; a resposta real do
MiniCPM dentro do VirtualBox ainda requer validação prática.

## Alpha 0.15.2 — teclado brasileiro ABNT2

A imagem de boot passa a incluir um mapa de teclado para o console Linux gerado
com `ckbcomp -model pc105 -layout br -variant abnt2`, instalado por `loadkeys`
na inicialização. O terminal é colocado em modo UTF-8 antes de abrir o chat.
Com isso, as posições físicas do teclado, o Ç e as teclas mortas de acentos
seguem o padrão brasileiro. F2/F3/Esc e a inicialização automática da IA
permanecem disponíveis; os dois VDI existentes não são alterados.

A compilação automática verifica a presença do mapa. Ainda é necessário
validar fisicamente no VirtualBox as teclas Ç, acentos, barra e interrogação.
