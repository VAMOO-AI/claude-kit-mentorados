#!/usr/bin/env bash
# Prova de regressão do par repo-session.sh + block-parallel-clone-switch.sh.
#
# O hook parseia o comando com regex para achar o repo-alvo — a classe de código que mais
# deu bug nos guard-rails: aspas no path, `~`, variável do próprio comando, heredoc contado
# como comando. O pior caso é o inverso do usual: capturar `"$W"` COM aspas fazia o
# `git -C` interno falhar e o hook sair 0 — falha ABERTA num hook cujo propósito é fechar.
#
# Uso: bash tests/test-block-parallel-clone-switch.sh [caminho-do-hook]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${1:-$RAIZ/plugin/hooks/block-parallel-clone-switch.sh}"
SESSAO="$RAIZ/plugin/hooks/repo-session.sh"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

falhas=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FORA="$TMP/fora"; mkdir -p "$FORA"                 # cwd neutro, fora de repo
CLONE="$TMP/clone"; mkdir -p "$CLONE"
git -C "$CLONE" init -q
git -C "$CLONE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$CLONE" worktree add -q "$CLONE/.wt" -b t-wt 2>/dev/null
ROOT=$(git -C "$CLONE" rev-parse --show-toplevel)
H=$(printf '%s' "$ROOT" | shasum | awk '{print $1}')

# HOME falso com marker de OUTRA sessão ativa (<30min) neste repo
COM_SESSAO="$TMP/home-com-sessao"
mkdir -p "$COM_SESSAO/.claude/.cache/repo-sessions/$H"
touch "$COM_SESSAO/.claude/.cache/repo-sessions/$H/outra-sessao"
# HOME falso onde o único marker é o da PRÓPRIA sessão
SO_EU="$TMP/home-so-eu"
mkdir -p "$SO_EU/.claude/.cache/repo-sessions/$H"
touch "$SO_EU/.claude/.cache/repo-sessions/$H/sessao-teste"

# Clone DENTRO do HOME falso: é o único jeito de exercitar `~/...`. Precisa do próprio
# marker de outra sessão (o hash é do root).
CLONE_H="$COM_SESSAO/repo-no-home"; mkdir -p "$CLONE_H"
git -C "$CLONE_H" init -q
git -C "$CLONE_H" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
H_H=$(printf '%s' "$(git -C "$CLONE_H" rev-parse --show-toplevel)" | shasum | awk '{print $1}')
mkdir -p "$COM_SESSAO/.claude/.cache/repo-sessions/$H_H"
touch "$COM_SESSAO/.claude/.cache/repo-sessions/$H_H/outra-sessao"

