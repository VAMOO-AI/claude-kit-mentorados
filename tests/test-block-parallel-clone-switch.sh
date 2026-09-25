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

# Path com espaço no nome do repo (issue #136).
CLONE_ESP="$TMP/repo esp - novo"; mkdir -p "$CLONE_ESP"
git -C "$CLONE_ESP" init -q
git -C "$CLONE_ESP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
H_E=$(printf '%s' "$(git -C "$CLONE_ESP" rev-parse --show-toplevel)" | shasum | awk '{print $1}')
mkdir -p "$COM_SESSAO/.claude/.cache/repo-sessions/$H_E"
touch "$COM_SESSAO/.claude/.cache/repo-sessions/$H_E/outra-sessao"

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
# Path com espaço (issue #136). O regex de detecção parava no espaço e o
# hook saía 0 antes de olhar o repo; o `cd` casava, mas o path vinha truncado em `/x`.
check block "git -C com espaço no path, aspas duplas" "git -C \"$CLONE_ESP\" checkout main" "$FORA"
check block "git -C com espaço no path, aspas simples" "git -C '$CLONE_ESP' checkout main" "$FORA"
check block "cd com espaço no path"                   "cd \"$CLONE_ESP\" && git checkout main" "$FORA"
# A primeira versão do fix acima (no claude-config-team) abriu cinco buracos. A âncora do
# `cd` não conhecia `{`/then/do, e buscar o `-C` por tipo de aspa deixava o `-C "…"` de
# OUTRO comando vencer o `-C` nu do checkout.
check block "{ cd clone; git checkout; }"             "{ cd $CLONE; git checkout main; }" "$FORA"
check block "for … do cd clone; git checkout"         "for d in x; do cd $CLONE; git checkout main; done" "$FORA"
check block "then cd clone; git checkout"             "if true; then cd $CLONE; git checkout main; fi" "$FORA"
check block "if cd clone; then git checkout"          "if cd $CLONE; then git checkout main; fi" "$FORA"
check block "if git checkout (verbo logo após if)"    'if git checkout main; then :; fi' "$CLONE"
check block "-C com aspas em outro comando não rouba o alvo" \
  "git -C \"$CLONE/.wt\" status; git -C $CLONE checkout main" "$FORA"
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
# 18/09/2026: o anchor aceitava `|` solto, então o `\|` de uma alternação de grep fazia o
# PADRÃO de busca passar por comando. Tirar `|` da classe abriria buraco pior — `||` é
# operador de verdade. E o prefixo `rtk` (que reescreve o comando na máquina do kit) escapava
# o guard aqui: falha ABERTA que a cópia do claude-config-team já cobria.
check block "|| antes do git ainda bloqueia" \
  'false || git checkout main'                                                        "$CLONE"
check block "prefixo rtk não escapa o guard"          'rtk git checkout main'        "$CLONE"

# Issue #229 (team) / #140 (kit): o alvo era UM só por comando — o último `cd` da linha
# inteira, inclusive o que vem DEPOIS do verbo — e alvo que não resolvia virava `exit 0`.
check block "cd clone; checkout; cd - depois não muda o alvo" \
  "cd $CLONE && git checkout main && cd -"                                            "$FORA"
check block "cd clone; checkout; cd worktree depois não muda o alvo" \
  "cd $CLONE && git checkout main && cd $CLONE/.wt"                                   "$FORA"
check block "cd .. depois do checkout não tira o clone do alvo" \
  'git checkout main && cd ..'                                                        "$CLONE"
check block "segundo checkout não se esconde atrás do -C do primeiro" \
  "git -C $CLONE/.wt checkout x; git checkout main"                                   "$CLONE"
check block "cd dentro de subshell já fechado não muda o alvo" \
  "(cd $CLONE/.wt && git log); git checkout main"                                     "$CLONE"
check block "-C que não resolve cai no cwd, não libera" \
  'git -C /nao/existe checkout main'                                                  "$CLONE"
check block "\$VAR sem atribuição no cd cai no cwd, não libera" \
  'cd $NAO_ATRIBUIDA && git checkout main'                                            "$CLONE"

check block "D=\$(mktemp -d) com cwd no clone: alvo incerto cai no clone" \
  'D=$(mktemp -d); git -C $D checkout -b x'                                           "$CLONE"
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
check pass "padrão de grep com \\| é argumento, não comando (18/09)" \
  '/usr/bin/grep -n "gh pr\|git checkout -b\|git commit" publicar.sh'                 "$CLONE"
check pass "alternação ERE com pipe simples dentro de aspas" \
  'grep -E "git switch|git checkout main" doc.md'                                     "$CLONE"
check pass "comando sem git nem checkout"             'ls -la src/'                  "$CLONE"
check pass "checkout num worktree via -C, clone citado em outro -C" \
  "git -C \"$CLONE\" status; git -C $CLONE/.wt checkout main"                          "$FORA"
check pass "'cd' dentro de outra palavra não é cd"    "echo abcd $CLONE; git checkout main" "$FORA"

check pass "cd worktree antes, cd clone depois: checkout caiu no worktree" \
  "cd $CLONE/.wt && git checkout main && cd $CLONE"                                   "$FORA"
check pass "cd relativo para o worktree" \
  'cd .wt && git checkout main'                                                       "$CLONE"
check pass "D=\$(mktemp -d) não vira path inventado; cwd fora de repo" \
  'D=$(mktemp -d); git -C $D init -q; git -C $D checkout -b x'                        "$FORA"
check pass "reset sem --hard no clone não mexe no working tree" \
  'git reset HEAD~1; git stash list'                                                  "$CLONE"
echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
