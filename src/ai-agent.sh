#!/bin/sh
# IA plans are untrusted data: allowed actions ONLY, no arbitrary shell.
set -eu
PATH=/bin:/usr/bin:/sbin
CONF=${XORRISO_CONF_DIR:-/run/xorriso}
if [ -n "${XORRISO_NOTES_DIR:-}" ]; then
 NOTES=$XORRISO_NOTES_DIR
elif grep -q ' /data ext4 ' /proc/mounts 2>/dev/null; then
 NOTES=/data/notes
else
 NOTES=/tmp/xorriso/notas
fi
CURL_BIN=${XORRISO_CURL_BIN:-curl}
JQ_BIN=${XORRISO_JQ_BIN:-jq}
ACTION_BIN=${XORRISO_ACTION_BIN:-/usr/lib/xorriso/actions.sh}
ROOT_EXEC=${XORRISO_ROOT_EXEC_BIN:-/usr/lib/xorriso/root-exec.sh}
getconf() { cat "$CONF/$1" 2>/dev/null || :; }
if [ "${1:-}" = '--notes' ]; then
 mkdir -p "$NOTES"; echo "Notas em $NOTES:"
 ls -1 "$NOTES" 2>/dev/null || :
 exit 0
fi
PROMPT=${1:-}
[ -n "$PROMPT" ] || { echo 'Uso: agent seu pedido'; exit 2; }
BASE=$(getconf api_url); MODEL=$(getconf api_model); KEY=$(getconf api_key)
case "$BASE" in
 https://*) [ -n "$KEY" ] || { echo 'Use api key.'; exit 2; } ;;
 http://127.0.0.1:*|http://localhost:*) : ;;
 http://10.0.2.2:*) [ -z "$KEY" ] || { echo "API key bloqueada no HTTP do host virtual."; exit 2; } ;;
 *) echo 'Configure api url ou api local.'; exit 2 ;;
esac
[ -n "$MODEL" ] || { echo 'Configure api model.'; exit 2; }
umask 077
mkdir -p "$CONF" "$NOTES"
SYSTEM='Voce e a IA que controla as ferramentas reais do xorriso OS. Interprete livremente o pedido em portugues, mesmo quando as palavras variam. Nao procure frases fixas. Escolha UMA ferramenta pelo significado do pedido, usando APENAS: create_folder, list_folders, check_folder, create_file, list_files, read_file, status, net_status, list_notes, read_note, write_note, system_commands, system_capabilities, propose_command ou none. Para create_folder extraia em filename o NOME EXATO solicitado pelo usuario, jamais inclua palavras como chamado, chamada ou pasta se elas nao fazem parte do nome. Nao invente um nome quando faltar. Para check_folder use filename com o nome exato quando indicado; se o usuario se refere a ultima pasta criada, use filename vazio. Para create_file use filename com nome e extensao do arquivo e content com o texto que o usuario pediu; se nao houver texto, pode criar um arquivo vazio apenas se isso for claramente solicitado. Para read_file identifique filename e para list_files deixe filename vazio. Nenhuma ferramenta de arquivos pode sobrescrever arquivos existentes. Para administrar o Linux com comandos nao cobertos pelas ferramentas de arquivos, use propose_command: coloque em command UMA linha de shell Linux com comando exato e verificavel. Exemplo de programas simples: escreva codigo com create_file e depois proponha o comando para executar ou compilar. Nunca diga que executou quando apenas propoe. O executor mostrara o comando e exigira que a PESSOA digite um token de confirmacao, sem autoconfirmacao da IA. Comandos que apagam discos ou dados devem ser tratados como perigosos e revisados cuidadosamente. Nunca escolha none para dizer que criou, listou ou verificou algo; escolha a ferramenta correspondente. Quando o pedido for conversa comum, use none e message com resposta natural, breve, em portugues do Brasil. Se pedir algo sem ferramenta disponivel, use none e diga claramente a limitacao, sem fingir execucao. Somente propose_command pode conter comandos de terminal no campo command. Para as demais ferramentas, nao forneca comandos de terminal nem caminhos; nomes de pasta e arquivo nao podem conter barras. Se o usuario pedir abrir um programa grafico, explique que a interface atual ainda nao suporta janelas de programas externos; nao invente uma abertura grafica. Se for um pedido de comando Linux, use propose_command mesmo que nao exista frase cadastrada. Responda somente JSON valido e puro, sem markdown, com este esquema: {"action":"none","filename":"","content":"","command":"","message":""}.'
"$JQ_BIN" -n --arg model "$MODEL" --arg system "$SYSTEM" --arg question "$PROMPT" \
 '{model:$model,messages:[{role:"system",content:$system},{role:"user",content:$question}],temperature:0,stream:false}' \
 > "$CONF/agent-request.json"
if [ -n "$KEY" ]; then
 printf 'Authorization: Bearer %s\n' "$KEY" > "$CONF/api-auth-header"
 if ! "$CURL_BIN" -fSs --connect-timeout 8 --max-time 90 \
  -H 'Content-Type: application/json' -H "@$CONF/api-auth-header" \
  --data-binary "@$CONF/agent-request.json" "$BASE/chat/completions" \
  -o "$CONF/agent-response.json"; then
  echo 'Erro ao consultar IA via API.'; exit 1
 fi
else
 if ! "$CURL_BIN" -fSs --connect-timeout 8 --max-time 90 \
  -H 'Content-Type: application/json' \
  --data-binary "@$CONF/agent-request.json" "$BASE/chat/completions" \
  -o "$CONF/agent-response.json"; then
  echo 'Servidor local indisponivel.'; exit 1
 fi
