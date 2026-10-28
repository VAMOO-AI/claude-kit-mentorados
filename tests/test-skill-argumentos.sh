#!/usr/bin/env bash
# `$0`, `$1`… no corpo de skill e de command são placeholders de argumento: quando a skill é
# chamada com argumentos, o Claude Code troca `$0` pelo primeiro, `$1` pelo segundo, e assim por
# diante (os que não têm argumento correspondente ficam literais). Um `awk '{print $1}'` vira
# `awk '{print <palavra>}'` só quando alguém passa dois argumentos: quebra longe de quem
# escreveu. O superpowers 7.0.0 pegou isso no requesting-code-review (#2311). Aqui estavam
# `/proc/$1/stat` e `awk '{print $2}'` na vps-hardening-clientes, que é slash-only e recebe o
# nome do cliente, e `**$0**` na tabela de custo da ambientes-clientes.
#
# Reference não passa pela substituição: comando com `$N` mora em `references/` ou em
# `scripts/`. No SKILL.md, `cut -d' ' -f1` no lugar do awk; preço em dólar é `US$ 20`, com
# espaço. Nenhuma skill do kit usa argumento posicional de propósito; quando uma usar, ela
# entra numa lista de exceção aqui, com o porquê.
#
# Uso: bash tests/test-skill-argumentos.sh [arquivo-ou-pasta ...]
#      (padrão: plugin/skills/*/SKILL.md e plugin/commands/*.md)
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
alvos=()
if [ $# -eq 0 ]; then
  for f in "$RAIZ"/plugin/skills/*/SKILL.md "$RAIZ"/plugin/commands/*.md; do [ -f "$f" ] && alvos+=("$f"); done
else
  for a in "$@"; do
    if [ -d "$a" ]; then
      for f in "$a"/*/SKILL.md "$a"/*.md; do [ -f "$f" ] && alvos+=("$f"); done
    elif [ -f "$a" ]; then alvos+=("$a")
    else echo "não encontrado: $a"; exit 2; fi
  done
fi
[ "${#alvos[@]}" -gt 0 ] || { echo "nenhum SKILL.md ou command para olhar"; exit 2; }

falhas=0
for f in "${alvos[@]}"; do
  hits="$(grep -nE '\$[0-9]' "$f" || true)"
  if [ -n "$hits" ]; then
    printf 'FALHA %s\n' "${f#"$RAIZ"/}"
    printf '%s\n' "$hits" | sed 's/^/      /'
    falhas=$((falhas+1))
  fi
done

echo
echo "${#alvos[@]} arquivo(s) olhado(s)"
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; exit 0; fi
echo "FALHOU ($falhas): mova o comando para references/ ou scripts/, ou troque o \$N (ver cabeçalho)"
exit 1
