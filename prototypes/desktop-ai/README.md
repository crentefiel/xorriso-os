# Alpha 0.15.5 — protótipo da interface gráfica por texto

Esta pasta contém **somente um protótipo visual**, independente do boot. Nenhuma ação Linux é executada, e nenhuma resposta é apresentada como se fosse resultado real do MiniCPM.

## Como experimentar

Abra `prototypes/desktop-ai/index.html` em um navegador desktop. O ícone "IA" abre a conversa; você pode minimizar, maximizar, fechar, mover a janela, criar sessões locais de conversa e escrever mensagens. O projeto não requer internet nem serviços externos.

## Critérios para a integração real (próxima etapa)

1. Preservar os discos `XORRISO_DATA` e `XORRISO_RUNTIME`, sem reparticionamento, formatação ou alteração de dados.
2. Construir uma sessão gráfica mínima no Linux (servidor gráfico, gerenciador de janelas e navegador/webview leve) com teclado ABNT2 e retorno para o console.
3. Exibir somente o ícone da IA na área de trabalho; abertura por clique; janela minimizável e independente das janelas de programas.
4. Conectar chat ao endpoint local do MiniCPM por um serviço intermediário que verifique disponibilidade, imponha timeout e mostre erros reais.
5. Conectar tarefas Linux exclusivamente ao executor existente ou a uma API de ações com esquema de entrada validado. Não oferecer shell root arbitrário à saída do modelo.
6. Não confirmar sucesso de ações antes de verificar o sistema de arquivos/estado real. Pedir confirmação explícita para tarefas com impacto ou destrutivas.
7. Adicionar testes QEMU/VirtualBox: boot, apresentação, abrir/minimizar/restaurar, texto, comando de pasta, listagem verificada, F2/F3 (se ainda suportados) e persistência nos dois VDI.
8. Microfone, reconhecimento de fala e síntese de voz fora do escopo desta primeira versão.

## Estado

Esta branch ainda **não contém uma ISO gráfica**. O protótipo HTML não substitui a tela TTY do sistema e não deve ser anunciado como funcionalidade implementada no boot.
