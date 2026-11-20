# MiniCPM-V 4.7 1B — xorriso Alpha 0.8

**O modelo não está incluído na ISO.** O xorriso continua com tela vazia, console mínimo e nenhum disco persistente.

## Ponte para IA local no computador anfitrião

A Alpha 0.8 permite que o Linux convidado se conecte por NAT ao **modelo executado no computador que hospeda o VirtualBox ou QEMU**. Não é inferência dentro da VM, mas não depende de uma API de nuvem depois que os pesos estejam em cache.

Modelo oficial: https://huggingface.co/openbmb/MiniCPM-V-4.7-1B-gguf
Motor: https://github.com/ggml-org/llama.cpp

**Anfitrião Linux:** instale ou compile uma versão atual do llama-server e, quando quiser rodar a IA, execute sh tools/run-minicpm-host-linux.sh. A primeira execução pode baixar os pesos GGUF Q4_K_M no cache do anfitrião. Eles não entram na ISO.

**Anfitrião Windows:** instale uma versão atual de llama.cpp e, em um terminal no computador anfitrião:

~~~powershell
llama-server.exe -hf openbmb/MiniCPM-V-4.7-1B-gguf:Q4_K_M --host 127.0.0.1 --port 8080 --alias MiniCPM-V-4.7-1B
~~~

**Máquina virtual:** rede NAT, placa Intel PRO/1000 MT Desktop. Depois de F2:

~~~text
net up
local status
api host
api test
ask Ola, MiniCPM!
~~~

O comando api host seleciona http://10.0.2.2:8080/v1, sem enviar chaves de API. Esse endereço é uma convenção de NAT para alcançar o computador anfitrião; pode exigir ajustes conforme a configuração de rede VirtualBox/QEMU. Em alguns ambientes um servidor que escuta apenas 127.0.0.1 no anfitrião não é acessível pelo NAT. Não exponha o servidor à internet sem firewall e autenticação.

O comando api local seleciona http://127.0.0.1:8080/v1, que fica **dentro da VM**. Ainda não temos motor nem pesos do modelo dentro do xorriso.

## Limitações e testes

O modelo MiniCPM real **não é executado nos testes de CI**. O workflow usa um servidor compatível com OpenAI **simulado** e valida DHCP e HTTP entre a VM e o host. Isso não comprova inferência real nem disponibilidade de recursos multimodais.

A inferência dentro do próprio xorriso requer disco persistente, runtime compilado e pesos baixados sob demanda, limites de RAM/armazenamento, validação dos downloads e testes adicionais.
