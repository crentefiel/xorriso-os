# xorriso OS — Alpha 0.14 (tela dedicada à conversa local)

O xorriso é um sistema Linux experimental centrado em IA. **A inicialização continua totalmente preta e vazia**, sem barra, janela, ícone ou relógio.

## Novidade: F3 abre uma conversa em tela cheia

Nesta versão, a interface de conversa é **textual e minimalista**, usando a própria tela de console do Linux (não é um ambiente gráfico de janelas). Ela só aparece quando o usuário solicita:

- **F3**: abre a tela dedicada para conversar diretamente com o MiniCPM, sem precisar digitar o prefixo \`ask\`.
- **Enter**: envia a pergunta ao servidor selecionado em \`api local\` ou à API configurada.
- **F2**: abre o console administrativo tradicional.
- **Esc**: fecha a conversa ou o console e retorna à tela preta totalmente vazia.
- **F1**: mostra estado do sistema.

O usuário também pode abrir a conversa com \`chat open\` no console F2. Durante a conversa, existem comandos curtos:

| Comando | Função |
| --- | --- |
| \`/last\` | Mostrar literalmente a última pergunta gravada na memória RAM |
| \`/status\` | Ver quantidade de trocas registradas |
| \`/clear\` | Apagar histórico e respostas temporárias na RAM |
| \`/exit\` | Voltar à tela preta vazia |

A memória de conversa permanece limitada a quatro pares de mensagens e **nunca é gravada no VDI**. O texto gerado pelo MiniCPM é apresentado como texto, nunca executado como comando de sistema.

## Como testar no VirtualBox

**Preserve os dois VDIs já existentes**: o volume \`XORRISO_DATA\` contém os pesos MiniCPM verificados e o volume \`XORRISO_RUNTIME\` contém o \`llama-server\`. Troque apenas a ISO pelo arquivo \`xorriso-alpha-014-grub.iso\`.

1. Inicie o Linux, pressione F2 e prepare a IA:

\`\`\`text
storage status
runtime start
api local
\`\`\`

2. Pressione **F3**. Deve surgir uma tela de conversa independente do prompt \`xorriso>\`.
3. Escreva uma pergunta, por exemplo \`Ola, quem e voce?\` e pressione Enter.
4. Teste \`/last\`, \`/status\`, \`/clear\`.
5. Pressione Esc. A área de trabalho deve ficar **completamente preta**; F2 ainda abre o console.

Se quiser verificar o modelo diretamente no console, os comandos anteriores \`ask\`, \`chat status\`, \`chat last\` e \`chat clear\` continuam disponíveis.

## Testes e limitações

A automação do GitHub gera a ISO com GRUB e verifica em QEMU que **F3 abre a tela de conversa, Esc a fecha, F2 abre o console e Esc volta à tela preta**. Os testes de API simulada, histórico, localhost, armazenamento em IDE/SATA, volumes separados e verificação de runtime permanecem.

Esta é uma **interface textual em tela cheia**, não ainda uma interface gráfica com compositor, janelas ou fontes renderizadas por GPU. A inferência MiniCPM local já foi confirmada em testes do VirtualBox do projeto, mas a qualidade das respostas continua dependente do modelo.

Código próprio sob MIT. Os componentes externos mantêm suas licenças. O xorriso é experimental e não deve ser instalado em computadores de produção.