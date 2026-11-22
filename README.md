# xorriso OS — Linux experimental centrado em IA

O **xorriso OS** é um projeto experimental de sistema Linux com assistente de inteligência artificial local. Há duas linhas de desenvolvimento: a **Alpha 0.15**, com interface própria em modo texto, e a **Alpha 0.16 (Debian 13 + LXQt)**, com desktop gráfico e agente de tarefas. A Alpha 0.16 ainda está em avaliação e **não foi incorporada à branch principal**.

## Alpha 0.16 — ISO experimental disponível para teste

**Download da imagem:** [xorriso Debian/LXQt — artefato GitHub Actions](https://github.com/crentefiel/xorriso-os/actions/runs/45023369804/artifacts/14755136054). O GitHub fornece um **arquivo ZIP contendo a ISO**, não um instalador do Windows. É necessário entrar no GitHub para baixar artefatos do Actions. O arquivo tem retenção de 14 dias, com expiração prevista para **6 de dezembro de 2026**; após essa data, confira as [execuções mais recentes](https://github.com/crentefiel/xorriso-os/actions).

- **Origem do código:** [PR #26 — agente Alpha 0.16](https://github.com/crentefiel/xorriso-os/pull/26) sobre a base [PR #25 — Debian/LXQt](https://github.com/crentefiel/xorriso-os/pull/25). PR experimental, ainda não integrado ao `main`.
- **Base:** Debian 13 (Trixie), LXQt, login gráfico automático e desktop minimalista com o ícone **xorriso IA**.
- **Assistente:** janela em Python/Tk conectada à API local compatível com OpenAI em `127.0.0.1:8080/v1`, destinada ao MiniCPM local quando modelo e motor estiverem disponíveis.
- **Ações delimitadas:** consultar o sistema, listar/ler/criar arquivos e pastas em espaço controlado, consultar pacotes, propor instalação de aplicativos e abri-los. O agente recebe observações reais, tem limite de etapas e não recebe um terminal root irrestrito.
- **Verificação já concluída:** compilação da ISO, validação da estrutura da imagem e teste automatizado no QEMU com framebuffer gráfico não preto. **Isso não comprova, por si só, que o LXQt, a janela da IA, o MiniCPM ou a instalação de aplicativos funcionem corretamente no VirtualBox.**

### Como testar a Alpha 0.16 no VirtualBox

1. Baixe o artefato no link acima e **extraia o ZIP** para obter o arquivo `.iso`.
2. Crie **uma nova VM descartável** no VirtualBox (Linux Debian 64 bits; recomenda-se começar com pelo menos 4 GiB de RAM e 2 CPUs, se o computador permitir).
3. Anexe a ISO como unidade óptica virtual e inicialize a VM **sem conectar inicialmente os seus discos VDI antigos**.
4. Verifique se o sistema abre o desktop LXQt e exibe o ícone **xorriso IA**. Abra o ícone e confira se a janela aparece.
5. Só depois de validar a interface, experimente cópias dos volumes, nunca os discos originais como primeiro teste. Registre falhas de boot, teclado, janela e inicialização do MiniCPM em uma [issue](https://github.com/crentefiel/xorriso-os/issues).

**Proteja os dados existentes:** não formate, converta, substitua ou use como destino de instalação os discos `XORRISO_DATA` e `XORRISO_RUNTIME`. Na implementação Debian, eles são detectados por label e montados **somente para leitura** quando presentes. O teste inicial mais seguro é sem esses discos.

### Limitações importantes da Alpha 0.16

- **MiniCPM real:** o funcionamento do modelo GGUF e do `llama-server` com os volumes reais continua dependendo de teste prático; sem esses componentes, a IA poderá indicar indisponibilidade.
- **Instalação administrativa:** a interface exige consentimento para instalação de pacotes e o helper usa `pkexec`, mas a conta live `xorriso` está com senha bloqueada e **não há ainda configuração inicial de credenciais administrativas**. Portanto, a instalação de aplicativos **não está funcional por padrão**.
- **Persistência:** a sessão Live usa armazenamento temporário. Aplicações e modificações feitas durante a sessão **não persistem necessariamente após reiniciar**.
- **Segurança e acabamento:** sem homologação no VirtualBox, sem teste integral da IA real e sem garantias para dados sensíveis. Esta ISO é para experimentação, não para uso como sistema principal.

Para detalhes técnicos, veja a [documentação da nova base na branch experimental](https://github.com/crentefiel/xorriso-os/blob/feat/alpha-016-ai-admin-agent/debian-lxqt/README.md).

---

## Linha anterior — Alpha 0.15 (interface textual)

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