fi
if ! "$JQ_BIN" -e '.choices[0].message.content | fromjson | select(type=="object")' \
 "$CONF/agent-response.json" > "$CONF/agent-plan.json" 2>/dev/null; then
 echo 'A IA nao retornou um plano JSON valido. Nenhuma acao realizada.'; exit 1
fi
ACTION=$("$JQ_BIN" -r '.action // "none"' "$CONF/agent-plan.json")
MESSAGE=$("$JQ_BIN" -r '.message // ""' "$CONF/agent-plan.json")
FILENAME=$("$JQ_BIN" -r '.filename // ""' "$CONF/agent-plan.json")
COMMAND=$("$JQ_BIN" -er '.command // "" | select(type=="string")' "$CONF/agent-plan.json") || { echo "Comando invalido."; exit 3; }
case "$ACTION" in
 none)
  printf 'IA: %s\n' "$MESSAGE"; echo 'Nenhuma acao executada.' ;;
 status)
  uname -a; cat /proc/uptime; echo 'Somente leitura.' ;;
 net_status)
  ip -4 addr show;ip route show;echo 'Somente leitura.' ;;
 list_notes)
  echo 'Notas:';ls -1 "$NOTES";echo 'Somente leitura.' ;;
 create_folder)
  [ -n "$FILENAME" ] || { echo 'A IA nao identificou o nome da pasta. Informe o nome.'; exit 2; }
  # Only the allowlisted executor touches the filesystem. Save only confirmed results.
  if result=$(/bin/sh "$ACTION_BIN" "--create:$FILENAME" 2>&1); then
   printf '%s\n' "$result"
   printf '%s\n' "$FILENAME" > "$CONF/last-folder"
  else
   printf '%s\n' "$result"
   exit 3
  fi ;;
 list_folders)
  /bin/sh "$ACTION_BIN" --list ;;
 propose_command)
  [ -n "$COMMAND" ] || { echo "A IA nao forneceu o comando Linux. Nada foi executado."; exit 2; }
  /bin/sh "$ROOT_EXEC" --propose "$COMMAND" ;;
 create_file)
  [ -n "$FILENAME" ] || { echo 'A IA nao identificou o nome do arquivo.'; exit 2; }
  CONTENT=$("$JQ_BIN" -er '.content | select(type=="string")' "$CONF/agent-plan.json") || {
   echo 'Conteudo de arquivo invalido. Nenhuma acao realizada.'; exit 3;
  }
  /bin/sh "$ACTION_BIN" "--write:$FILENAME" "$CONTENT" ;;
 list_files)
  /bin/sh "$ACTION_BIN" --files ;;
 read_file)
  [ -n "$FILENAME" ] || { echo 'A IA nao identificou qual arquivo deve ler.'; exit 2; }
  /bin/sh "$ACTION_BIN" "--read:$FILENAME" ;;
 check_folder)
  if [ -z "$FILENAME" ] && [ -s "$CONF/last-folder" ]; then
   FILENAME=$(cat "$CONF/last-folder")
  fi
  [ -n "$FILENAME" ] || { echo 'Ainda nao ha uma pasta criada e confirmada nesta sessao.'; exit 2; }
  /bin/sh "$ACTION_BIN" "--check:$FILENAME" ;;
 system_commands)
  /bin/sh /usr/lib/xorriso/command-catalog.sh --list ;;
 system_capabilities)
  /bin/sh /usr/lib/xorriso/command-catalog.sh --status ;;

 read_note|write_note)
  case "$FILENAME" in ''|.|..|.*) echo 'Nome invalido.'; exit 3 ;; esac
  # Compare the complete byte string. grep -E can accept one matching line
  # even when the filename also contains a newline or other control bytes.
  if [ "${#FILENAME}" -gt 64 ] || [ -z "$FILENAME" ]; then
   echo 'Nome invalido. Nenhuma acao realizada.'; exit 3
  fi
  case "$FILENAME" in
   [a-zA-Z0-9_-]*) : ;;
   *) echo 'Nome invalido. Nenhuma acao realizada.'; exit 3 ;;
  esac
  safe_name=$(printf '%s' "$FILENAME" | LC_ALL=C tr -cd 'a-zA-Z0-9_.-')
  if [ "$safe_name" != "$FILENAME" ]; then
   echo 'Nome invalido. Nenhuma acao realizada.'; exit 3
  fi
  TARGET="$NOTES/$FILENAME"
  if [ -L "$TARGET" ]; then echo 'Link simbolico rejeitado.'; exit 3; fi
  if [ "$ACTION" = 'read_note' ]; then
   if [ -f "$TARGET" ]; then cat "$TARGET"; else echo 'Nota nao encontrada.'; fi
   exit 0
  fi
  CONTENT=$("$JQ_BIN" -r '.content // "" | strings' "$CONF/agent-plan.json" 2>/dev/null) || { echo 'Texto invalido.'; exit 3; }
  [ "${#CONTENT}" -le 4096 ] || { echo 'Conteudo longo demais.'; exit 3; }
  echo "Plano: criar nota temporaria $FILENAME";printf 'Conteudo:\n%s\n' "$CONTENT"
  printf 'Autorizar gravacao? [s/N]: '
  IFS= read -r OK || OK=n
  case "$OK" in s|S|sim|SIM)
   (umask 077;printf '%s\n' "$CONTENT" > "$TARGET")
   echo "Nota criada em $TARGET" ;;
   *) echo 'Operacao cancelada.' ;;
  esac ;;
 *)
  echo "Acao '$ACTION' fora da lista permitida. Nada foi executado."; exit 3 ;;
esac
