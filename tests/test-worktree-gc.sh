#!/usr/bin/env bash
# Prova de regressão do plugin/scripts/worktree-gc.sh.
#
# O script anterior aceitava "mergeada" por `gh pr list --state merged | length > 0`:
# bastava a branch ter tido UM PR mergeado um dia. Commit feito depois do merge, ainda
# sem push, contava como lixo — e `--apply` apagava worktree com trabalho novo. O
# conserto (vindo do kit do time) exige que o tip local esteja contido no head do PR
# mergeado; sem isso, fail-closed: mantém.
#
# Também cobre as outras duas travas que vieram juntas: env ignorado que difere do
# clone principal (invisível no `status`, some junto com o worktree) e worktree
# detached, que antes era pulado sempre e agora é lixo quando está limpo e o HEAD é
# trabalho já contido em origin/main. Até 28/09/2026 a trava do env só comparava o
# `.env.local` da raiz: `.npmrc` e `.env.local` de subpasta sumiam no --apply.
#
# Branch sem commit próprio é ancestral de origin/main por definição, e o `--apply`
# removia o worktree limpo de uma sessão recém-aberta (24/09/2026 — o mesmo defeito do
# warn-worktree-stale). Agora ela fica: o tip não passou do ponto de criação (1ª entrada
# do reflog) ou é commit da linha first-parent da main. Vale também para o detached no
# tip ou num commit antigo da main.
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
no_disco() { # <worktree> <por que não podia sumir>
  if [ -d "$WTS/$1" ]; then printf '  ok    %s continua no disco\n' "$1"
  else printf '  FALHA %s foi apagado: %s\n' "$1" "$2"; falhas=$((falhas+1)); fi
}

# --- fixture: origin bare + clone principal com main -------------------------------
ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"; WTS="$CLONE/.claude/worktrees"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
G() { g -C "$CLONE" "$@"; }
# O .gitignore entra no PRIMEIRO commit, antes de qualquer worktree: a trava do .env.local
# só é alcançada se o arquivo estiver ignorado — untracked, ele já cai na trava de "sujo".
# Sem isto o teste passava só em máquina cujo gitignore global ignora .env.local (03/09/2026).
echo base > "$CLONE/base.txt"; printf '.env.local\n.npmrc\nbunfig.toml\nvendor/\n' > "$CLONE/.gitignore"
G add base.txt .gitignore; G commit -qm base
G branch -M main; G remote add origin "$ORIGIN"; G push -qu origin main
BASE="$(G rev-parse HEAD)"
echo "ENV=clone" > "$CLONE/.env.local"; echo "registry=clone" > "$CLONE/.npmrc"
echo "exact = true" > "$CLONE/bunfig.toml"
mkdir -p "$WTS"

novo_wt()    { G worktree add -q -b "$1" "$WTS/wt-$1" "${2:-origin/main}"; }
commit_em()  { g -C "$WTS/wt-$1" commit -q --allow-empty -m "$2"; }
# Push a cada merge: o gc abre com `fetch --prune`, e o origin/main do clone vira o do bare.
merge_main() { G merge -q --no-ff -m "merge $1" "$1"; G push -q origin main; }

# Sem commit próprio — criadas antes dos merges, para a main andar depois delas.
# nova: recém-criada de origin/main, limpa — a sessão ainda não escreveu nada
novo_wt nova
# sem-reflog: idem, com o reflog expirado — sobra a linha first-parent da main
novo_wt sem-reflog
G reflog expire --expire=now refs/heads/sem-reflog
# sincronizada: nasce aqui, puxa a base (ff) lá embaixo, e a main anda de novo depois
novo_wt sincronizada
# empilhada: criada de feat (que tem commit próprio), sem commit dela; feat é mergeada
novo_wt feat; commit_em feat f
G worktree add -q -b empilhada "$WTS/wt-empilhada" feat
merge_main feat

