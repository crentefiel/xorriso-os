# xorriso OS — Alpha 0.12 (conversa natural em IA local)

Protótipo experimental de Linux centrado em IA. A tela permanece **totalmente preta e vazia** ao iniciar, sem barra, relógio ou ícones. **F1** mostra informações, **F2** abre o console, **Esc** volta à tela preta.

## Novidades da Alpha 0.12

O vídeo do VirtualBox confirmou que o MiniCPM-V 4.7 1B carregou, a API interna respondeu na porta 8080 e o comando `ask` gerou texto. A resposta usou um banner decorativo; a Alpha 0.12 adiciona um **prompt de sistema apenas para a IA local** para solicitar respostas curtas em português brasileiro, com texto simples, sem emojis, arte ASCII ou Markdown.

O comando `ask` agora carrega até **quatro trocas anteriores** (oito mensagens usuário/assistente), guardadas **somente na memória RAM**. Nenhuma conversa é gravada no VDI. A mensagem inicial é limpa ao trocar de modelo ou endpoint pelo console. Para conferir e limpar manualmente:

```text
chat status
chat clear
```

No VirtualBox, mantendo a ISO como CD e os VDIs anteriores (XORRISO_DATA e XORRISO_RUNTIME), pressione F2:

```text
storage status
runtime start
runtime status
api local
ask Ola, quem e voce?
ask Voce consegue lembrar da minha ultima pergunta?
chat status
chat clear
```

A ISO nova **não altera nem formata os seus VDIs**. O MiniCPM GGUF continua em `/data/models`, e o servidor `llama-server` verificado fica no segundo VDI de runtime. Esse motor não está embutido na ISO, preservando o tamanho do sistema.

## Componentes anteriores

Rede DHCP, discos persistentes separados por rótulo ext4, downloads de GGUF com SHA-256, motor `llama-server` local verificado, cliente para APIs HTTPS compatíveis com OpenAI e agente experimental de operações permitidas.

## Limitações e validação

Os testes do GitHub verificam requisições JSON, memória de conversa na RAM, limpeza, API simulada, boot GRUB da ISO, F2/Esc, TCP localhost, SATA/IDE e dois VDIs separados. **O prompt não garante respostas corretas ou sem caracteres decorativos**: a qualidade real depende do MiniCPM e precisa ser testada novamente no VirtualBox.

O xorriso ainda não tem desktop gráfico completo, instalador automático de aplicativos, criptografia de dados ou ferramenta gráfica para controle da IA. É um protótipo para VM, não para uso diário. Código próprio sob MIT; componentes de terceiros respeitam suas licenças.
