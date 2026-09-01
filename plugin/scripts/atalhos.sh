#!/usr/bin/env bash
# Ledger dos atalhos deliberados: todo comentário `atalho:` no repositório, em
# uma tela, com quem não tem gatilho de revisão marcado.
#
# A convenção (vale em qualquer linguagem, no prefixo de comentário dela):
#
#   // atalho: lock global; por conta se passar de 50 req/s
#   #  atalho: lê o CSV inteiro em memória; stream quando passar de 100 MB
#   -- atalho: sem índice em created_at; criar quando a tabela passar de 1M linhas
#
# Antes do `;` é o TETO (o que foi simplificado e até onde aguenta). Depois é o
# GATILHO (quando revisitar). Atalho sem `;` não tem gatilho e é o que apodrece:
# "depois" sem condição é nunca.
#
#   atalhos.sh            # ledger do repositório atual
#   atalhos.sh src/api    # só um diretório
#   atalhos.sh --blame    # inclui autor e data de cada linha
set -uo pipefail

BLAME=0; ALVO=.
for a in "$@"; do case "$a" in --blame) BLAME=1 ;; -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; *) ALVO="$a" ;; esac; done

# prefixos de comentário: // # -- /* * <!-- ;  — e nada de casar prosa que só cita a palavra
PADRAO='(//|#|--|/\*|\*|<!--|;)[[:space:]]*atalho:'
if git -C "$ALVO" rev-parse --show-toplevel >/dev/null 2>&1; then
  LINHAS=$(git -C "$ALVO" grep -n -E -I "$PADRAO" -- . ':!*.lock' ':!*.min.*' 2>/dev/null | sed "s#^#$ALVO/#; s#^\./##")
else
  LINHAS=$(grep -rn -E -I --exclude-dir={node_modules,.git,dist,build,.next,coverage} "$PADRAO" "$ALVO" 2>/dev/null)
fi

if [ -z "$LINHAS" ]; then echo "Nenhum atalho marcado em $ALVO. Ledger limpo."; exit 0; fi

total=0; sem=0; arquivo_atual=""
while IFS= read -r linha; do
  arq="${linha%%:*}"; resto="${linha#*:}"; num="${resto%%:*}"; txt="${resto#*:}"
  corpo=$(printf '%s' "$txt" | sed -E "s/.*atalho:[[:space:]]*//; s/[[:space:]]*(\*\/|-->)[[:space:]]*$//")
  if [ "$arq" != "$arquivo_atual" ]; then printf '\n%s\n' "$arq"; arquivo_atual="$arq"; fi
  if printf '%s' "$corpo" | grep -q ';'; then
    teto="${corpo%%;*}"; gatilho="${corpo#*;}"
    printf '  L%-5s %s  →  revisitar quando: %s\n' "$num" "$(printf '%s' "$teto" | sed 's/[[:space:]]*$//')" "$(printf '%s' "$gatilho" | sed 's/^[[:space:]]*//')"
  else
    printf '  L%-5s %s  [sem-gatilho]\n' "$num" "$corpo"; sem=$((sem+1))
  fi
  if [ "$BLAME" = 1 ] && git -C "$(dirname "$arq")" rev-parse >/dev/null 2>&1; then
    git -C "$(dirname "$arq")" blame -L"$num,$num" --date=short -- "$(basename "$arq")" 2>/dev/null \
      | sed -E 's/^[^(]*\((.*) +[0-9]+\) .*$/         \1/'
  fi
  total=$((total+1))
done <<< "$LINHAS"

echo
echo "$total atalho(s), $sem sem gatilho."
[ "$sem" -gt 0 ] && echo "Sem gatilho = sem condição pra voltar. Acrescente '; <quando revisitar>' ou remova o atalho."
exit 0
