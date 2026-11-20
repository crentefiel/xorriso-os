# xorriso OS — Linux minimalista centrado em IA

> **Alpha 0.7: protótipo experimental.** Ainda não é um sistema operacional completo.

O xorriso inicia com a tela **totalmente vazia**: sem barra de tarefas, menu, relógio, ícones ou aplicativos gráficos. **F1** mostra status, **F2** abre o console e **Esc** limpa a tela. A base é Linux + initramfs e um `/init` próprio em C.

## Funcionalidades atuais

- Inicialização mínima Linux x86_64 em BIOS legado por GRUB.
- Rede DHCP manual (`net up`, `net status`) para o adaptador Intel E1000 no VirtualBox.
- API externa compatível com OpenAI (`api url`, `api model`, `api key`, `ask`).
- Agente experimental (`agent`) com ações de lista fechada e confirmação antes de escrever uma nota temporária.
- Conector para futuro servidor local `llama.cpp` (`api local`, `local status`).

**Não incluído:** pesos do MiniCPM-V 4.7 1B, motor de inferência, ambiente gráfico, persistência em disco, instalador de aplicativos, Ghidra, REA. A IA não tem execução irrestrita de shell; a ISO é apenas para máquina virtual.

## ISO automática no GitHub

Vá até **Actions → xorriso Alpha 0.7 - Build and smoke test**. O workflow compila o `/init` a partir do código-fonte, prepara o initramfs com os utilitários necessários e empacota uma ISO BIOS com GRUB. O arquivo `xorriso-alpha-07-grub.iso` será um **artifact** do workflow se todos os passos passarem.

Requisitos da compilação: Ubuntu 24.04, `linux-image-generic`, BusyBox estático, GRUB e ferramentas indicadas em `.github/workflows/build-iso.yml`. Para compilar numa máquina Ubuntu com essas dependências:

```bash
bash src/test-ai.sh
python3 src/test-http-real.py
bash build-from-source.sh
```

No VirtualBox: Linux 64-bit, **EFI desativado**, RAM >= 1 GiB, adaptador de rede Intel PRO/1000 MT Desktop em NAT.

Depois de F2:

```text
help
net up
net status
api url https://seu-provedor.example/v1
api model IDENTIFICADOR_DO_MODELO
api key
api test
ask Ola, voce esta funcionando?
agent crie uma nota chamada ideias.txt com o texto Meu projeto
```

Não publique sua chave de API em issues, logs ou vídeos. A chave configurada pelo console fica somente na RAM. Notas temporárias também desaparecem ao reiniciar.

## MiniCPM-V 4.7 1B

O modelo local **não está incluído** nesta fase para preservar a ISO mínima. Veja [docs/MINICPM.md](docs/MINICPM.md). A intenção é baixar o runtime e pesos GGUF somente quando o usuário solicitar, em armazenamento persistente futuro.

## Validação e limites

Os testes de agente usam APIs **simuladas**. O workflow inclui um teste de inicialização direta do kernel no QEMU e tenta localizar o marcador emitido pelo `/init`. Um build do ISO ou um smoke test não substitui o teste de inicialização da própria ISO no VirtualBox; validar o boot completo e os comandos na ISO ainda é necessário.

O código deste repositório é licenciado sob MIT, conforme `LICENSE`. Linux/BusyBox e bibliotecas de terceiros retêm suas próprias licenças e obrigações. O nome **xorriso** também pertence a um utilitário GNU de processamento de ISO, não relacionado a este projeto.