# anc: mergeada de verdade (ancestral de origin/main)
novo_wt anc; commit_em anc anc; merge_main anc
OID_ANC="$(G rev-parse anc)"

# pr-ok: squash-mergeada — o PR aponta para o tip local
novo_wt pr-ok; commit_em pr-ok pr
OID_PR="$(G rev-parse pr-ok)"

# pr-after: PR mergeado no commit X, mas há um commit Y DEPOIS, sem push
novo_wt pr-after; commit_em pr-after X
OID_AFTER="$(G rev-parse pr-after)"
commit_em pr-after Y

# env: mergeada de verdade e limpa, mas com .env.local diferente do clone — só a trava
# do .env.local a segura (o `worktree remove` apaga arquivo ignorado sem reclamar)
novo_wt env; commit_em env e; merge_main env
echo "ENV=outro" > "$WTS/wt-env/.env.local"
# env-npmrc e env-aninhado: a mesma trava para o .npmrc e para um .env.local de subpasta,
# que nem existe no clone principal. E a anc leva uma cópia igual do .env.local do clone:
# env igual não segura ninguém.
novo_wt env-npmrc; commit_em env-npmrc n; merge_main env-npmrc
echo "registry=outro" > "$WTS/wt-env-npmrc/.npmrc"
novo_wt env-aninhado; commit_em env-aninhado a; merge_main env-aninhado
mkdir -p "$WTS/wt-env-aninhado/apps/x"; echo "ENV=sub" > "$WTS/wt-env-aninhado/apps/x/.env.local"
cp "$CLONE/.env.local" "$WTS/wt-anc/.env.local"
# env-bunfig, env-npmrc-sub e env-repo: o bunfig.toml de projeto (sem ponto) diferente, um
# .npmrc de subpasta e um repo aninhado ignorado — o remove apagaria até o .git dele
novo_wt env-bunfig; commit_em env-bunfig b; merge_main env-bunfig
echo "exact = false" > "$WTS/wt-env-bunfig/bunfig.toml"
novo_wt env-npmrc-sub; commit_em env-npmrc-sub s; merge_main env-npmrc-sub
mkdir -p "$WTS/wt-env-npmrc-sub/apps/y"; echo "registry=sub" > "$WTS/wt-env-npmrc-sub/apps/y/.npmrc"
novo_wt env-repo; commit_em env-repo r; merge_main env-repo
git init -q "$WTS/wt-env-repo/vendor/lib"

# dirty: mergeada de verdade, mas suja
novo_wt dirty; commit_em dirty d; merge_main dirty
echo x > "$WTS/wt-dirty/sujo.txt"

g -C "$WTS/wt-sincronizada" merge -q --ff-only origin/main
G commit -q --allow-empty -m "main andou"; G push -q origin main

