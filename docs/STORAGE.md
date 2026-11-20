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

## Solução de problemas no VirtualBox (SATA/IDE)

Se aparecer **"Sem volume persistente. Notas continuam na RAM"**:

1. **Desligue a VM completamente**, sem salvar o estado.
2. Abra **Configurações → Armazenamento** no VirtualBox.
3. Confirme que `xorriso-data-6GiB.vdi` ou `xorriso-ai-runtime-6GiB.vdi` está anexado como **disco rígido**, nunca como mídia óptica. Mantenha a ISO no leitor de CD.
4. Não anexe os dois VDIs ao mesmo tempo: ambos usam o rótulo `XORRISO_DATA` e criariam ambiguidade. Faça backup se o VDI antigo contiver dados.
5. Inicialize uma ISO que inclua os drivers **AHCI/SATA** (a correção é testada na versão posterior à Alpha 0.11).
6. Abra F2 e digite:
   ```text
   storage probe
   storage mount
   storage status
   ```
7. `storage probe` deve listar ao menos um disco SATA como `sda` ou `sdb` (ou um IDE equivalente). Se não listar, o kernel não está reconhecendo o controlador ou o disco não foi anexado. Se listar mas não montar, inspecione o rótulo e a formatação ext4.

O volume fornecido pelo GitHub é um ext4 **diretamente no disco virtual inteiro**, sem tabela de partições. Isso é intencional: um `sda` (sem `sda1`) pode ser correto. **Nunca formate o disco da VM por tentativa e erro**; os dados podem ser perdidos.

A verificação automática de persistência usa o mesmo arquivo de disco em dois boots do QEMU, agora tanto em controlador **IDE** quanto em controlador **AHCI/SATA**. Isso valida o funcionamento no QEMU; ainda é preciso testar a configuração específica do VirtualBox.
