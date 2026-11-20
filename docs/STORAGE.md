# xorriso Alpha 0.9 — Armazenamento persistente opcional

O xorriso **continua iniciando com a tela totalmente vazia**. Não há barra, menu, relógio, ícones ou ambiente gráfico completo.

## Por que um disco separado?

A ISO funciona em memória e não tem instalador. Uma segunda unidade ext4 com o rótulo exato **XORRISO_DATA** pode guardar notas entre reinicializações e reservar uma pasta para modelos de IA. Sem essa unidade, o sistema se comporta como antes: dados temporários somem ao reiniciar.

**O xorriso não cria, particiona nem formata discos.** Ele somente procura um volume ext4 com o rótulo correspondente e tenta montá-lo em `/data` com as opções `nosuid,nodev,noexec`.

## Criar o arquivo de disco em um Linux anfitrião

É necessário ter `mkfs.ext4` e `truncate`. No diretório do projeto:

```bash
bash tools/create-data-disk.sh xorriso-data.img 6G
```

O script recusa sobrescrever um arquivo existente. A imagem é esparsa: não ocupa todo o espaço lógico de imediato. **Não execute isso em discos reais ou em arquivos importantes.**

Depois anexe `xorriso-data.img` como **segundo disco** na VM do QEMU. No VirtualBox, converta uma cópia desse arquivo em VDI pelo `VBoxManage convertfromraw` e anexe como segundo disco em uma controladora compatível; suporte aos controladores ainda exige testes em cada versão do VirtualBox.

## Comandos no xorriso

Na tela preta, pressione F2:

```text
storage status
storage mount
storage status
notes
```

Sem volume, `notes` continua usando /tmp. Com volume montado, as notas feitas pelo agente ficam em `/data/notes` e sobrevivem a reinicializações.

A pasta `/data/models` está reservada para o MiniCPM-V 4.7 1B e modelos futuros. **A Alpha 0.9 ainda não executa o modelo dentro da VM**: o motor `llama.cpp`, o download verificado dos pesos GGUF e o serviço de inferência serão próximos marcos.

## Verificação automática

O GitHub Actions cria um pequeno arquivo ext4 com o rótulo XORRISO_DATA, inicia o kernel duas vezes no QEMU com o mesmo disco, grava e relê uma nota, e mantém a automação de boot completo da ISO via GRUB e os atalhos F2/Esc.

Os testes não formatam discos físicos, apenas um arquivo temporário criado pela CI.

## Segurança

O sistema permanece experimental, sem endurecimento completo. Dados persistentes não são criptografados. Não grave informações sensíveis. As chaves das APIs compatíveis com OpenAI continuam somente na memória volátil, sem serem copiadas para o disco.