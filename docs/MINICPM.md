# MiniCPM-V 4.7 1B — Alpha 0.10 do xorriso

O gerenciador `model` instala **sob demanda os pesos oficiais GGUF**, mas não instala nem executa o motor de inferência `llama.cpp` dentro do xorriso ainda. A ISO fica pequena porque nem os pesos nem o motor são embarcados.

## Arquivos oficiais

Fonte: [openbmb/MiniCPM-V-4.7-1B-gguf](https://huggingface.co/openbmb/MiniCPM-V-4.7-1B-gguf) (licença Apache-2.0).

| Comando | Arquivo oficial | Tamanho aproximado |
| --- | --- | --- |
| `model install` | `MiniCPM-V-4_7-1B-Q4_K_M.gguf` | 672 MB |
| `model vision` | `mmproj-model-f16.gguf` | 1,11 GB |

Os SHA-256 verificados automaticamente pelo xorriso (conforme os metadados oficiais):

- Q4_K_M: `f18f594747e5317ab490cff9c06339c9cfb89acbe2f02ebc48a4e167bc23576d`.
- Projetor: `fb9cc047a3cdad5317fd8433a4aeda2d22f00f02ca4bd93b34ad84165b25a900`.

Se a origem mudar os arquivos, o download será rejeitado em vez de aceitar bytes diferentes. Não desative a checagem para contornar um erro.

## Executar na máquina virtual

1. Configure BIOS legado (EFI desligado), placa E1000 no VirtualBox NAT, RAM e um **segundo** disco ext4 rotulado `XORRISO_DATA`. Veja [STORAGE.md](STORAGE.md).
2. Pressione F2 e execute `storage status`, `net up`, `model status`.
3. Digite `model install` e responda **s** para baixar os pesos.
4. Opcionalmente `model vision` para a capacidade de imagens.
5. Use `model verify` para recalcular os hashes após download.

São aproximadamente 1,8 GB de arquivos para usar modelo e visão juntos; reserve pelo menos 3 GB livres, preferencialmente 6 GB. O modelo real precisará de mais RAM além do tamanho de arquivo. Em VM de apenas 1 GB, **não há garantia de inferência viável**.

## Limite importante

`model install` ainda **não torna o comando `ask` uma inferência dentro da VM**. O próximo marco é um motor `llama-server` verificado, executado por demanda dentro do Linux convidado, usando `/data/models`. A conexão `api local` já aponta a 127.0.0.1:8080 da própria VM, mas não inicia um servidor.

Enquanto isso, `api host` pode conectar um servidor `llama.cpp` no computador anfitrião via NAT, conforme a documentação anterior; não confunda o anfitrião com o convidado.

Os testes automatizados desta versão usam **pesos simulados minúsculos**, sem baixar ou executar o MiniCPM verdadeiro.