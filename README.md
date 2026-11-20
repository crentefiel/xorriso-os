# xorriso OS — Alpha 0.9 (desenvolvimento)

**Sistema operacional Linux mínimo centrado em IA — protótipo experimental para máquina virtual.**

O xorriso inicia em uma **tela totalmente preta e vazia**, sem barra, menu, relógio, ícones ou janelas. **F1** mostra informações; **F2** abre o console; **Esc** retorna à tela vazia.

## O que funciona

- Linux mínimo e GRUB para BIOS legado, initramfs e inicializador em C.
- Rede DHCP manual: `net up`, `net status`.
- APIs compatíveis com OpenAI por HTTPS: `api url`, `api model`, `api key`, `ask`.
- Agente experimental `agent`, com ações limitadas e confirmação para gravar notas.
- `api host`: conecta a VM ao MiniCPM executado separadamente no computador anfitrião via NAT. Não é inferência dentro da VM.
- **Novo:** `storage status` e `storage mount` para armazenamento ext4 persistente opcional com rótulo `XORRISO_DATA`.
- Quando o disco está montado, as notas do agente ficam em `/data/notes`, e `/data/models` fica preparada para futuros arquivos de IA.

## Como experimentar

Baixe a ISO nos artefatos do workflow [Actions](https://github.com/crentefiel/xorriso-os/actions) após os testes passarem. Crie uma VM Linux 64-bit com BIOS legado, 1 GB de RAM ou mais, NAT e adaptador Intel PRO/1000 MT Desktop.

Pressione F2 e experimente:

```text
help
storage status
net up
api host
api test
```

Para criar um segundo disco ext4 sem substituir arquivos, siga [docs/STORAGE.md](docs/STORAGE.md). O volume é opcional; sem ele o xorriso continua com tela vazia e notas temporárias na RAM.

Para conversar com um modelo MiniCPM real no **computador anfitrião**, veja [docs/MINICPM.md](docs/MINICPM.md).

## Verificações automáticas

O GitHub Actions compila o /init, gera a ISO GRUB, testa o boot ISO/F2/Esc no QEMU e testa a rede com API simulada. Na Alpha 0.9, também testa escrita e leitura do mesmo disco ext4 em dois boots separados.

**Ainda não incluídos:** ambiente gráfico, modelo MiniCPM dentro do xorriso, instalador de programas, Ghidra/REA e criptografia de dados. A ISO não deve ser usada para dados sensíveis ou no computador principal.