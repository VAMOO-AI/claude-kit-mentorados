#!/usr/bin/env bash
# Prova de regressão do plugin/scripts/warn-branch-worktree.sh (hook de SessionStart), que
# depois da 0.64 juntou o warn-branch-behind.sh e o warn-worktree-stale.sh num aviso só.
#
# Três partes:
#
# (A) Branch atrás do upstream, com o cache de fetch. O hook fazia `git fetch` em TODA
#     sessão (~1 s cada). Agora faz no máximo 1x a cada 10 min por repositório+branch,
#     com marcador em ~/.claude/.cache/warn-branch-behind/<sha do git-common-dir>-<branch>;
#     dentro da janela compara com o origin/<branch> local e continua avisando. O `git` do
#     PATH é um wrapper que conta os `fetch`: é o único jeito de saber se o remoto foi
#     consultado sem depender de rede.
#
# (B) Worktree mergeado. O hook chamava de mergeada toda branch ancestral de origin/main, e
#     a branch recém-criada de origin/main, sem commit nenhum, é ancestral por definição
#     (24/09/2026: o aviso mandou remover um worktree com o fix inteiro sem commit). Agora:
#     branch sem commit próprio não é mergeada; mergeada com mudança não commitada não é
#     lixo; a prova por PR (squash) exige o tip contido no head do PR. O aviso não dá
#     ordem nem oferece o ExitWorktree: aponta a skill worktrees, o `worktree-gc.sh
#     --verificar <caminho>` (só lê) e o `git-sync --cleanup-dry-run` antes do apply. E o
#     clone principal fora da main só é assunto numa sessão em worktree.
#
# (C) O diretório vem do `.cwd` do payload. Numa sessão de worktree do app desktop, o
#     $PWD do hook (e o CLAUDE_PROJECT_DIR) pode ser a raiz do clone principal. Os dois
#     scripts antigos liam `${CLAUDE_PROJECT_DIR:-$PWD}` e calavam ali.
#
# O `gh` é falso (PATH). Uso: bash tests/test-warn-branch-worktree.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/warn-branch-worktree.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
REAL_GIT="$(command -v git)" || { echo "git ausente"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/warn-bw.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"   # o TMPDIR do macOS termina em "/"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_PROJECT_DIR

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}
calado() { # <descrição> <saída>
  if [ -z "$2" ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s (saiu: %s)\n' "$1" "$2"; falhas=$((falhas+1)); fi
}
sim() { # <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
# payload <cwd> → o JSON do SessionStart, montado por node (aspas no caminho não quebram)
payload() { D="$1" node -e 'process.stdout.write(JSON.stringify({session_id:"s1",hook_event_name:"SessionStart",source:"startup",cwd:process.env.D}))'; }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/git" <<EOF
#!/usr/bin/env bash
[ "\$1" = fetch ] && echo fetch >> "$TMP/fetches"
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$BIN/git"

# roda_em <cwd do payload> [PWD do processo]: o processo roda no segundo, o payload diz o primeiro
roda_em() {
  payload "$1" > "$TMP/payload.json"
  ( cd "${2:-$1}" && HOME="$FAKE_HOME" PATH="$BIN:$PATH" bash "$SCRIPT" < "$TMP/payload.json" 2>&1 )
}

FAKE_HOME="$TMP/home"; mkdir -p "$FAKE_HOME"

echo "== (A) atrás do upstream: fetch 1x a cada 10 min, e o aviso continua =="
REMOTE="$TMP/origin-a.git"; git init -q --bare -b main "$REMOTE"
SEED="$TMP/seed"; git init -q -b main "$SEED"
git -C "$SEED" commit -q --allow-empty -m base
git -C "$SEED" remote add origin "$REMOTE" && git -C "$SEED" push -q -u origin main 2>/dev/null
WORK="$TMP/work"; git clone -q "$REMOTE" "$WORK" 2>/dev/null
git -C "$SEED" commit -q --allow-empty -m novo && git -C "$SEED" push -q origin main 2>/dev/null
CACHE_DIR="$FAKE_HOME/.claude/.cache/warn-branch-behind"
fetches()  { [ -f "$TMP/fetches" ] && wc -l < "$TMP/fetches" | tr -d ' ' || echo 0; }
marcador() { /bin/ls "$CACHE_DIR"/*-main 2>/dev/null | head -n 1; }

saida="$(roda_em "$WORK")"; codigo=$?
sim "exit 0"                                       "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
sim "git fetch chamado 1 vez"                      "$([ "$(fetches)" = 1 ] && echo ok || echo fail)"
sim "marcador <sha>-main criado"                   "$([ -n "$(marcador)" ] && echo ok || echo fail)"
check "1 commit\(s\) atrás" "avisa que está 1 commit atrás" "$saida"
saida="$(roda_em "$WORK")"
sim "2ª execução na janela: fetch continua em 1"   "$([ "$(fetches)" = 1 ] && echo ok || echo fail)"
check "1 commit\(s\) atrás" "…e o aviso sai do origin/main local" "$saida"
m="$(marcador)"; [ -n "$m" ] && touch -t 202001010000 "$m"
roda_em "$WORK" >/dev/null
sim "marcador velho (>10 min): fetch de novo (2)"  "$([ "$(fetches)" = 2 ] && echo ok || echo fail)"
sim "marcador renovado"                            "$([ -n "$m" ] && [ -n "$(find "$m" -mmin -1 2>/dev/null)" ] && echo ok || echo fail)"
git -C "$WORK" pull -q --ff-only 2>/dev/null
calado "branch em dia: silencioso" "$(roda_em "$WORK")"

echo "== (B) worktree mergeado e clone principal fora da main =="
ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"; WTS="$CLONE/.claude/worktrees"
g() { "$REAL_GIT" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
G() { g -C "$CLONE" "$@"; }
"$REAL_GIT" init -q --bare -b main "$ORIGIN"
"$REAL_GIT" init -q -b main "$CLONE"
echo base > "$CLONE/base.txt"
G add base.txt; G commit -qm base
G remote add origin "$ORIGIN"; G push -qu origin main
mkdir -p "$WTS"

novo_wt()    { G worktree add -q -b "$1" "$WTS/$1" "${2:-origin/main}"; }
commit_em()  { g -C "$WTS/$1" commit -q --allow-empty -m "$2"; }
merge_main() { G merge -q --no-ff -m "merge $1" "$1"; G push -q origin main; }

novo_wt nova-suja
echo mudou >> "$WTS/nova-suja/base.txt"; echo novo > "$WTS/nova-suja/novo.txt"
novo_wt nova-limpa
novo_wt sem-reflog
G reflog expire --expire=now refs/heads/sem-reflog
novo_wt sincronizada
novo_wt feat; commit_em feat f
G worktree add -q -b empilhada "$WTS/empilhada" feat
merge_main feat
novo_wt mergeada; commit_em mergeada m; merge_main mergeada
novo_wt mergeada-suja; commit_em mergeada-suja ms; merge_main mergeada-suja
echo depois >> "$WTS/mergeada-suja/base.txt"
novo_wt squash; commit_em squash s
OID_SQUASH="$(g -C "$WTS/squash" rev-parse HEAD)"
novo_wt squash-depois; commit_em squash-depois X
OID_X="$(g -C "$WTS/squash-depois" rev-parse HEAD)"
commit_em squash-depois Y
novo_wt viva; commit_em viva v
g -C "$WTS/sincronizada" merge -q --ff-only origin/main
G commit -q --allow-empty -m "main andou"; G push -q origin main

cat > "$BIN/gh" <<GH
#!/usr/bin/env bash
case "\$1" in auth) exit 0 ;; esac
br=""; forma=""
while [ \$# -gt 0 ]; do
  case "\$1" in --head) br="\$2"; shift ;; --json) forma="\$2"; shift ;; esac
  shift
done
oid=""
case "\$br" in squash) oid="$OID_SQUASH" ;; squash-depois) oid="$OID_X" ;; esac
case "\$forma" in headRefOid) printf '%s\n' "\$oid" ;; esac
exit 0
GH
chmod +x "$BIN/gh"

# Os worktrees da fixture rastreiam origin/main e ficam atrás dela: a linha "⚠️ git:" é da
# parte (A), que já saía assim com os dois hooks separados. Aqui só conta o resto.
run() { roda_em "$WTS/$1" | grep -v '^⚠️ git:'; }

calado "nova de origin/main com mudança sem commit (o caso de 24/09)"   "$(run nova-suja)"
calado "nova de origin/main, limpa"                                     "$(run nova-limpa)"
calado "nova com o reflog expirado (linha first-parent da main)"        "$(run sem-reflog)"
calado "nova que só puxou a base (ff), com a main andando depois"       "$(run sincronizada)"
calado "empilhada numa branch que depois foi mergeada"                  "$(run empilhada)"
OUT="$(run mergeada)"
check  "já foi mergeada e está limpo"            "commit próprio em origin/main, limpa: avisa"  "$OUT"
check  "pedir a limpeza"                         "diz que a pessoa pode pedir a limpeza"        "$OUT"
check  "skill worktrees"                         "aponta o procedimento da skill worktrees"     "$OUT"
check  "cleanup-dry-run.*cleanup-apply"          "dry-run antes do apply, como na skill"        "$OUT"
check  "cleanup-apply.* só com o pedido"         "o apply só com o pedido da pessoa"            "$OUT"
check  "worktree-gc\.sh --verificar '?[^ ]*/worktrees/mergeada" "cita o --verificar com o caminho do worktree" "$OUT"
refute "gc\.sh --apply|--prune-remote"           "nunca o gc que remove"                        "$OUT"
refute "Remova|é lixo|~/\.claude/scripts"        "não manda remover nem cita ~/.claude/scripts" "$OUT"
refute "ExitWorktree"                            "não oferece ExitWorktree direto, sem a prova" "$OUT"
check  "já foi mergeada e está limpo"            "squash com tip == head do PR, limpa: avisa"   "$(run squash)"
OUT="$(run mergeada-suja)"
check  "mergeada.*mudança não commitada"         "mergeada com mudança sem commit: avisa a mudança" "$OUT"
refute "lixo|ExitWorktree|worktree-gc"           "mergeada suja nunca é chamada de lixo"        "$OUT"
calado "commit depois do head do PR mergeado"                           "$(run squash-depois)"
calado "commit próprio sem merge e sem PR"                              "$(run viva)"

G checkout -q -b no-clone
[ "$(G branch --show-current)" = no-clone ] || { echo "fixture: o clone não saiu da main"; exit 2; }
calado "sessão no próprio clone, numa feat/x: nada a avisar"            "$(roda_em "$CLONE")"
OUT="$(run viva)"
check  "clone principal .* está em 'no-clone'"   "sessão em worktree: avisa o clone fora da main" "$OUT"
check  "ofereça ao usuário voltar pra main"      "oferece a volta, sem dar ordem"               "$OUT"
refute "Sua regra|Volte pra main"                "sem 'sua regra' nem 'volte pra main'"         "$OUT"
G checkout -q main

echo "== (C) o diretório vem do .cwd do payload, não do \$PWD nem do CLAUDE_PROJECT_DIR =="
# O caso do app desktop: o processo do hook nasce na raiz do clone principal (em main, em
# dia, sem nada a avisar), e o payload diz que a sessão está no worktree mergeado.
OUT="$(payload "$WTS/mergeada" > "$TMP/payload.json"; cd "$CLONE" && HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$CLONE" PATH="$BIN:$PATH" bash "$SCRIPT" < "$TMP/payload.json" 2>&1)"
check  "já foi mergeada e está limpo"            "PWD e CLAUDE_PROJECT_DIR no clone, cwd no worktree: avisa o worktree" "$OUT"
# O inverso: o processo no worktree, o payload no clone em dia — nada a dizer do worktree.
OUT="$(payload "$CLONE" > "$TMP/payload.json"; cd "$WTS/mergeada" && HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$WTS/mergeada" PATH="$BIN:$PATH" bash "$SCRIPT" < "$TMP/payload.json" 2>&1)"
calado "PWD no worktree, cwd no clone em main: calado"                  "$OUT"
# A parte (A) também segue o payload: o WORK atrasado de novo, processo no clone em dia.
git -C "$SEED" commit -q --allow-empty -m mais && git -C "$SEED" push -q origin main 2>/dev/null
rm -rf "$CACHE_DIR"
check  "1 commit\(s\) atrás"                     "branch atrasada lida do cwd do payload, com o processo em outro repo" "$(roda_em "$WORK" "$CLONE")"
# Payload sem cwd (ou sem node): cai no CLAUDE_PROJECT_DIR, como antes.
OUT="$(cd "$TMP" && printf '{}' | HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$WTS/mergeada" PATH="$BIN:$PATH" bash "$SCRIPT" 2>&1)"
check  "já foi mergeada e está limpo"            "payload sem cwd: cai no CLAUDE_PROJECT_DIR"   "$OUT"
OUT="$(cd "$TMP" && payload "$TMP" | HOME="$FAKE_HOME" PATH="$BIN:$PATH" bash "$SCRIPT" 2>&1)"; rc=$?
sim "fora de repo git: sai 0 calado" "$([ "$rc" = 0 ] && [ -z "$OUT" ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