payload() { # <comando> <cwd> [sid]
  CMD="$1" CWD="$2" SID="${3:-sessao-teste}" node -e \
    'process.stdout.write(JSON.stringify({session_id:process.env.SID,cwd:process.env.CWD,tool_input:{command:process.env.CMD}}))'
}
decide() { # <comando> <cwd> [home]
  payload "$1" "$2" | HOME="${3:-$COM_SESSAO}" bash "$HOOK" >/dev/null 2>&1
  [ $? -eq 2 ] && echo block || echo pass
}
check() { # check <esperado> <descrição> <comando> <cwd> [home]
  local got; got=$(decide "$3" "$4" "${5:-}")
  if [ "$got" = "$1" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$2" "$1" "$got"; falhas=$((falhas+1)); fi
}

echo "== repo-session registra e apaga o marker =="
VIVO="$TMP/home-vivo"; mkdir -p "$VIVO"
payload 'ls' "$CLONE" sessao-a | HOME="$VIVO" bash "$SESSAO" touch
[ -f "$VIVO/.claude/.cache/repo-sessions/$H/sessao-a" ] && printf '  ok    touch cria o marker da sessão no hash do repo\n' || { printf '  FALHA touch não criou o marker\n'; falhas=$((falhas+1)); }
[ "$(cat "$VIVO/.claude/.cache/repo-sessions/$H/.root" 2>/dev/null)" = "$ROOT" ] && printf '  ok    .root guarda o caminho do repo\n' || { printf '  FALHA .root errado\n'; falhas=$((falhas+1)); }
payload 'ls' "$CLONE" sessao-a | HOME="$VIVO" bash "$SESSAO" end
[ ! -f "$VIVO/.claude/.cache/repo-sessions/$H/sessao-a" ] && printf '  ok    end remove o marker\n' || { printf '  FALHA end não removeu\n'; falhas=$((falhas+1)); }
payload 'ls' "$FORA" sessao-b | HOME="$VIVO" bash "$SESSAO" touch
[ -z "$(ls "$VIVO/.claude/.cache/repo-sessions/" 2>/dev/null | grep -v '^\.' | grep -v "^$H$")" ] && printf '  ok    fora de repo git não registra nada\n' || { printf '  FALHA registrou marker fora de repo\n'; falhas=$((falhas+1)); }
check pass  "depois do end não há outra sessão: checkout passa" 'git checkout main' "$CLONE" "$VIVO"
payload 'ls' "$CLONE" sessao-outra | HOME="$VIVO" bash "$SESSAO" touch
check block "marker vindo do repo-session bloqueia de verdade"  'git checkout main' "$CLONE" "$VIVO"

echo
echo "== tem que bloquear (outra sessão ativa, clone principal) =="
check block "checkout no clone (baseline)"            'git checkout main'            "$CLONE"
check block "switch no clone"                         'git switch -c feat/x'         "$CLONE"
check block "reset --hard no clone"                   'git reset --hard HEAD~1'      "$CLONE"
check block "stash mexe no working tree"              'git stash'                    "$CLONE"
check block "git -C sem aspas resolve o alvo"         "git -C $CLONE checkout x"     "$FORA"
check block "git -C com path ENTRE ASPAS"             "git -C \"$CLONE\" checkout x" "$FORA"
check block "cd com aspas antes do checkout"          "cd \"$CLONE\" && git checkout x" "$FORA"
check block "git -C com ~"                            'git -C ~/repo-no-home checkout x' "$FORA"
check block "cd com ~ antes do checkout"              'cd ~/repo-no-home && git checkout x' "$FORA"
check block "git -C \$VAR do próprio comando"         "W=$CLONE; git -C \$W checkout x" "$FORA"
# Heredoc: o corpo some do match, mas o que vem DEPOIS do terminador é comando. Tag não
# reconhecida engole o resto — e aqui a falha é ABERTA: o checkout real some junto.
NL=$'\n'; TAB=$'\t'
check block "<<- fecha com o terminador indentado por tab" \
  "cat > s.sh <<-EOF${NL}${TAB}echo oi${NL}${TAB}EOF${NL}git checkout main"                 "$CLONE"
check block "tag com hífen fecha o heredoc" \
  "cat > s.sh <<'END-OF-SCRIPT'${NL}echo oi${NL}END-OF-SCRIPT${NL}git checkout main"        "$CLONE"
check block "\$(cat <<EOF) fechado por EOF)\" e checkout depois" \
  "b=\"\$(cat <<'EOF'${NL}corpo${NL}EOF)\"${NL}git checkout main"                            "$CLONE"
check block "here-string não é heredoc" \
  "grep -q x <<<\"git checkout\"${NL}git checkout main"                                     "$CLONE"
check block "PARALLEL_OK=1 citado no heredoc não é a escotilha" \
  "cat > doc.md <<EOF${NL}rode PARALLEL_OK=1 git checkout main${NL}EOF${NL}git checkout main" "$CLONE"

echo
echo "== tem que deixar passar =="
check pass "stash list é read-only"                   'git stash list'               "$CLONE"
check pass "checkout citado em corpo de heredoc é conteúdo, não comando" \
  "cat > doc.md <<EOF${NL}git checkout main${NL}EOF"                                        "$CLONE"
check pass "o mesmo com <<-EOF e corpo indentado por tab" \
  "cat > s.sh <<-EOF${NL}${TAB}git checkout main${NL}${TAB}EOF"                             "$CLONE"
check pass "'git checkout' dentro de string não é checkout" 'echo "rode git checkout main"' "$CLONE"
check pass "worktree linkado tem git-dir próprio"     'git checkout -b feat/y'       "$CLONE/.wt"
check pass "PARALLEL_OK=1 (override consciente)"      'PARALLEL_OK=1 git checkout main' "$CLONE"
check pass "sem outra sessão ativa (marker é o meu)"  'git checkout main'            "$CLONE" "$SO_EU"
check pass "comando sem git nem checkout"             'ls -la src/'                  "$CLONE"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
