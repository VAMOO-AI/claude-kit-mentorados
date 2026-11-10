#!/usr/bin/env bash
# Prova de regressão do plugin/scripts/warn-branch-worktree.sh (aviso de SessionStart).
#
# Quatro partes:
#
# (A) Branch atrás do upstream, com o cache de fetch. O hook fazia `git fetch` em TODA
#     sessão (~1 s cada). Agora faz no máximo 1x a cada 10 min por repositório+branch,
#     com marcador em ~/.claude/.cache/warn-branch-behind/<sha do git-common-dir>-<branch>;
#     dentro da janela compara com o origin/<branch> local e continua avisando. O `git` do
#     PATH é um wrapper que conta os `fetch`: é o único jeito de saber se o remoto foi
#     consultado sem depender de rede.
#
# (B) Só esse aviso ficou (decisão D13 de 09/11/2026). Até a 0.90 o script também avisava de
#     worktree com branch já mergeada e de clone principal fora da main, o que pedia
#     `gh pr list` e fetch de refs/pull na abertura. Aqui se prova que os dois calaram, e que
#     o script não chama mais o `gh`.
#
# (C) O diretório vem do `.cwd` do payload, ou do KIT_SESSAO_CWD que o session-start.sh
#     entrega. Numa sessão de worktree do app desktop, o $PWD do hook (e o
#     CLAUDE_PROJECT_DIR) pode ser a raiz do clone principal.
#
# (D) O fetch tem teto de tempo, sem depender do `timeout` do coreutils (o macOS não traz):
#     fetch pendurado é morto e o aviso sai com o que já está local.
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

echo "== (B) worktree mergeado e clone fora da main não são mais assunto deste aviso =="
ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"; WTS="$CLONE/.claude/worktrees"
g() { "$REAL_GIT" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
G() { g -C "$CLONE" "$@"; }
"$REAL_GIT" init -q --bare -b main "$ORIGIN"
"$REAL_GIT" init -q -b main "$CLONE"
echo base > "$CLONE/base.txt"
G add base.txt; G commit -qm base
G remote add origin "$ORIGIN"; G push -qu origin main
mkdir -p "$WTS"
# Worktree com commit próprio, mergeado na main e limpo: era o caso do "🧹 já foi mergeada".
G worktree add -q -b mergeada "$WTS/mergeada" origin/main
g -C "$WTS/mergeada" commit -q --allow-empty -m m
G merge -q --no-ff -m "merge mergeada" mergeada; G push -q origin main
# Um `gh` que deixa rastro: o script não pode mais chamá-lo.
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$TMP/gh-chamadas"
exit 0
EOF
chmod +x "$BIN/gh"
OUT="$(roda_em "$WTS/mergeada")"
refute "já foi mergeada|worktree-gc|ExitWorktree|🧹" "sessão em worktree já mergeado: sem aviso de limpeza" "$OUT"
# Clone principal fora da main, com worktree vivo: era o "clone principal … não em main".
G checkout -q -b no-clone
OUT="$(roda_em "$WTS/mergeada")"
refute "clone principal \(|não em main" "sessão em worktree com o clone fora da main: sem aviso" "$OUT"
calado "sessão no próprio clone fora da main, sem upstream: calado" "$(roda_em "$CLONE")"
G checkout -q main
sim "o script não chama o gh" "$([ ! -e "$TMP/gh-chamadas" ] && echo ok || echo fail)"
grep -v '^[[:space:]]*#' "$SCRIPT" | grep -qE '(^|[^a-z])gh (pr|auth)' && sim "o script não cita gh pr/auth" fail || sim "o script não cita gh pr/auth" ok

echo "== (C) o diretório vem do .cwd do payload, não do \$PWD nem do CLAUDE_PROJECT_DIR =="
# O caso do app desktop: o processo do hook nasce noutro repo (em dia, sem nada a avisar),
# e o payload diz que a sessão está no WORK, que ficou atrás de novo.
git -C "$SEED" commit -q --allow-empty -m mais && git -C "$SEED" push -q origin main 2>/dev/null
rm -rf "$CACHE_DIR"
check  "1 commit\(s\) atrás"                     "branch atrasada lida do cwd do payload, com o processo em outro repo" "$(roda_em "$WORK" "$CLONE")"
# O inverso: o processo no repo atrasado, o payload num repo em dia.
calado "PWD no repo atrasado, cwd do payload num repo em dia: calado"   "$(roda_em "$CLONE" "$WORK")"
# O dispatcher (session-start.sh) entrega o cwd em KIT_SESSAO_CWD, e ele vale sobre o stdin.
OUT="$(cd "$CLONE" && printf '{}' | KIT_SESSAO_CWD="$WORK" HOME="$FAKE_HOME" PATH="$BIN:$PATH" bash "$SCRIPT" 2>&1)"
check  "1 commit\(s\) atrás"                     "KIT_SESSAO_CWD do dispatcher: lê o repo dele, sem payload" "$OUT"
# Payload sem cwd (ou sem node): cai no CLAUDE_PROJECT_DIR, como antes.
OUT="$(cd "$TMP" && printf '{}' | HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$WORK" PATH="$BIN:$PATH" bash "$SCRIPT" 2>&1)"
check  "1 commit\(s\) atrás"                     "payload sem cwd: cai no CLAUDE_PROJECT_DIR"   "$OUT"
OUT="$(cd "$TMP" && payload "$TMP" | HOME="$FAKE_HOME" PATH="$BIN:$PATH" bash "$SCRIPT" 2>&1)"; rc=$?
sim "fora de repo git: sai 0 calado" "$([ "$rc" = 0 ] && [ -z "$OUT" ] && echo ok || echo fail)"

echo "== (D) fetch pendurado: o teto mata, e o aviso sai com o que já está local =="
# Um git cujo `fetch` dorme 30 s (rede caída, remote que pede senha). Sem teto, a abertura
# da sessão esperava o fetch inteiro. O PATH do teste não tem `timeout`: o teto é do script.
LENTO="$TMP/bin-lento"; mkdir -p "$LENTO"
cat > "$LENTO/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = fetch ]; then echo fetch >> "$TMP/fetches-lentos"; sleep 30; exit 0; fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$LENTO/git"
printf '#!/bin/sh\necho "timeout não devia ser chamado" >&2\nexit 127\n' > "$LENTO/timeout"; chmod +x "$LENTO/timeout"
rm -rf "$CACHE_DIR"
payload "$WORK" > "$TMP/payload.json"
t0=$(date +%s)
OUT="$(cd "$WORK" && HOME="$FAKE_HOME" PATH="$LENTO:$PATH" WARN_BRANCH_FETCH_TETO=2 bash "$SCRIPT" < "$TMP/payload.json" 2>&1)"; rc=$?
dt=$(( $(date +%s) - t0 ))
sim "com o fetch pendurado sai 0" "$([ "$rc" = 0 ] && echo ok || echo fail)"
sim "o fetch foi tentado" "$([ -s "$TMP/fetches-lentos" ] && echo ok || echo fail)"
if [ "$dt" -le 10 ]; then printf '  ok    %s\n' "volta em ${dt}s com teto de 2 s (o fetch dormiria 30)"
else printf '  FALHA %s\n' "levou ${dt}s com teto de 2 s: o fetch pendurado segurou o hook"; falhas=$((falhas+1)); fi
check "1 commit\(s\) atrás" "…e ainda avisa pelo origin/main que já está local" "$OUT"
refute "timeout não devia" "não depende do binário timeout" "$OUT"
sim "o marcador é gravado mesmo com o fetch morto (a sessão seguinte não espera de novo)" "$([ -n "$(marcador)" ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
