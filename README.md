# xorriso OS — Alpha 0.10 (candidato)

**Linux mínimo experimental centrado em IA.** O xorriso inicia com a **tela preta totalmente vazia**: sem ícones, relógio, janelas ou barra. **F1** mostra o estado, **F2** abre o console e **Esc** volta à tela vazia.

## Funcionalidades

- Inicialização Linux por GRUB/BIOS, rede DHCP, console ocultável.
- APIs compatíveis com OpenAI: `api url`, `api model`, `api key`, `ask` (rede e chave do provedor são necessárias).
- Agente experimental com ações limitadas e confirmação para escrever notas.
- `storage status` / `storage mount`: volume ext4 opcional `XORRISO_DATA`, separado da ISO, para notas persistentes.
- **Novo gerenciador de modelo:** `model status`, `model install`, `model vision`, `model verify`. Downloads somente sob confirmação do usuário, para `/data/models`, com hash SHA-256 oficial fixado. Sem disco persistente, não é possível instalar pesos.

## Instalar os pesos oficiais do MiniCPM-V 4.7 1B

Use uma VM com rede e um segundo disco ext4 rotulado `XORRISO_DATA`, com pelo menos 3 GB livres (6 GB recomendados). Configure a placa Intel PRO/1000 MT Desktop em NAT e use mais RAM para o futuro motor de inferência. Pressione F2:

```text
storage status
net up
model status
model install
model vision
model verify
```

O `model install` baixa o GGUF `Q4_K_M` (~672 MB); `model vision` baixa o projetor visual (~1,11 GB). Cada operação pede confirmação, verifica SHA-256 e somente depois coloca o arquivo no disco. A ISO não baixa nenhum modelo por conta própria. Leia [docs/MINICPM.md](docs/MINICPM.md) e [docs/STORAGE.md](docs/STORAGE.md).

**Importante:** o GGUF é apenas o arquivo do modelo. O executável `llama.cpp`/ `llama-server` e a inferência **dentro da VM ainda não foram integrados**. Para uma IA real atualmente, use `api host` com um servidor no anfitrião, ou configure sua API remota por HTTPS.

## Testes e download

O [GitHub Actions](https://github.com/crentefiel/xorriso-os/actions) compila o Linux, gera a ISO, testa seu boot pelo GRUB no QEMU, os atalhos F2/Esc, a rede com servidor simulado, a persistência ext4 entre dois boots e a lógica do gerenciador de modelo com arquivos de teste pequenos (sem baixar pesos reais).

Esta é uma prova de conceito. **Não use na máquina principal nem armazene segredos.** Os dados no volume ext4 não são criptografados. O código próprio é MIT; bibliotecas de terceiros mantêm suas licenças. O nome xorriso também identifica um utilitário GNU não relacionado.
