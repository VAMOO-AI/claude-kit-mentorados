#!/usr/bin/env bash
# baseline · raizes — onde moram o app e as migrations deste repo. Descobre, não supõe.
#
# Por que existe: secscan, baseline e auditoria-seguranca fixavam `supabase/migrations` e "a
# raiz do repo". Em três pentests de 11/2026 as migrations estavam em src/db/migrations, em
# src/sql e em <app>/supabase/migrations, e o app numa subpasta. Todo check de SQL saiu
# nao_medido (ou "medido: 0"), os greps deram 0 hits e a classe mais grave passou calada.
#
# Só lê nomes de arquivo: o que o git rastreia mais o untracked fora do .gitignore; fora de
# um repo git, `find`. Sem rede, sem escrita.
#
#   raizes.sh [--root DIR]
#
# Saída (TSV, caminhos relativos ao --root, "." é a própria raiz):
#   APP<TAB>dir                 pasta com package.json
#   MIGRATIONS<TAB>dir<TAB>n    pasta chamada migrations/, sql/ ou schemas/ com n arquivos .sql
#                               direto nela (o que está sob tests/, fixtures/, examples/ ou
#                               docs/ não conta)
# Exit 0 mesmo sem achar nada: saída vazia quer dizer "não achei", e quem chama registra
# nao_medido com o motivo.
set -uo pipefail

ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT" 2>/dev/null || { echo "root inválido: $ROOT" >&2; exit 2; }

lista=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  lista="$(git -c core.quotePath=false ls-files -co --exclude-standard 2>/dev/null \
            | grep -E '(^|/)package\.json$|\.sql$')"
fi
# Fora do git, ou numa pasta que o repo de cima ignora inteira (a listagem do git vem vazia).
if [ -z "$lista" ]; then
  lista="$(find . \( -name node_modules -o -name .git -o -name .next -o -name dist -o -name build \
                    -o -name .claude -o -name .vercel -o -name vendor \) -prune \
              -o -type f \( -name package.json -o -name '*.sql' \) -print 2>/dev/null | sed 's|^\./||')"
fi

printf '%s\n' "$lista" \
  | grep -vE '(^|/)(node_modules|\.git|\.next|dist|build|\.claude|\.vercel|vendor|tests?|__tests__|fixtures|examples?|docs)/' \
  | LC_ALL=C awk '
      function pasta(p,   i) { i = match(p, /\/[^\/]*$/); return i ? substr(p, 1, i - 1) : "." }
      /(^|\/)package\.json$/ { app[pasta($0)] = 1; next }
      /\.sql$/ { d = pasta($0); if (d ~ /(^|\/)(migrations|sql|schemas)$/) mig[d]++ }
      END {
        for (d in app) print "APP\t" d
        for (d in mig) print "MIGRATIONS\t" d "\t" mig[d]
      }' \
  | LC_ALL=C sort
exit 0
