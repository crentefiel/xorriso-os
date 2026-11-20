# Motor MiniCPM local — VDI separado


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

O motor llama-server é compilado a partir do commit upstream fixo b1b770d90d94cad9e9ea5b993bdbc383a522fb28, CPU-only e verificado pelo SHA-256 incluído na ISO. A build do motor e sua cópia no VDI não provam inferência com os pesos reais. O servidor, quando iniciado, deve escutar apenas em 127.0.0.1:8080 dentro da VM.
