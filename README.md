# xorriso OS — Alpha 0.8

**Sistema operacional Linux mínimo centrado em IA — protótipo experimental.**

O xorriso inicia com a **tela preta totalmente vazia**, sem barra, menu, relógio, ícones ou janelas. F1 mostra informações, F2 abre o console e Esc volta à tela vazia.

## Funcionalidades

- Kernel Linux, GRUB BIOS legado, initramfs e inicializador próprio em C.
- Rede DHCP manual: comandos net up, net status, net down.
- Cliente OpenAI compatível por HTTPS: api url, api model, api key, api test, ask.
- Agente experimental: comando agent com ações restritas e autorização para criar notas temporárias.
- **Novo: api host** usa HTTP no gateway NAT 10.0.2.2:8080 para conectar o MiniCPM executado no **computador anfitrião da VM**. Chaves de API são bloqueadas nesse HTTP sem criptografia.
- api local aponta para 127.0.0.1 **da VM**, mas o modelo e o runtime ainda não estão instalados dentro dela.

## Executar no VirtualBox

VM Linux 64 bits, 1 GiB ou mais de RAM, EFI desativado, NAT, placa Intel PRO/1000 MT Desktop. Baixe a ISO dos artefatos em [GitHub Actions](https://github.com/crentefiel/xorriso-os/actions).

No console F2, depois de iniciar o servidor MiniCPM no anfitrião:

~~~text
net up
local status
api host
api test
ask Ola, MiniCPM!
~~~

Veja [docs/MINICPM.md](docs/MINICPM.md) e [tools/run-minicpm-host-linux.sh](tools/run-minicpm-host-linux.sh) para iniciar o servidor local no anfitrião. A ponte pode exigir ajustes na rede VirtualBox.

Para conectar uma API externa por HTTPS:

~~~text
api url https://provedor.example/v1
api model IDENTIFICADOR
api key
api test
ask Ola
~~~

Não divulgue suas chaves de API. Notas e configuração ficam apenas em RAM.

## Construção e testes

O GitHub Actions compila o inicializador, gera a ISO GRUB, testa o boot da própria ISO e os atalhos F2/Esc em QEMU. A Alpha 0.8 também testa a rede convidado→anfitrião contra **API simulada**, não inferência com MiniCPM verdadeiro.

~~~bash
bash src/test-ai.sh
python3 src/test-http-real.py
bash build-from-source.sh
~~~

**Ainda faltam:** desktop gráfico real, armazenamento persistente, MiniCPM rodando dentro do xorriso, instalação autônoma de programas, Ghidra e REA. Esta ISO é experimental, para testes em máquina virtual. Código novo sob MIT; componentes terceiros têm licenças próprias. O nome xorriso também é usado por um utilitário GNU diferente.
