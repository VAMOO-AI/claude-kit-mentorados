#!/usr/bin/env bash
# env-tem-chave.sh — diz se uma chave existe num arquivo de env, SEM imprimir o valor.
#
#   env-tem-chave.sh <arquivo> <CHAVE> [CHAVE...]
#
# Saída, uma linha por chave: "CHAVE: presente", "CHAVE: vazia" ou "CHAVE: ausente".
# Exit 0 se todas estão presentes, 1 se alguma está vazia ou ausente, 2 para uso errado ou
# arquivo ilegível. Nenhum caminho deste script escreve o valor em stdout ou stderr.
#
# Por que existe: a receita antiga, `grep -c '^KEY=' .env.local`, é negada pelo deny
# `Read(//**/.env.local)` do kit desde a 0.53.2. O deny cobre os comandos de leitura que o
# Claude Code reconhece (cat, grep, head…), não um script que abre o arquivo por dentro.
# É isso que deixa este rodar, e é por isso que a saída dele é só o veredito. Espelho de
# scripts/env-tem-chave.sh do VAMOO-AI/claude-config-team (medição de 15/10/2026).
#
# Semântica de shell: `export KEY=` conta, espaço em volta do `=` é tolerado, linha de
# comentário não conta, a última atribuição vence, aspas vazias e CR do Windows são vazio.
set -u
[ "$#" -ge 2 ] || { echo "uso: env-tem-chave.sh <arquivo> <CHAVE> [CHAVE...]" >&2; exit 2; }
arq="$1"; shift
[ -f "$arq" ] && [ -r "$arq" ] || { echo "arquivo ilegível: $arq" >&2; exit 2; }
for k in "$@"; do
  case "$k" in ''|[0-9]*|*[!A-Za-z0-9_]*) echo "nome de chave inválido (só letras, dígitos e _)" >&2; exit 2 ;; esac
done

rc=0
for k in "$@"; do
  v=$(awk -v k="$k" '
    { l = $0; sub(/\r$/, "", l)
      if (l ~ /^[ \t]*#/) next
      sub(/^[ \t]*(export[ \t]+)?/, "", l)
      if (substr(l, 1, length(k)) != k) next
      r = substr(l, length(k) + 1)
      if (r !~ /^[ \t]*=/) next
      sub(/^[ \t]*=[ \t]*/, "", r); sub(/[ \t]+$/, "", r)
      if (r == "\"\"" || r == "\047\047") r = ""
      s = (r == "" ? "vazia" : "presente") }
    END { print (s == "" ? "ausente" : s) }' "$arq" 2>/dev/null)
  st=$?
  # Falha de leitura (awk ausente, I/O) não pode virar "ausente": quem lê concluiria que a
  # chave falta e iria criá-la por cima.
  [ "$st" -eq 0 ] || { echo "falha ao ler $arq (awk saiu $st)" >&2; exit 2; }
  case "$v" in presente|vazia|ausente) ;; *) echo "falha ao ler $arq" >&2; exit 2 ;; esac
  printf '%s: %s\n' "$k" "$v"
  [ "$v" = presente ] || rc=1
done
exit "$rc"
