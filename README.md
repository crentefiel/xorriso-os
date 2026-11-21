# xorriso OS — Alpha 0.13 (recuperação confiável do histórico)

O xorriso continua sendo um protótipo Linux mínimo centrado em IA. Tela inicial **completamente preta e vazia**, sem barra, relógio ou ícones. F1 informa o estado, F2 abre o console, Esc retorna à tela preta.

## Por que essa atualização?

No VirtualBox, a Alpha 0.12 executou o MiniCPM local, respondeu em português, armazenou **duas trocas** e aceitou `chat clear`. Entretanto, diante de `ask Qual foi minha pergunta anterior?`, respondeu erroneamente que não havia pergunta anterior. Isso mostra que **ter o histórico no JSON não garante que um modelo pequeno consiga usá-lo corretamente**.

A Alpha 0.13 introduz uma consulta direta e determinística ao histórico em RAM:

- `chat status`: quantidade de trocas registradas em memória.
- **`chat last`**: exibe literalmente a última mensagem do usuário disponível no histórico, sem chamar IA e sem rede.
- `chat clear`: apaga histórico e arquivos temporários de perguntas e respostas na RAM.
- Quando a **IA local** recebe `ask Qual foi minha pergunta anterior?` ou `ask O que eu te perguntei anteriormente?`, o xorriso consulta os registros reais e identifica o resultado como uma **consulta ao histórico local**, em vez de pedir ao MiniCPM que adivinhe.

O histórico mantém apenas as últimas quatro trocas de conversa (oito mensagens usuário/assistente), apenas em `/run/xorriso` (RAM). `api local`, `api host` ou alteração de modelo/URL limpa o histórico.

## Como testar no VirtualBox

Substitua **somente a ISO**. Preserve o VDI `XORRISO_DATA` que contém os pesos verificados do MiniCPM e o VDI `XORRISO_RUNTIME` com o motor `llama-server`.

```text
storage status
runtime start
api local
ask Ola, quem e voce?
chat last
ask Qual foi minha pergunta anterior?
chat status
chat clear
chat last
```

Após a primeira pergunta, `chat last` deverá retornar `Ola, quem e voce?`. A pergunta sobre o histórico também deverá mostrar o texto exato, mas com o prefixo `Consulta ao historico local`, para deixar explícito que **não foi uma resposta gerada pelo modelo**.

## Testes e limites

GitHub Actions compila a ISO, testa o boot com GRUB, tela vazia/F2/Esc, rede, TCP localhost, discos SATA/IDE e VDIs separados. Testes de HTTP simulam um servidor OpenAI-compatível e verificam que a recuperação da pergunta anterior é exata e **não faz requisição ao modelo**.

O MiniCPM pode errar outros pedidos de memória ou conversação. A melhoria é deliberadamente limitada a consultas claras sobre a pergunta anterior, sem fingir uma capacidade de memória geral. O sistema permanece experimental, sem interface gráfica completa, criptografia de dados nem instalador automático. Não use para dados sensíveis.
