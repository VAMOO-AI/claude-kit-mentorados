#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/warn-doc-ancorado.sh (SessionStart).
#
# Handoff e baseline trazem "**Base:** <branch> @ `<sha>`"; o hook avisa quando o repo andou
# 40+ commits desde esse SHA. O que precisa valer: 40+ commits avisa e 39 não, SHA que o
# repo não conhece não conta, os dois formatos de `**Base:**` são lidos, cala no mesmo repo
# depois de avisar, dois repos com a mesma pasta não calam um ao outro, e exit 0 em todos os
# casos (hook que aborta derruba o prompt).
#
# Veio do kit do time (F8a do núcleo único), que decidia o repo por
# `${CLAUDE_PROJECT_DIR:-$PWD}`. Numa sessão de worktree do app desktop esse diretório pode
# ser outro, então aqui o repo vem do `.cwd` do payload (lido por node), com o env e o $PWD
# só de reserva. O caso "desktop" prova isso.
#
# Uso: bash tests/test-warn-doc-ancorado.sh [caminho-do-hook]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${1:-$RAIZ/plugin/hooks/warn-doc-ancorado.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
HOOK="$(cd "$(dirname "$HOOK")" && pwd -P)/$(basename "$HOOK")"   # o teste roda o hook de dentro do projeto

TMP="$(mktemp -d "${TMPDIR:-/tmp}/warn-doc-ancorado.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

FAKE_HOME="$TMP/home"; mkdir -p "$FAKE_HOME"
G() { git -C "$1" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null -c commit.gpgsign=false "${@:2}"; }
RC=0
roda() { # roda <dir do projeto>: payload com o cwd; guarda a saída em $saida e o exit em $RC
  saida="$(cd "$1" && printf '{"cwd":"%s"}' "$1" | HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1)"; RC=$?
}
# repo <dir> <n commits>: SHA de cada commit em $dir/.shas, o 1º na linha 1
repo() {
  mkdir -p "$1/.context/docs/handoffs"
  G "$1" init -q
  local i
  for i in $(seq 0 "$2"); do
    G "$1" commit -q --allow-empty -m "c$i"
    G "$1" rev-parse HEAD >> "$1/.shas"
  done
}
sha_n() { sed -n "$(( $2 + 1 ))p" "$1/.shas"; }   # sha_n <dir> <índice do commit>

echo "== doc 40+ commits atrás: avisa =="
A="$TMP/a/proj"; repo "$A" 45
printf '# Baseline\n\n**Base:** main @ `%s`\n' "$(sha_n "$A" 0)" > "$A/.context/docs/baseline.md"
printf '**Base:** `feat/x` @ `%s` (handoff)\n' "$(sha_n "$A" 5)" > "$A/.context/docs/HANDOFF-x.md"
printf '**Base:** main @ `%s`\n' "$(sha_n "$A" 6)" > "$A/.context/docs/handoffs/quase.md"
printf '**Base:** main @ `deadbeefcafe1234`\n' > "$A/.context/docs/handoffs/sumiu.md"
roda "$A"
check "sai 0"                                      "$([ "$RC" = 0 ] && echo ok || echo fail)"
check "avisa"                                      "$(printf '%s' "$saida" | grep >/dev/null 'doc ancorado em SHA distante' && echo ok || echo fail)"
check "baseline 45 commits atrás entra"            "$(printf '%s' "$saida" | grep >/dev/null 'baseline.md — 45 commits' && echo ok || echo fail)"
check "40 commits atrás entra (formato com branch em crase)" "$(printf '%s' "$saida" | grep >/dev/null 'HANDOFF-x.md — 40 commits' && echo ok || echo fail)"
check "39 commits atrás fica fora"                 "$(printf '%s' "$saida" | grep >/dev/null 'quase.md' && echo fail || echo ok)"
check "SHA que o repo não conhece fica fora"       "$(printf '%s' "$saida" | grep >/dev/null 'sumiu.md' && echo fail || echo ok)"

echo "== cala no mesmo repo depois de avisar =="
roda "$A"
check "segunda sessão do dia: silêncio"            "$([ -z "$saida" ] && [ "$RC" = 0 ] && echo ok || echo fail)"
B="$TMP/b/proj"; repo "$B" 41
printf '**Base:** main @ `%s`\n' "$(sha_n "$B" 0)" > "$B/.context/docs/baseline.md"
roda "$B"
check "outro repo com a mesma pasta ainda avisa"   "$(printf '%s' "$saida" | grep >/dev/null 'baseline.md — 41 commits' && echo ok || echo fail)"

echo "== desktop: o repo vem do .cwd do payload, não do \$PWD nem do env =="
W="$TMP/w/worktree"; repo "$W" 42
printf '**Base:** main @ `%s`\n' "$(sha_n "$W" 0)" > "$W/.context/docs/baseline.md"
OUTRO="$TMP/w/clone"; mkdir -p "$OUTRO"
saida="$(cd "$OUTRO" && printf '{"cwd":"%s"}' "$W" | HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$OUTRO" bash "$HOOK" 2>&1)"; RC=$?
check "payload com cwd do worktree: avisa"         "$(printf '%s' "$saida" | grep >/dev/null 'baseline.md — 42 commits' && echo ok || echo fail)"
check "payload com cwd do worktree: sai 0"         "$([ "$RC" = 0 ] && echo ok || echo fail)"
V="$TMP/v/sem-payload"; repo "$V" 40
printf '**Base:** main @ `%s`\n' "$(sha_n "$V" 0)" > "$V/.context/docs/baseline.md"
saida="$(cd "$V" && HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$V" bash "$HOOK" 2>&1 </dev/null)"; RC=$?
check "payload vazio: cai no CLAUDE_PROJECT_DIR"   "$(printf '%s' "$saida" | grep >/dev/null 'baseline.md — 40 commits' && echo ok || echo fail)"

echo "== caso bom e fora de escopo: silêncio, exit 0, sem marcador =="
C="$TMP/c/fresco"; repo "$C" 3
printf '**Base:** main @ `%s`\n' "$(sha_n "$C" 3)" > "$C/.context/docs/baseline.md"
roda "$C"
check "doc no HEAD: silêncio"                      "$([ -z "$saida" ] && [ "$RC" = 0 ] && echo ok || echo fail)"
check "doc no HEAD: não grava marcador"            "$(ls "$FAKE_HOME/.claude/.cache/doc-ancorado" 2>/dev/null | grep -q '^fresco-' && echo fail || echo ok)"
D="$TMP/d/sem-git"; mkdir -p "$D/.context/docs"; printf '**Base:** main @ `abc1234`\n' > "$D/.context/docs/baseline.md"
roda "$D"
check "fora de git: silêncio e exit 0"             "$([ -z "$saida" ] && [ "$RC" = 0 ] && echo ok || echo fail)"
E="$TMP/e/sem-context"; mkdir -p "$E"; G "$E" init -q
roda "$E"
check "repo sem .context: silêncio e exit 0"       "$([ -z "$saida" ] && [ "$RC" = 0 ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; fi
exit "$falhas"
