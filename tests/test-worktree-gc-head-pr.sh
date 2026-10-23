#!/usr/bin/env bash
# Prova de regressão do head do PR ausente no clone, no worktree-gc.sh e no
# warn-branch-worktree.sh.
#
# Os dois já aceitavam o tip contido no head do PR (`merge-base --is-ancestor tip head`), mas
# só quando o objeto do head estava no clone. Os últimos commits do PR feitos noutro clone
# (merge da main, correção de review) deixam o head só no GitHub, em refs/pull/<n>/head, que o
# `git fetch --prune origin` não traz: o --verificar dizia "NÃO mergeada" e o aviso de
# worktree mergeado nunca acendia. O mesmo defeito do git-sync na 0.71.1, em 23/10/2026.
#
# Casos, pelo gh e pela API REST:
#   igual    tip == head                              → pode remover
#   atras    tip contido no head, head só no origin    → pode remover (head buscado)
#   avancou  commit local depois do head               → keep, NÃO mergeada
#   ausente  head nunca chegou ao origin               → keep, "indisponível", nunca seco
# E o hook: atras avisa "já foi mergeada"; avancou e ausente ficam calados.
#
# Uso: bash tests/test-worktree-gc-head-pr.sh [worktree-gc.sh] [warn-branch-worktree.sh]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
GC="${1:-$RAIZ/plugin/scripts/worktree-gc.sh}"
HOOK="${2:-$RAIZ/plugin/scripts/warn-branch-worktree.sh}"
[ -f "$GC" ] && [ -f "$HOOK" ] || { echo "script não encontrado: $GC / $HOOK"; exit 2; }
unset GH_TOKEN GITHUB_TOKEN
command -v node >/dev/null 2>&1 || { echo "node é preciso para o payload do hook"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wtgc-headpr.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E -- "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E -- "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}
igual_a() { # <esperado> <obtido> <descrição>
  if [ "$1" = "$2" ]; then printf '  ok    %s\n' "$3"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$3" "$1" "$2"; falhas=$((falhas+1)); fi
}

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"; OUTRO="$TMP/outro"; WTS="$CLONE/.claude/worktrees"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
cd "$CLONE" || exit 2
git config user.email eu@x; git config user.name eu; git config commit.gpgsign false
printf '.claude/\n' > .gitignore
echo base > base.txt; git add base.txt .gitignore; git commit -qm base
git branch -M main; git remote add origin "$ORIGIN"; git push -qu origin main

commit() { echo "$1" > "$1.txt"; git add "$1.txt"; git commit -qm "$1"; }
nova() { git checkout -q main; git checkout -qb "$1"; commit "$1-1"; git push -qu origin "$1"; }
squash() { git checkout -q main; git merge -q --squash "$1" >/dev/null && git commit -qm "$1 (squash)"; }

nova igual;   SHA_IGUAL="$(git rev-parse HEAD)";   squash igual
nova atras;                                        squash atras
nova avancou; SHA_AVANCOU="$(git rev-parse HEAD)"; squash avancou
git checkout -q avancou; commit avancou-depois
nova ausente;                                      squash ausente
git checkout -q main; git push -q origin main

# O outro clone fecha os PRs: o commit final só existe no origin, em refs/pull/<n>/head.
git clone -q "$ORIGIN" "$OUTRO" 2>/dev/null
cd "$OUTRO" || exit 2
git config user.email eu@x; git config user.name eu; git config commit.gpgsign false
git checkout -q --detach origin/atras; commit atras-final
git push -q origin "HEAD:refs/pull/71/head"; SHA_ATRAS="$(git rev-parse HEAD)"
git checkout -q --detach origin/ausente; commit ausente-final; SHA_AUSENTE="$(git rev-parse HEAD)"

cd "$CLONE" || exit 2
git push -q origin --delete igual atras avancou ausente >/dev/null 2>&1
git fetch -q --prune origin
git remote set-head origin main >/dev/null 2>&1
mkdir -p "$WTS"
for b in igual atras avancou ausente; do git worktree add -q "$WTS/$b" "$b" 2>/dev/null; done
# O head buscado vira objeto solto sem ref; o gc o tira para o próximo bloco começar igual.
esquece_heads() { git -C "$CLONE" gc -q --prune=now 2>/dev/null; }
sem_head() { ! git -C "$CLONE" cat-file -e "$SHA_ATRAS^{commit}" 2>/dev/null; }
sem_head || { echo "fixture inválida: head do PR #71 já está no clone"; exit 2; }

mkdir -p "$TMP/bin" "$TMP/home"
# gh falso: responde a forma antiga (só o head) e a nova (número e head), sem ler o --jq
cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$1" in auth) exit 0 ;; repo) exit 0 ;; api) echo '[]'; exit 0 ;; esac
br=""; forma=""
while [ \$# -gt 0 ]; do
  case "\$1" in --head) br="\$2"; shift ;; --json) forma="\$2"; shift ;; esac
  shift
done
n=""; oid=""
case "\$br" in
  igual)   n=70; oid=$SHA_IGUAL ;;
  atras)   n=71; oid=$SHA_ATRAS ;;
  avancou) n=72; oid=$SHA_AVANCOU ;;
  ausente) n=74; oid=$SHA_AUSENTE ;;
esac
case "\$forma" in
  headRefOid)        [ -n "\$oid" ] && echo "\$oid" ;;
  number,headRefOid) [ -n "\$oid" ] && echo "\$n \$oid" ;;
