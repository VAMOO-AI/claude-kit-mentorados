#!/usr/bin/env bash
# Prova do scripts/env-tem-chave.sh: diz se a chave existe sem NUNCA imprimir o valor.
#
# Ele substitui a receita `grep -c '^KEY=' .env.local`, que o deny `Read(//**/.env.local)`
# nega desde 15/10/2026 (antes ela só passava porque o rtk reescrevia o grep e o deny não
# reconhecia a leitura). O que esta suíte segura: a saída é só o veredito por chave, e
# nenhum valor da fixture aparece nela, nem em erro.
#
# Uso: bash tests/test-env-tem-chave.sh [caminho-do-script]
set -uo pipefail
S="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/env-tem-chave.sh}"
[ -f "$S" ] || { echo "script não encontrado: $S"; exit 2; }

falhas=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/envchave.XXXXXX")
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

F="$TMP/.env.local"
cat > "$F" <<'ENV'
# comentario: NAO_E_CHAVE=valor-do-comentario
TOKEN=valor-secreto-1
VAZIA=
ASPAS_VAZIAS=""
export EXPORTADA=valor-secreto-2
  COM_ESPACO = valor-secreto-3
DUPLICADA=valor-secreto-4
DUPLICADA=
CRLF=valor-secreto-5
ENV
printf 'CRLF_VAZIA=\r\n' >> "$F"

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
espera() { # espera <descrição> <saída esperada> <comando...>
  local d="$1" e="$2"; shift 2
  local out; out=$("$@" 2>&1)
  [ "$out" = "$e" ] && ok "$d" || falha "$d (esperado '$e', veio '$out')"
}

echo "== veredito por chave =="
espera "presente"                       "TOKEN: presente"        bash "$S" "$F" TOKEN
espera "vazia"                          "VAZIA: vazia"           bash "$S" "$F" VAZIA
espera "aspas vazias contam como vazia" "ASPAS_VAZIAS: vazia"    bash "$S" "$F" ASPAS_VAZIAS
espera "export KEY= conta"              "EXPORTADA: presente"    bash "$S" "$F" EXPORTADA
espera "ausente"                        "NAO_EXISTE: ausente"    bash "$S" "$F" NAO_EXISTE
espera "chave dentro de comentário não conta" "NAO_E_CHAVE: ausente" bash "$S" "$F" NAO_E_CHAVE
espera "prefixo não casa (TOK ≠ TOKEN)" "TOK: ausente"           bash "$S" "$F" TOK
espera "a última atribuição vence, como no shell" "DUPLICADA: vazia" bash "$S" "$F" DUPLICADA
espera "CR do Windows não vira valor"   "CRLF_VAZIA: vazia"      bash "$S" "$F" CRLF_VAZIA
espera "espaço em volta do = conta"     "COM_ESPACO: presente"   bash "$S" "$F" COM_ESPACO
espera "várias chaves, uma por linha" "$(printf 'TOKEN: presente\nVAZIA: vazia\nNAO_EXISTE: ausente')" \
                                                                  bash "$S" "$F" TOKEN VAZIA NAO_EXISTE

echo
echo "== código de saída =="
bash "$S" "$F" TOKEN EXPORTADA >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "todas presentes → 0" || falha "todas presentes → 0 (veio $rc)"
bash "$S" "$F" TOKEN VAZIA >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "alguma vazia ou ausente → 1" || falha "alguma vazia ou ausente → 1 (veio $rc)"
bash "$S" "$TMP/nao-existe.env" TOKEN >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "arquivo inexistente → 2" || falha "arquivo inexistente → 2 (veio $rc)"
bash "$S" "$F" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "sem chave → 2 (uso)" || falha "sem chave → 2 (veio $rc)"
bash "$S" "$F" 'TOKEN.*' >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "nome de chave inválido (regex) → 2" || falha "nome inválido → 2 (veio $rc)"
# Falha de leitura não pode virar "ausente" com rc=1: quem lê concluiria que a chave falta.
mkdir -p "$TMP/sem-awk"
out=$(PATH="$TMP/sem-awk" /bin/bash "$S" "$F" TOKEN 2>&1); rc=$?
[ "$rc" = 2 ] && ok "awk que falha → 2, não 'ausente'" || falha "awk que falha → 2 (veio $rc: $out)"
case "$out" in *ausente*) falha "awk que falha não pode dizer 'ausente'" ;; *) ok "awk que falha não diz 'ausente'" ;; esac

echo
echo "== nenhum valor sai, nem em erro =="
tudo=$( { bash "$S" "$F" TOKEN VAZIA ASPAS_VAZIAS EXPORTADA COM_ESPACO DUPLICADA CRLF CRLF_VAZIA NAO_E_CHAVE NAO_EXISTE
          bash "$S" "$F" 'TOKEN.*'; bash "$S" "$F"; bash "$S" "$TMP/x"; } 2>&1 )
if printf '%s' "$tudo" | grep -q 'valor-'; then falha "algum valor vazou: $(printf '%s' "$tudo" | grep 'valor-')"
else ok "nenhum 'valor-…' na saída nem no stderr"; fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
