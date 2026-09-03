#!/usr/bin/env bash
# Prova de regressão do plugin/scripts/worktree-gc.sh.
#
# O script anterior aceitava "mergeada" por `gh pr list --state merged | length > 0`:
# bastava a branch ter tido UM PR mergeado um dia. Commit feito depois do merge, ainda
# sem push, contava como lixo — e `--apply` apagava worktree com trabalho novo. O
# conserto (vindo do kit do time) exige que o tip local esteja contido no head do PR
# mergeado; sem isso, fail-closed: mantém.
#
# Também cobre as outras duas travas que vieram juntas: `.env.local` que difere do
# clone principal (invisível no `status`, some junto com o worktree) e worktree
# detached, que antes era pulado sempre e agora é lixo quando está limpo e o HEAD já
# está em origin/main.
#
# O `gh` é falso (PATH): responde às duas formas de consulta — a antiga (`length`) e a
# nova (`headRefOid`) — para que o mesmo teste rode contra as duas versões do script.
#
# Uso: bash tests/test-worktree-gc.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/worktree-gc.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wtgc.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}

# --- fixture: origin bare + clone principal com main -------------------------------
ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"; WTS="$CLONE/.claude/worktrees"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
G() { git -C "$CLONE" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
# O .gitignore entra no PRIMEIRO commit, antes de qualquer worktree: a trava do .env.local
# só é alcançada se o arquivo estiver ignorado — untracked, ele já cai na trava de "sujo".
# Sem isto o teste passava só em máquina cujo gitignore global ignora .env.local (03/09/2026).
echo base > "$CLONE/base.txt"; printf '.env.local\n' > "$CLONE/.gitignore"
G add base.txt .gitignore; G commit -qm base
G branch -M main; G remote add origin "$ORIGIN"; G push -qu origin main
echo "ENV=clone" > "$CLONE/.env.local"
mkdir -p "$WTS"

# anc: mergeada de verdade (ancestral de origin/main)
G worktree add -q "$WTS/wt-anc" -b anc
git -C "$WTS/wt-anc" -c user.email=t@t -c user.name=t commit -q --allow-empty -m anc
G merge -q --no-ff -m "merge anc" anc; G push -q origin main

# pr-ok: squash-mergeada — o PR aponta para o tip local
G worktree add -q "$WTS/wt-pr" -b pr-ok
git -C "$WTS/wt-pr" -c user.email=t@t -c user.name=t commit -q --allow-empty -m pr
OID_PR="$(git -C "$WTS/wt-pr" rev-parse HEAD)"

# pr-after: PR mergeado no commit X, mas há um commit Y DEPOIS, sem push
G worktree add -q "$WTS/wt-after" -b pr-after
git -C "$WTS/wt-after" -c user.email=t@t -c user.name=t commit -q --allow-empty -m X
OID_AFTER="$(git -C "$WTS/wt-after" rev-parse HEAD)"
git -C "$WTS/wt-after" -c user.email=t@t -c user.name=t commit -q --allow-empty -m Y

# env: mergeada (ancestral), limpa, mas .env.local diferente do clone
G worktree add -q "$WTS/wt-env" -b env
G merge -q --no-ff -m "merge env" env 2>/dev/null || true
echo "ENV=outro" > "$WTS/wt-env/.env.local"

# det: detached no tip da main, limpo
G worktree add -q --detach "$WTS/wt-det" origin/main

# dirty: mergeada (ancestral) mas suja
G worktree add -q "$WTS/wt-dirty" -b dirty
echo x > "$WTS/wt-dirty/sujo.txt"

# --- gh falso: quem tem PR mergeado, e em qual head ----------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<GH
#!/usr/bin/env bash
case "\$1" in auth) exit 0 ;; esac
br=""; forma=""
while [ \$# -gt 0 ]; do
  case "\$1" in --head) br="\$2"; shift ;; --json) forma="\$2"; shift ;; esac
  shift
done
oid=""
case "\$br" in pr-ok) oid="$OID_PR" ;; pr-after) oid="$OID_AFTER" ;; esac
case "\$forma" in
  headRefOid) printf '%s\n' "\$oid" ;;
  number)     [ -n "\$oid" ] && echo 1 || echo 0 ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

run() { (cd "$CLONE" && PATH="$TMP/bin:$PATH" bash "$SCRIPT" "$@" 2>&1); }

echo "== dry-run: quem é lixo e quem não é =="
OUT="$(run)"
check 'removeria: .*wt-anc '            "branch ancestral de origin/main é candidata"            "$OUT"
check 'removeria: .*wt-pr '             "squash-mergeada com tip == head do PR é candidata"      "$OUT"
check 'wt-after .*NÃO mergeada'         "commit DEPOIS do PR mergeado mantém o worktree"         "$OUT"
refute 'removeria: .*wt-after'          "wt-after nunca aparece como candidato"                  "$OUT"
check 'wt-env .*\.env\.local difere'    ".env.local divergente segura o worktree"                "$OUT"
check 'removeria: .*wt-det .*detached'  "detached limpo com HEAD em origin/main é lixo"          "$OUT"
check 'wt-dirty .*SUJO'                 "worktree sujo é mantido"                                "$OUT"

echo "== --apply: o que sobrevive =="
OUT="$(run --apply)"
check 'removido: .*wt-anc'              "apply remove a ancestral"                               "$OUT"
[ -d "$WTS/wt-after" ] && printf '  ok    wt-after continua no disco\n' || { printf '  FALHA wt-after foi apagado com commit sem push\n'; falhas=$((falhas+1)); }
[ -d "$WTS/wt-env" ]   && printf '  ok    wt-env continua no disco\n'   || { printf '  FALHA wt-env foi apagado com .env.local divergente\n'; falhas=$((falhas+1)); }
[ -d "$WTS/wt-dirty" ] && printf '  ok    wt-dirty continua no disco\n' || { printf '  FALHA wt-dirty foi apagado sujo\n'; falhas=$((falhas+1)); }
G branch --list pr-after | grep -q pr-after && printf '  ok    branch pr-after preservada\n' || { printf '  FALHA branch pr-after deletada\n'; falhas=$((falhas+1)); }

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