esac
exit 0
EOF
# curl falso: a API de pulls pelo head=dono:<branch>, exigindo o token pelo stdin
cat > "$TMP/bin/curl" <<EOF
#!/usr/bin/env bash
hdr="\$(cat)"
case "\$hdr" in *"Bearer segredo-123"*) ;; *) echo '{"message":"Bad credentials"}'; exit 22 ;; esac
head=""
for a in "\$@"; do case "\$a" in head=*) head="\${a#head=}" ;; esac; done
pr() { echo "[{\"number\":\$1,\"merged_at\":\"2026-10-01T00:00:00Z\",\"base\":{\"ref\":\"main\"},\"head\":{\"sha\":\"\$2\"}}]"; }
case "\$head" in
  dono:igual)   pr 70 $SHA_IGUAL ;;
  dono:atras)   pr 71 $SHA_ATRAS ;;
  dono:avancou) pr 72 $SHA_AVANCOU ;;
  dono:ausente) pr 74 $SHA_AUSENTE ;;
  *) echo '[]' ;;
esac
EOF
chmod +x "$TMP/bin/gh" "$TMP/bin/curl"
printf 'TESTE_GH_TOKEN=segredo-123\n' > "$TMP/tokens"

gc() { (cd "$CLONE" && GIT_SYNC_TOKENS_FILE="$TMP/tokens" PATH="$TMP/bin:$PATH" bash "$GC" "$@" 2>&1); }
verifica() { # <worktree> → "<exit>|<saída>"
  local out rc
  out="$(gc --verificar "$WTS/$1")"; rc=$?
  printf '%s|%s' "$rc" "$out"
}
payload() { D="$1" node -e 'process.stdout.write(JSON.stringify({session_id:"s1",hook_event_name:"SessionStart",source:"startup",cwd:process.env.D}))'; }
hook() { # <worktree>
  payload "$WTS/$1" > "$TMP/payload.json"
  (cd "$WTS/$1" && HOME="$TMP/home" PATH="$TMP/bin:$PATH" bash "$HOOK" < "$TMP/payload.json" 2>&1)
}

casos_verificar() { # <rótulo>
  local r="$1" o
  o="$(verifica igual)";   igual_a 0 "${o%%|*}" "$r igual: --verificar sai 0"
  o="$(verifica atras)";   igual_a 0 "${o%%|*}" "$r atrás do head: --verificar sai 0"
  check  "pode remover" "$r atrás do head: pode remover" "${o#*|}"
  o="$(verifica avancou)"; igual_a 1 "${o%%|*}" "$r avançou: --verificar sai 1"
  check  "NÃO mergeada" "$r avançou: NÃO mergeada" "${o#*|}"
  o="$(verifica ausente)"; igual_a 1 "${o%%|*}" "$r head ausente: --verificar sai 1"
  check  "head do PR #74 indisponível" "$r head ausente: motivo indisponível, não um NÃO mergeada seco" "${o#*|}"
}

echo "== gh: --verificar =="
casos_verificar gh
if [ -z "$(git -C "$CLONE" for-each-ref refs/pull)" ]; then printf '  ok    %s\n' "a busca do head não deixa ref"
else printf '  FALHA %s\n' "ficou ref em refs/pull"; falhas=$((falhas+1)); fi
esquece_heads

echo "== gh: dry-run =="
sem_head || echo "  (aviso: o gc não tirou o head buscado)"
OUT="$(gc)"
check  "removeria: .*/atras "                      "gh dry-run: atrás do head é candidato" "$OUT"
check  "removeria: .*/igual "                      "gh dry-run: igual é candidato"         "$OUT"
refute "removeria: .*/(avancou|ausente) "          "gh dry-run: avançou e ausente ficam"   "$OUT"
check  "ausente.*head do PR #74 indisponível"      "gh dry-run: ausente com o motivo"      "$OUT"
esquece_heads

echo "== hook: aviso de worktree mergeado =="
sem_head || echo "  (aviso: o gc não tirou o head buscado)"
check  "'atras' já foi mergeada"   "hook: atrás do head avisa que já mergeou" "$(hook atras)"
refute "já foi mergeada"           "hook: avançou fica calado"                "$(hook avancou)"
refute "já foi mergeada"           "hook: head ausente fica calado"           "$(hook ausente)"
esquece_heads

echo "== API REST: --verificar =="
git -C "$CLONE" config git-sync.noGh true
git -C "$CLONE" config git-sync.tokenVar TESTE_GH_TOKEN
git -C "$CLONE" config git-sync.repo dono/repo
sem_head || echo "  (aviso: o gc não tirou o head buscado)"
casos_verificar rest
refute "segredo-123" "rest: o token não aparece" "$(gc --verificar "$WTS/atras")"
esquece_heads

echo "== API REST: apply =="
OUT="$(gc --apply)"
check "✅ removido: .*/atras " "rest apply: atrás do head sai" "$OUT"
[ -d "$WTS/atras" ] && { printf '  FALHA %s\n' "rest apply: worktree atras ficou"; falhas=$((falhas+1)); } \
  || printf '  ok    %s\n' "rest apply: worktree atras removido"
for b in avancou ausente; do
  if [ -d "$WTS/$b" ]; then printf '  ok    %s\n' "rest apply: $b continua"
  else printf '  FALHA %s\n' "rest apply: $b removido"; falhas=$((falhas+1)); fi
done

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
