# xorriso OS — dois discos de IA opcionais

Protótipo Linux x86-64 mínimo centrado em IA. Ao iniciar, a tela é **totalmente preta e vazia** (sem barra, ícones, relógio, janelas ou desktop completo). **F1** informa o estado, **F2** mostra o console e **Esc** volta à tela vazia.

## Componentes

- ISO Linux mínima com GRUB/BIOS legado, rede DHCP e ferramentas de console;
- `api url`, `api model`, `api key`, `ask`: cliente OpenAI-compatível com HTTPS;
- `agent`: conjunto limitado de ações autorizadas e confirmação para escrever notas;
- `storage status`, `storage mount`: disco ext4 opcional `XORRISO_DATA`;
- `model install`, `model vision`, `model verify`: baixa pesos oficiais MiniCPM com confirmação e SHA-256;
- **Alpha 0.11:** `runtime status`, `runtime start`, `runtime stop`, `runtime log`: controle de um motor `llama-server` opcional, verificado por SHA-256, armazenado em um VDI de dados separado.

## Arquitetura da IA local

**A ISO não contém `llama.cpp` nem pesos de IA.** Um workflow independente em [GitHub Actions](https://github.com/crentefiel/xorriso-os/actions) compila um `llama-server` x86-64 **CPU-only** a partir do commit fixado de llama.cpp e o incorpora em um segundo disco VDI ext4 com rótulo `XORRISO_RUNTIME`. Assim, o runtime é instalado separadamente, sem aumentar a ISO.

O volume persistente é montado com `noexec`. Antes de iniciar o motor, o xorriso verifica o hash do servidor e o copia para a RAM executável em `/run/xorriso/llama`; os pesos são lidos no disco. O servidor é acessível **somente na VM, em 127.0.0.1:8080**.

### Uso previsto no VirtualBox

1. Desligue a VM; configure Linux de 64 bits, EFI desativado, pelo menos 4 GB de RAM e adaptador E1000 em NAT.
2. Baixe a ISO Alpha 0.11 e o VDI **com runtime** dos artefatos do GitHub Actions, depois que ambos os workflows passarem.
3. Monte a ISO como CD. **Mantenha o VDI original `XORRISO_DATA` com seus modelos** e adicione o novo VDI `XORRISO_RUNTIME` como outro disco rígido SATA; nunca substitua nem formate o primeiro.
4. Pressione F2 e digite:

```text
storage status
net up
model status
model verify
runtime status
runtime start
runtime log
api local
api test
ask Ola, MiniCPM!
```

**Cuidado:** o download real e a inferência MiniCPM dentro da VM requerem testes adicionais. `runtime start` só funciona se o VDI contiver um servidor cujo SHA-256 corresponda ao hash fixado no código. Mesmo com download correto, pode não haver RAM ou CPU suficiente. O comando não promete sucesso se o modelo não carregar.

Leia [docs/LOCAL-RUNTIME.md](docs/LOCAL-RUNTIME.md), [docs/STORAGE.md](docs/STORAGE.md) e [docs/MINICPM.md](docs/MINICPM.md).

## Limitações

O xorriso permanece experimental: não é uma distribuição de uso diário, não tem instalador de aplicativos, desktop gráfico completo nem criptografia do armazenamento. O modelo MiniCPM não é baixado automaticamente. **Os testes não executam inferência real com os pesos do MiniCPM**; verificam separadamente o executável `llama-server`, o gerenciador do modelo, a conexão HTTP simulada, o boot GRUB/F2/Esc e a persistência ext4.

Código próprio sob MIT; componentes upstream seguem suas licenças. A palavra `xorriso` também nomeia um utilitário GNU de ISO, sem relação com este projeto.
## Novo: preservar os pesos do MiniCPM usando dois discos separados

**Não substitua nem formate o VDI original.** Ele contém os pesos que já passaram por SHA-256.

- XORRISO_DATA: VDI original (rw), continua montado em /data, com /data/models e /data/notes.
- XORRISO_RUNTIME: VDI adicional de 256 MiB (ro), montado em /runtime-data, com /runtime/llama-server.

Desligue a VM. No VirtualBox, mantenha o VDI original e adicione xorriso-llama-runtime-only-256MiB.vdi como OUTRO disco rígido SATA. A ISO continua no leitor de CD. Use a ISO gerada com suporte aos dois volumes.

Depois de F2 execute:

```text
storage probe
storage mount
storage status
model verify
runtime status
runtime start
runtime log
api local
api test
ask Ola, MiniCPM!
```

O runtime é montado somente para leitura e copiado para RAM após validação do SHA-256. O modelo continua no VDI original. **A inferência real no VirtualBox ainda necessita de teste.**

Não utilize ao mesmo tempo o VDI antigo de runtime de 6 GiB (rótulo XORRISO_DATA) e o VDI original de modelos: isso duplicaria o rótulo.
