#!/usr/bin/env bash
# Os repos de onde o kit tira ideia (superpowers, rtk, gstack…) andam toda semana, e a
# leitura deles era por lembrança: a de 01/09/2026 só se repetiu em 28/10, e nesse meio o
# superpowers já tinha achado o corte de skill na compactação que pegava a ship e a secscan.
# Este script compara cada repo do scripts/upstreams.json com a data da última leitura e
# lista o que saiu depois dela: release nova (filtrada pelo regex `tag`) e, quando
# `commits_minimo` > 0, o número de commits na branch padrão. Não lê nem julga conteúdo:
# isso é da pessoa (ou da sessão) que abre a issue.
#
# Repo que a API não respondeu sai como "não medido", nunca como "nada novo", e o script
# termina 3: no workflow isso fica vermelho em vez de virar silêncio.
#
# Uso: bash scripts/upstreams-check.sh [--issue] [--manifesto <arquivo>]
#   --issue  abre (ou atualiza o corpo da aberta) a issue "upstreams: novidade para ler" no
#            repo do kit (UPSTREAMS_REPO, ou GITHUB_REPOSITORY no Actions). Sem novidade,
#            não mexe em issue nenhuma.
# Exit: 0 rodou (com ou sem novidade) · 2 uso/dependência · 3 algum repo não foi medido.
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
MANIFESTO="$RAIZ/scripts/upstreams.json"
ISSUE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --issue) ISSUE=1 ;;
    --manifesto) shift; MANIFESTO="${1:-}" ;;
    *) echo "uso: $0 [--issue] [--manifesto <arquivo>]" >&2; exit 2 ;;
  esac
  shift
done
command -v jq >/dev/null 2>&1 || { echo "jq ausente" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "gh ausente" >&2; exit 2; }
[ -f "$MANIFESTO" ] || { echo "manifesto não encontrado: $MANIFESTO" >&2; exit 2; }
jq -e '.upstreams | type == "array" and length > 0' "$MANIFESTO" >/dev/null 2>&1 \
  || { echo "manifesto sem a lista .upstreams: $MANIFESTO" >&2; exit 2; }

TITULO="upstreams: novidade para ler"
TITULO_ISSUE="${UPSTREAMS_TITULO:-$TITULO}"
relatorio="$(mktemp)"; trap 'rm -f "$relatorio"' EXIT
novidades=0
erros=0

n=$(jq '.upstreams | length' "$MANIFESTO")
for i in $(seq 0 $((n - 1))); do
  e=$(jq -c ".upstreams[$i]" "$MANIFESTO")
  repo=$(jq -r '.repo' <<<"$e")
  lido=$(jq -r '.lido_em' <<<"$e")
  versao=$(jq -r '.lido_versao // "-"' <<<"$e")
  tag=$(jq -r '.tag // ""' <<<"$e")
  minimo=$(jq -r '.commits_minimo // 0' <<<"$e")
  trouxe=$(jq -r '.que_trouxemos // ""' <<<"$e")

  # O lido_em é ISO 8601 em UTC: comparar string com o published_at da API é comparar data.
  rels=$(gh api "repos/$repo/releases?per_page=30" --jq "[.[] | select(.draft | not) | select(.prerelease | not)
    | select(.published_at > \"$lido\") | select(.tag_name | test(\"$tag\"))
    | \"\(.tag_name) (\(.published_at[:10])) \(.html_url)\"] | .[]" 2>/dev/null)
  rc_rel=$?
  commits=0; rc_com=0
  if [ "$minimo" -gt 0 ]; then
    commits=$(gh api "repos/$repo/commits?since=$lido&per_page=100" --jq 'length' 2>/dev/null)
    rc_com=$?
  fi

  if [ "$rc_rel" -ne 0 ] || [ "$rc_com" -ne 0 ] || ! [[ "$commits" =~ ^[0-9]+$ ]]; then
    printf '%-28s não medido (a API não respondeu)\n' "$repo"
    printf '## %s: não medido\n\nA API do GitHub não respondeu para este repo. Rode `bash scripts/upstreams-check.sh` de novo.\n\n' "$repo" >>"$relatorio"
    erros=$((erros + 1))
    continue
  fi

  nrel=0; [ -n "$rels" ] && nrel=$(printf '%s\n' "$rels" | wc -l | tr -d ' ')
  tem_commits=0; [ "$minimo" -gt 0 ] && [ "$commits" -ge "$minimo" ] && tem_commits=1
  if [ "$nrel" -eq 0 ] && [ "$tem_commits" -eq 0 ]; then
    printf '%-28s nada novo desde %s\n' "$repo" "${lido%%T*}"
    continue
  fi

  novidades=$((novidades + 1))
  # As duas consultas são de uma página só (30 releases, 100 commits): no teto, o número é piso.
  qtd="$commits"; [ "$commits" -ge 100 ] && qtd="100+"
  qrel="$nrel"; [ "$nrel" -ge 30 ] && qrel="30+"
  printf '%-28s %s release(s), %s commit(s) desde %s\n' "$repo" "$qrel" "$qtd" "${lido%%T*}"
  {
    printf '## %s\n\nÚltima leitura: %s (%s). O que trouxemos: %s\n\n' "$repo" "${lido%%T*}" "$versao" "$trouxe"
    if [ "$nrel" -gt 0 ]; then
      printf 'Releases novas:\n\n'
      printf '%s\n' "$rels" | sed 's/^/- /'
      printf '\n'
    fi
    [ "$tem_commits" -eq 1 ] && printf 'Commits na branch padrão desde a leitura: %s (o repo anda sem tag; leia o CHANGELOG).\n\n' "$qtd"
  } >>"$relatorio"
done

echo
echo "$novidades repo(s) com novidade, $erros não medido(s)"

if [ "$ISSUE" -eq 1 ] && [ "$novidades" -gt 0 ]; then
  alvo="${UPSTREAMS_REPO:-${GITHUB_REPOSITORY:-}}"
  R=(); [ -n "$alvo" ] && R=(-R "$alvo")
  corpo="$(mktemp)"
  {
    printf 'Saiu coisa nos repos de onde o kit tira ideia. Para cada um: leia o changelog, cruze com o kit (o que já temos, o que não serve e por quê) e traga só o que sobreviver.\n\n'
    printf 'Depois de ler, atualize `lido_em`, `lido_versao` e `que_trouxemos` em `scripts/upstreams.json`, e feche esta issue.\n\n'
    cat "$relatorio"
    printf -- '---\nGerada por `scripts/upstreams-check.sh --issue` em %s.\n' "$(date -u +%Y-%m-%d)"
  } >"$corpo"
  aberta=$(gh issue list ${R[@]+"${R[@]}"} --state open --search "in:title \"$TITULO_ISSUE\"" --json number,title \
    --jq "[.[] | select(.title == \"$TITULO_ISSUE\")][0].number // empty" 2>/dev/null)
  if [ -n "$aberta" ]; then
    gh issue edit "$aberta" ${R[@]+"${R[@]}"} --body-file "$corpo" >/dev/null && echo "issue #$aberta atualizada" || { echo "falhou ao atualizar a issue #$aberta" >&2; erros=$((erros + 1)); }
  else
    gh issue create ${R[@]+"${R[@]}"} --title "$TITULO_ISSUE" --body-file "$corpo" || { echo "falhou ao abrir a issue" >&2; erros=$((erros + 1)); }
  fi
  rm -f "$corpo"
fi

[ "$erros" -gt 0 ] && exit 3
exit 0
