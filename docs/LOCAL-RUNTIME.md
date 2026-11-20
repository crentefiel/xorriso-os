# Alpha 0.11 — Motor local do xorriso (experimental)

## O que realmente é instalado

O motor de inferência `llama.cpp` é compilado em um workflow separado, por segurança e para **não inflar a ISO**. A origem é o repositório oficial https://github.com/ggml-org/llama.cpp, commit imutável `b1b770d90d94cad9e9ea5b993bdbc383a522fb28` (release v1.0.0). O workflow tenta gerar um `llama-server` Linux x86-64 estático, CPU-only, e coloca o executável no diretório `/runtime` de um VDI ext4.

O volume ext4 de dados usa rótulo `XORRISO_DATA`. A ISO monta-o em `/data` com `noexec`; quando o usuário executa `runtime start`, o sistema verifica o SHA-256 fixado no código e copia o executável para `/run/xorriso/llama` (RAM executável). Nenhum arquivo externo é executado diretamente do volume de dados.

**Esta etapa não baixa automaticamente nenhum arquivo da IA.** O modelo GGUF continua sendo instalado com `model install` e seu projetor opcional com `model vision`, após confirmação explícita.

## Como testar no VirtualBox

1. Desligue a VM.
2. Substitua o VDI de dados vazio pelo VDI que contém o runtime (não use os dois simultaneamente; ambos usam o mesmo rótulo). **Faça backup de qualquer VDI com dados antes de substituí-lo.**
3. Deixe a ISO montada como CD. Selecione BIOS legado e rede NAT.
4. Configure pelo menos 4 GiB de RAM para testes reais do modelo (o desempenho depende da CPU e da memória disponíveis).
5. Abra o console com F2 e execute:

```text
storage status
net up
model install
model verify
runtime status
runtime start
runtime log
api local
api test
ask Ola, voce esta funcionando?
```

Se `runtime start` não conseguir executar ou carregar o modelo, `runtime log` mostrará as últimas linhas do servidor. O xorriso nunca executa um binário com SHA diferente do fixado e **não contorna esse controle automaticamente**. `runtime stop` encerra o servidor gerenciado.

## O que os testes provam

- O CI de runtime compila o projeto upstream a partir de um commit fixo, checa o ELF e seu SHA-256 e cria um VDI ext4 dinâmico com o binário.
- O CI da ISO compila o Linux, testa GRUB, F2, Esc, rede simulada, persistência e as operações do gerenciador com um servidor falso.
- A inferência real do MiniCPM só poderá ser confirmada com um ambiente que tenha baixado os pesos reais, RAM adequada e uma interação bem-sucedida.

**Não use o VDI para guardar segredos:** o ext4 não tem criptografia. Não exponha a porta do servidor à rede externa; a configuração padrão limita o serviço a `127.0.0.1` da máquina virtual.