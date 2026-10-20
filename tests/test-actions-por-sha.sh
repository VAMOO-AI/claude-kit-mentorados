#!/usr/bin/env bash
# Toda action dos workflows versionados é pinada por SHA, com a versão em comentário.
#
# Tag móvel (`@v7`) pode ser reescrita por quem controla o repo da action, e o código novo
# roda no CI com o token do repo. No kit do time pesa mais: o `ci-base.yml` é o reusable que
# os repos de app da org consomem. Pinada por SHA, quem atualiza é o Dependabot
# (.github/dependabot.yml), que lê e reescreve o comentário `# vX.Y.Z` junto com o SHA.
#
# O que reprova, em `.github/workflows/*.yml` versionado:
#   - `uses: dono/repo@<ref>` cujo ref não é SHA de 40 hex (tag, branch);
#   - `uses:` sem `@`;
#   - SHA sem o comentário `# v…` na mesma linha.
# Fica de fora: action local (`./…`) e imagem `docker://…`.
#
# Uso: bash tests/test-actions-por-sha.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
git -C "$RAIZ" rev-parse --show-toplevel >/dev/null 2>&1 || { echo "não é um repo git: $RAIZ"; exit 2; }

confere_repo() { # <raiz>
  local f n linha valor resto falhas=0 wf=0 acoes=0
  local re_uses='^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*([^[:space:]#]+)(.*)$'
  while IFS= read -r f; do
    [ -f "$1/$f" ] || continue
    wf=$((wf+1)); n=0
    while IFS= read -r linha || [ -n "$linha" ]; do
      n=$((n+1))
      [[ $linha =~ $re_uses ]] || continue
      valor=${BASH_REMATCH[2]}; resto=${BASH_REMATCH[3]}
      valor=${valor//\"/}; valor=${valor//\'/}
      case "$valor" in ./*|docker://*) continue ;; esac
      acoes=$((acoes+1))
      if [[ $valor != *@* ]]; then
        echo "  FALHA $f:$n: uses sem @ref: $valor"; falhas=$((falhas+1))
      elif ! [[ ${valor##*@} =~ ^[0-9a-f]{40}$ ]]; then
        echo "  FALHA $f:$n: ref não é SHA (tag ou branch move): $valor"; falhas=$((falhas+1))
      elif ! [[ $resto =~ \#[[:space:]]*v[0-9] ]]; then
        echo "  FALHA $f:$n: SHA sem o comentário # vX.Y.Z que o Dependabot atualiza: $valor"; falhas=$((falhas+1))
      fi
    done < "$1/$f"
  done < <(git -C "$1" ls-files -- '.github/workflows/*.yml' '.github/workflows/*.yaml')
  echo
  if [ "$falhas" -gt 0 ]; then echo "$falhas falha(s) em $wf workflow(s)"; return 1; fi
  echo "tudo verde ($wf workflow(s), $acoes action(s) pinada(s) por SHA)"
}

# Antes do repo de verdade, um repo de mentira com um erro de cada tipo: gate que não
# reprova o erro plantado aprovaria qualquer coisa.
FIX=$(mktemp -d); trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
mkdir -p "$FIX/.github/workflows"
cat > "$FIX/.github/workflows/x.yml" <<'YML'
jobs:
  a:
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: "actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1" # v7.1.0
      - uses: ./.github/actions/local
      - uses: docker://alpine:3.20
      - name: uses: no meio do nome não é action
        run: echo "uses: actions/checkout@v4 dentro de run não conta"
      - uses: actions/QUEBRADO-tag@v4
      - uses: actions/QUEBRADO-sem-comentario@3d3c42e5aac5ba805825da76410c181273ba90b1
      - uses: actions/QUEBRADO-sem-ref
  b:
    uses: VAMOO-AI/QUEBRADO-reusable/.github/workflows/ci-base.yml@main
YML
git -C "$FIX" add -A
saida=$(confere_repo "$FIX"); rc=$?
falhas_fix=0
espera() { # <padrão> <descrição>
  if printf '%s' "$saida" | grep -qF -- "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não achei %s)\n' "$2" "$1"; falhas_fix=$((falhas_fix+1)); fi
}
echo "== o gate reprova o erro plantado =="
[ "$rc" = 1 ] && printf '  ok    sai 1\n' || { printf '  FALHA rc=%s\n' "$rc"; falhas_fix=$((falhas_fix+1)); }
espera 'QUEBRADO-tag@v4' "tag móvel"
espera 'QUEBRADO-sem-comentario' "SHA sem # vX.Y.Z"
espera 'QUEBRADO-sem-ref' "uses sem @"
espera 'QUEBRADO-reusable' "reusable workflow por branch"
n=$(printf '%s' "$saida" | grep -c 'FALHA')
[ "$n" = 4 ] && printf '  ok    exatamente 4 achados (SHA com versão, local, docker e run não acusam)\n' \
  || { printf '  FALHA %s achados, esperava 4:\n%s\n' "$n" "$saida"; falhas_fix=$((falhas_fix+1)); }
[ "$falhas_fix" -eq 0 ] || { echo; echo "$falhas_fix falha(s) no autoteste"; exit 1; }

echo
echo "== o repo =="
confere_repo "$RAIZ"