# det: detached no tip da main, limpo — checkout da base, não trabalho
G worktree add -q --detach "$WTS/wt-det" origin/main
# det-velho: detached num commit antigo da linha first-parent da main
G worktree add -q --detach "$WTS/wt-det-velho" "$BASE"
# det-mergeado: detached num commit que entrou na main por merge commit — esse é lixo
G worktree add -q --detach "$WTS/wt-det-mergeado" "$OID_ANC"
# det-env: o mesmo commit mergeado, mas com .env.local diferente do clone — fica, e diz qual
G worktree add -q --detach "$WTS/wt-det-env" "$OID_ANC"
echo "ENV=det" > "$WTS/wt-det-env/.env.local"

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
check 'removeria: .*wt-pr-ok '          "squash-mergeada com tip == head do PR é candidata"      "$OUT"
check 'wt-pr-after .*NÃO mergeada'      "commit DEPOIS do PR mergeado mantém o worktree"         "$OUT"
refute 'removeria: .*wt-pr-after'       "wt-pr-after nunca aparece como candidato"               "$OUT"
check 'wt-env .*\.env\.local difere'    ".env.local divergente segura o worktree mergeado"       "$OUT"
check 'wt-env-npmrc .*\.npmrc difere'   ".npmrc divergente segura o worktree mergeado"           "$OUT"
check 'wt-env-aninhado .*apps/x/\.env\.local difere' ".env.local de subpasta segura o worktree mergeado" "$OUT"
refute 'removeria: .*wt-env-(npmrc|aninhado) ' "nenhum dos dois aparece como candidato"         "$OUT"
check 'wt-env-bunfig .*bunfig\.toml difere'     "bunfig.toml de projeto divergente segura o worktree"     "$OUT"
check 'wt-env-npmrc-sub .*apps/y/\.npmrc difere' ".npmrc de subpasta segura o worktree"                   "$OUT"
check 'wt-env-repo .*repo aninhado ignorado: vendor/lib/' "repo aninhado ignorado segura o worktree, com o caminho" "$OUT"
refute 'removeria: .*wt-env-(bunfig|npmrc-sub|repo) ' "nenhum dos três aparece como candidato"          "$OUT"
check 'wt-dirty .*SUJO'                 "worktree mergeado e sujo é mantido"                     "$OUT"
check 'removeria: .*wt-det-mergeado .*detached' "detached limpo num commit mergeado é lixo"      "$OUT"
check 'wt-det-env .*\.env\.local difere' "detached mergeado com .env.local divergente: fica e diz o arquivo" "$OUT"

echo "== sem commit próprio: sessão recém-aberta, não branch mergeada =="
check  'wt-nova .*sem commit próprio'               "nova de origin/main, limpa: mantida"                        "$OUT"
check  'wt-sem-reflog .*sem commit próprio'         "nova com o reflog expirado (linha first-parent): mantida"   "$OUT"
check  'wt-sincronizada .*sem commit próprio'       "nova que só puxou a base (ff), com a main andando: mantida" "$OUT"
check  'wt-empilhada .*sem commit próprio'          "empilhada numa branch que depois foi mergeada: mantida"     "$OUT"
check  'wt-det .*detached sem commit próprio'       "detached no tip da main: mantido"                           "$OUT"
check  'wt-det-velho .*detached sem commit próprio' "detached num commit antigo da main: mantido"                 "$OUT"
refute 'removeria: .*wt-(nova|sem-reflog|sincronizada|empilhada|det|det-velho) ' "nenhum deles aparece como candidato" "$OUT"

echo "== --apply: o que sobrevive =="
OUT="$(run --apply)"
check 'removido: .*wt-anc'              "apply remove a ancestral"                               "$OUT"
check 'removido: .*wt-det-mergeado'     "apply remove o detached num commit mergeado"            "$OUT"
no_disco wt-pr-after     "commit sem push"
no_disco wt-env          ".env.local divergente"
no_disco wt-env-npmrc    ".npmrc divergente"
no_disco wt-env-aninhado "apps/x/.env.local só no worktree"
no_disco wt-det-env      ".env.local divergente num detached"
no_disco wt-env-bunfig   "bunfig.toml divergente"
no_disco wt-env-npmrc-sub "apps/y/.npmrc só no worktree"
no_disco wt-env-repo     "repo aninhado ignorado"
no_disco wt-dirty        "estava sujo"
no_disco wt-nova         "branch sem commit próprio"
no_disco wt-sem-reflog   "branch sem commit próprio"
no_disco wt-sincronizada "branch sem commit próprio"
no_disco wt-empilhada    "branch sem commit próprio"
no_disco wt-det          "detached sem commit próprio"
no_disco wt-det-velho    "detached sem commit próprio"
G branch --list pr-after | grep -q pr-after && printf '  ok    branch pr-after preservada\n' || { printf '  FALHA branch pr-after deletada\n'; falhas=$((falhas+1)); }
G branch --list nova | grep -q nova && printf '  ok    branch nova preservada\n' || { printf '  FALHA branch nova deletada\n'; falhas=$((falhas+1)); }

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
