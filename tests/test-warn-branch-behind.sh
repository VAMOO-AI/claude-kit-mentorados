#!/usr/bin/env bash
# Prova de regressão do cache de fetch do plugin/scripts/warn-branch-behind.sh.
#
# O hook SessionStart fazia `git fetch` em TODA sessão — ~1 s cada, inclusive nas
# várias que abrem no mesmo repo em poucos minutos. Agora o fetch acontece no máximo
# 1x a cada 10 min por repositório+branch, com marcador em
# ~/.claude/.cache/warn-branch-behind/<sha do git-common-dir>-<branch>; dentro da
# janela ele compara com o origin/<branch> que já está local e continua avisando.
# O que precisa continuar valendo: a 1ª execução faz fetch e cria o marcador; a 2ª,
# dentro da janela, NÃO faz fetch e ainda assim avisa; marcador velho faz fetch de
# novo; e o aviso some quando a branch está em dia.
#
# O `git` do PATH é um wrapper que conta os `fetch` e repassa tudo ao git de verdade —
# é o único jeito de saber se o remoto foi consultado sem depender de rede.
#
# Uso: bash tests/test-warn-branch-behind.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/warn-branch-behind.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
REAL_GIT="$(command -v git)" || { echo "git ausente"; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/warn-behind.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"   # o TMPDIR do macOS termina em "/"
trap 'rm -rf "$TMP"' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/git" <<EOF
#!/usr/bin/env bash
[ "\$1" = fetch ] && echo fetch >> "$TMP/fetches"
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$BIN/git"

# Um remoto bare, um clone que rastreia origin/main e um segundo clone que empurra
# um commit a mais — o primeiro fica 1 commit atrás sem saber.
REMOTE="$TMP/origin.git"; git init -q --bare -b main "$REMOTE"
SEED="$TMP/seed"; git init -q -b main "$SEED"
git -C "$SEED" commit -q --allow-empty -m base
git -C "$SEED" remote add origin "$REMOTE" && git -C "$SEED" push -q -u origin main 2>/dev/null
WORK="$TMP/work"; git clone -q "$REMOTE" "$WORK" 2>/dev/null
git -C "$SEED" commit -q --allow-empty -m novo && git -C "$SEED" push -q origin main 2>/dev/null

FAKE_HOME="$TMP/home"; mkdir -p "$FAKE_HOME"
CACHE_DIR="$FAKE_HOME/.claude/.cache/warn-branch-behind"

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
fetches()  { [ -f "$TMP/fetches" ] && wc -l < "$TMP/fetches" | tr -d ' ' || echo 0; }
marcador() { /bin/ls "$CACHE_DIR"/*-main 2>/dev/null | head -n 1; }
roda() { HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$WORK" PATH="$BIN:$PATH" bash "$SCRIPT" 2>/dev/null; }

echo "== 1ª execução: faz fetch, cria o marcador e avisa =="
saida="$(roda)"; codigo=$?
check "exit 0"                                        "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "git fetch chamado 1 vez"                       "$([ "$(fetches)" = 1 ] && echo ok || echo fail)"
check "marcador <sha>-main criado"                    "$([ -n "$(marcador)" ] && echo ok || echo fail)"
check "avisa que está 1 commit atrás"                 "$(printf '%s' "$saida" | grep -q '1 commit(s) atrás' && echo ok || echo fail)"

echo "== 2ª execução dentro da janela: não faz fetch, mas continua avisando =="
saida="$(roda)"
check "git fetch continua em 1 chamada"               "$([ "$(fetches)" = 1 ] && echo ok || echo fail)"
check "aviso sai do origin/main que já está local"    "$(printf '%s' "$saida" | grep -q '1 commit(s) atrás' && echo ok || echo fail)"

echo "== marcador velho (>10 min): faz fetch de novo =="
m="$(marcador)"; [ -n "$m" ] && touch -t 202001010000 "$m"
roda >/dev/null
check "git fetch chamado de novo (2)"                 "$([ "$(fetches)" = 2 ] && echo ok || echo fail)"
check "marcador renovado (mtime recente)"             "$([ -n "$m" ] && [ -n "$(find "$m" -mmin -1 2>/dev/null)" ] && echo ok || echo fail)"

echo "== branch em dia: silencioso =="
git -C "$WORK" pull -q --ff-only 2>/dev/null
saida="$(roda)"
check "sem aviso quando não está atrás"               "$([ -z "$saida" ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
