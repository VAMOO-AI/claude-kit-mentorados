#!/usr/bin/env bash
# Prova de regressão do plugin/scripts/warn-worktree-stale.sh (hook de SessionStart).
#
# O hook chamava de mergeada toda branch ancestral de origin/main — e a branch recém-criada
# de origin/main, sem commit nenhum, é ancestral por definição. Em 24/09/2026, no CRM
# Multipedidos, o aviso saiu num compact com o fix inteiro ainda sem commit no worktree:
# "já foi MERGEADA — este worktree é lixo. Remova com 'ExitWorktree'". Agora:
#   - branch sem commit próprio não é mergeada: o tip não passou do ponto de criação (a 1ª
#     entrada do reflog) ou é commit da linha first-parent da main (só puxou a base, ou o
#     reflog expirou);
#   - mergeada com mudança não commitada não é lixo;
#   - a prova pelo PR (squash) exige o tip contido no head do PR, como no worktree-gc.
#
# O `gh` é falso (PATH) e responde às duas formas de consulta — a antiga (`length`) e a
# nova (`headRefOid`) — para o mesmo teste rodar contra as duas versões do script.
#
# Uso: bash tests/test-warn-worktree-stale.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/warn-worktree-stale.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wtstale.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"   # o TMPDIR do macOS termina em "/"
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}
calado() { # <descrição> <saída>
  if [ -z "$2" ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s (saiu: %s)\n' "$1" "$2"; falhas=$((falhas+1)); fi
}

# --- fixture: origin bare + clone principal em main ----------------------------------
ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"; WTS="$CLONE/.claude/worktrees"
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
G() { g -C "$CLONE" "$@"; }
git init -q --bare -b main "$ORIGIN"
git init -q -b main "$CLONE"
echo base > "$CLONE/base.txt"
G add base.txt; G commit -qm base
G remote add origin "$ORIGIN"; G push -qu origin main
mkdir -p "$WTS"

novo_wt()   { G worktree add -q -b "$1" "$WTS/$1" "${2:-origin/main}"; }
commit_em() { g -C "$WTS/$1" commit -q --allow-empty -m "$2"; }
merge_main() { G merge -q --no-ff -m "merge $1" "$1"; G push -q origin main; }

# nova-suja: o caso de 24/09 — branch nova de origin/main, o fix inteiro sem commit
novo_wt nova-suja
echo mudou >> "$WTS/nova-suja/base.txt"; echo novo > "$WTS/nova-suja/novo.txt"
# nova-limpa: recém-criada, a sessão ainda não escreveu nada
novo_wt nova-limpa
# sem-reflog: recém-criada, reflog expirado — sobra a linha first-parent da main
novo_wt sem-reflog
G reflog expire --expire=now refs/heads/sem-reflog
# sincronizada: nasce aqui, puxa a base (ff) lá embaixo, depois a main anda de novo
novo_wt sincronizada

# empilhada: criada de feat (que tem commit próprio) sem commit dela; feat é mergeada depois
novo_wt feat; commit_em feat f
G worktree add -q -b empilhada "$WTS/empilhada" feat
merge_main feat

# mergeada: commit próprio, merge commit na main
novo_wt mergeada; commit_em mergeada m; merge_main mergeada
# mergeada-suja: idem, com mudança não commitada depois do merge
novo_wt mergeada-suja; commit_em mergeada-suja ms; merge_main mergeada-suja
echo depois >> "$WTS/mergeada-suja/base.txt"

# squash: commit próprio fora da main; o PR mergeado aponta para o tip
novo_wt squash; commit_em squash s
OID_SQUASH="$(g -C "$WTS/squash" rev-parse HEAD)"
# squash-depois: PR mergeado no commit X, mas há um Y depois, sem push
novo_wt squash-depois; commit_em squash-depois X
OID_X="$(g -C "$WTS/squash-depois" rev-parse HEAD)"
commit_em squash-depois Y
# viva: commit próprio, sem merge e sem PR
novo_wt viva; commit_em viva v

g -C "$WTS/sincronizada" merge -q --ff-only origin/main
G commit -q --allow-empty -m "main andou"; G push -q origin main

# --- gh falso: quem tem PR mergeado, e em qual head -----------------------------------
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
case "\$br" in squash) oid="$OID_SQUASH" ;; squash-depois) oid="$OID_X" ;; esac
case "\$forma" in
  headRefOid) printf '%s\n' "\$oid" ;;
  number)     [ -n "\$oid" ] && echo 1 || echo 0 ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

run() { CLAUDE_PROJECT_DIR="$WTS/$1" PATH="$TMP/bin:$PATH" bash "$SCRIPT" 2>&1; }

echo "== branch sem commit próprio: nada a avisar =="
calado "nova de origin/main com mudança sem commit (o caso de 24/09)"   "$(run nova-suja)"
calado "nova de origin/main, limpa"                                     "$(run nova-limpa)"
calado "nova com o reflog expirado (linha first-parent da main)"        "$(run sem-reflog)"
calado "nova que só puxou a base (ff), com a main andando depois"       "$(run sincronizada)"
calado "empilhada numa branch que depois foi mergeada"                  "$(run empilhada)"

echo "== mergeada de verdade: continua avisando =="
OUT="$(run mergeada)"
check  "já foi MERGEADA — este worktree é lixo"  "commit próprio em origin/main, limpa: lixo"   "$OUT"
OUT="$(run squash)"
check  "já foi MERGEADA — este worktree é lixo"  "squash com tip == head do PR, limpa: lixo"    "$OUT"
OUT="$(run mergeada-suja)"
check  "mergeada.*mudança não commitada"         "mergeada com mudança sem commit: avisa a mudança" "$OUT"
refute "lixo|ExitWorktree|worktree-gc"           "mergeada suja nunca é chamada de lixo"        "$OUT"

echo "== trabalho vivo: nada a avisar =="
calado "commit depois do head do PR mergeado"                           "$(run squash-depois)"
calado "commit próprio sem merge e sem PR"                              "$(run viva)"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
