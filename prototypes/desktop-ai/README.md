# Alpha 0.15.5 — protótipo da interface gráfica por texto

Esta pasta contém o protótipo visual e uma ponte HTTP de desenvolvimento para conversar com um MiniCPM já disponível no computador Linux. Ela não inicia o modelo nem executa ações Linux, e ainda não está incluída na ISO de boot.

## Como experimentar

Em um computador com Python 3, navegador e um servidor OpenAI-compatible já funcionando em `127.0.0.1:8080/v1`, execute `python3 prototypes/desktop-ai/bridge.py`, depois abra `http://127.0.0.1:8765`. O ícone IA abre a conversa, que pode ser minimizada, maximizada, fechada e movida. A troca de texto é encaminhada ao servidor de modelo local, e erros reais são exibidos no chat. Não abra o HTML via `file://`, pois o bridge serve a interface e a API na mesma origem. Para testar sem carregar o modelo, rode `python3 prototypes/desktop-ai/test_bridge.py`; ele usa um MiniCPM simulado. A ponte escuta apenas em `127.0.0.1`, não oferece execução de comandos e guarda o histórico somente na sessão da página.

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
