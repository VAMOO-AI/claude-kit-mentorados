#!/usr/bin/env bash
# Prova de regressão do hooks/block-main-commit.sh.
#
# O falso positivo que originou esta suíte (30/08/2026): `cd` com o path ENTRE ASPAS não
# era reconhecido — o char class do sed excluía `"`, o cdp saía vazio, o hook caía no cwd
# da SESSÃO e bloqueava commit legítimo dentro de worktree. E aspas é a prática correta
# aqui: há repo com espaço no nome ("WELD MENTORIA /"). O hook punia o jeito certo.
#
# `cd $VAR` sem aspas "passava" por acidente, não por acerto: o tgt virava a string
# literal `$VAR`, o git não resolvia, a branch saía vazia e o case não casava.
#
# Uso: bash tests/test-block-main-commit.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/block-main-commit.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente"; exit 2; }

falhas=0
MAIN=$(mktemp -d);  git -C "$MAIN" init -q -b main 2>/dev/null
FEAT=$(mktemp -d);  git -C "$FEAT" init -q -b feat/x 2>/dev/null
COM_ESPACO=$(mktemp -d)/"pasta com espaço"; mkdir -p "$COM_ESPACO"; git -C "$COM_ESPACO" init -q -b feat/y 2>/dev/null

# O caso de 31/08, que a suíte anterior não reproduzia: o path com espaço tem
# como PREFIXO um repo que existe e está em main. Truncar no primeiro espaço
# não devolve "path inválido" (que o git recusa e vira passe), devolve OUTRO
# REPO — e aí o hook decide pela branch errada, nas duas direções.
GEMEO=$(mktemp -d)
IRMAO_MAIN="$GEMEO/projeto";          mkdir -p "$IRMAO_MAIN"
git -C "$IRMAO_MAIN" init -q -b main 2>/dev/null
IRMAO_WT="$GEMEO/projeto - cópia/wt"; mkdir -p "$IRMAO_WT"
git -C "$IRMAO_WT" init -q -b feat/z 2>/dev/null

# O til só é testável com repo DENTRO do $HOME: `~/x` só faz sentido relativo a ele.
# `git -C "~/x"` não resolve — bash não expande til dentro de aspas, e o hook usa aspas.
NO_HOME=$(mktemp -d "$HOME/.tmp-hooktest-XXXXXX")
HOME_FEAT="$NO_HOME/wt";   mkdir -p "$HOME_FEAT";   git -C "$HOME_FEAT" init -q -b feat/til 2>/dev/null
HOME_MAIN="$NO_HOME/main"; mkdir -p "$HOME_MAIN";   git -C "$HOME_MAIN" init -q -b main 2>/dev/null
TIL_FEAT="~/${HOME_FEAT#"$HOME"/}"
TIL_MAIN="~/${HOME_MAIN#"$HOME"/}"

trap 'rm -rf "$MAIN" "$FEAT" "$(dirname "$COM_ESPACO")" "$GEMEO" "$NO_HOME"' EXIT

decide() { # decide <comando> [cwd]
  jq -nc --arg c "$1" --arg d "${2:-$MAIN}" '{cwd:$d, tool_input:{command:$c}}' \
    | bash "$HOOK" >/dev/null 2>&1
  [ "$?" = 2 ] && echo bloqueia || echo passa
}
check() { # check <esperado> <descrição> <comando> [cwd]
  local got; got=$(decide "$3" "${4:-}")
  if [ "$got" = "$1" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$2" "$1" "$got"; falhas=$((falhas+1)); fi
}

echo "== tem que bloquear (é pra isso que ele existe) =="
check bloqueia "commit direto com a sessão em main"        'git commit -q -m x'
check bloqueia "cd pra repo em main"                       "cd $MAIN && git commit -m x"
check bloqueia "cd pra repo em main, com aspas"            "cd \"$MAIN\" && git commit -m x"
check bloqueia "git -C apontando pra main"                 "git -C $MAIN commit -m x"
check bloqueia "git -C com aspas apontando pra main"       "git -C \"$MAIN\" commit -m x"
check bloqueia "commit embutido em bash -c"                "bash -c 'git commit -m x'"
check bloqueia "git -C com aspas E espaço apontando pra main" \
                                                           "git -C \"$IRMAO_MAIN\" commit -m x" "$FEAT"
check bloqueia "path inexistente não vira passe livre"     "cd /nao/existe/aqui && git commit -m x"
check bloqueia "cd com ~ pra repo em main"                 "cd $TIL_MAIN && git commit -m x" "$FEAT"
# Falha ABERTA que motivou o fix: o path era a string literal `$WT`, o git não resolvia,
# o hook decidia pelo cwd (uma feature branch) e o commit caía em main sem aviso.
check bloqueia "git -C \$VAR do próprio comando apontando pra main" \
                                                           "WT=$MAIN; git -C \$WT commit -m x" "$FEAT"
check bloqueia "cd \$VAR do próprio comando apontando pra main" \
                                                           "WT=$MAIN; cd \$WT && git commit -m x" "$FEAT"
# Heredoc (03/09): o corpo some do match, mas o que vem DEPOIS do terminador é comando.
# Tag não reconhecida engole o resto do comando e o commit em main passa — cada forma
# de fechar (tab do `<<-`, `EOF)"` do `$(cat <<EOF`, tag com hífen) precisa ser vista.
NL=$'\n'; TAB=$'\t'
check bloqueia "commit depois de um heredoc fechado"        "cat > s.sh <<'EOF'${NL}echo oi${NL}EOF${NL}git commit -m x"
check bloqueia "<<- fecha com o terminador indentado por tab" \
                                                           "cat > s.sh <<-EOF${NL}${TAB}echo oi${NL}${TAB}EOF${NL}git commit -m x"
check bloqueia "\$(cat <<EOF) fechado por EOF)\" e commit depois" \
                                                           "b=\"\$(cat <<'EOF'${NL}corpo${NL}EOF)\"${NL}git commit -m x"
check bloqueia "&& git commit na linha após o \$(cat <<EOF)" \
                                                           "gh pr create --body \"\$(cat <<'EOF'${NL}corpo${NL}EOF${NL})\" && git commit -m x"
check bloqueia "tag com hífen fecha o heredoc"              "cat > s.sh <<'END-OF-SCRIPT'${NL}echo oi${NL}END-OF-SCRIPT${NL}git commit -m x"
check bloqueia "here-string não é heredoc"                  "grep -q x <<<\"git commit\"${NL}git commit -m x"
# O corpo não pode contaminar o resto: `cd <worktree>` de dentro dele resolvia o
# repo-alvo e deixava o commit REAL em main passar (falha aberta do hook anterior).
check bloqueia "cd pra feature branch DENTRO do heredoc não resolve o alvo" \
                                                           "cat > s.sh <<'EOF'${NL}cd $FEAT && git commit -m x${NL}EOF${NL}git commit -m x"
check bloqueia "HOTFIX_MAIN=1 citado no heredoc não é a escotilha" \
                                                           "cat >> CHANGELOG.md <<'EOF'${NL}prefixe com HOTFIX_MAIN=1${NL}EOF${NL}git commit -m x"

echo
echo "== não pode bloquear =="
check passa "cd pra worktree em feature branch"            "cd $FEAT && git commit -m x"
check passa "cd COM ASPAS pra feature branch (o falso positivo de 30/08)" \
                                                           "cd \"$FEAT\" && git commit -m x"
check passa "path com espaço só funciona com aspas"        "cd \"$COM_ESPACO\" && git commit -m x"
check passa "worktree cujo prefixo truncado é um repo em main (31/08)" \
                                                           "cd \"$IRMAO_WT\" && git commit -m x" "$IRMAO_MAIN"
check passa "o mesmo com aspas simples"                    "cd '$IRMAO_WT' && git commit -m x" "$IRMAO_MAIN"
check passa "git -C para esse mesmo worktree"              "git -C \"$IRMAO_WT\" commit -m x" "$IRMAO_MAIN"
check passa "git -C pra feature branch"                    "git -C $FEAT commit -m x"
# Falsos positivos de 01/09: `~` não expande dentro das aspas do hook, e variável
# atribuída no próprio comando chegava crua — os dois caíam no cwd da sessão (main).
check passa "cd com ~ pra worktree em feature branch"      "cd $TIL_FEAT && git commit -m x"
check passa "git -C com ~ pra feature branch"              "git -C $TIL_FEAT commit -m x"
check passa "git -C \$VAR do próprio comando"              "WT=$FEAT; git -C \$WT commit -m x"
check passa "git -C \${VAR} com chaves"                    "WT=$FEAT; git -C \${WT} commit -m x"
check passa "cd \$VAR do próprio comando"                  "WT=$FEAT; cd \$WT && git commit -m x"
check passa "\$VAR que o comando NÃO define cai no cwd"    "git -C \$NAO_DEFINIDA commit -m x" "$FEAT"
check passa "HOTFIX_MAIN=1 é a escotilha"                  'HOTFIX_MAIN=1 git commit -m x'
check passa "'git commit' dentro de string não é comando"  'grep -n "git commit" plugin/hooks/*.sh'
check passa "echo mencionando git commit"                  'echo "rode git commit depois"'
check passa "comando que não é commit"                     "cd $MAIN && git status"
# O falso positivo de 03/09: subagente ESCREVENDO um script (`cat > x <<'EOF'`) cujo
# corpo tem `git commit` e `bash -c`, numa sessão com cwd em main — bloqueado 3 vezes.
SCRIPT="#!/bin/bash${NL}[ \"\$(git branch --show-current)\" = feat/x ] && git commit -m x${NL}bash -c 'git commit -m y'"
check passa "heredoc <<'EOF' escrevendo script com git commit e bash -c" \
                                                           "cat > s.sh <<'EOF'${NL}${SCRIPT}${NL}EOF"
check passa "o mesmo com <<EOF sem aspas"                  "cat > s.sh <<EOF${NL}${SCRIPT}${NL}EOF"
check passa "o mesmo com <<\"EOF\""                        "cat > s.sh <<\"EOF\"${NL}${SCRIPT}${NL}EOF"
check passa "o mesmo com <<-EOF e corpo indentado por tab" \
                                                           "cat > s.sh <<-EOF${NL}${TAB}git commit -m x${NL}${TAB}bash -c 'git commit -m y'${NL}${TAB}EOF"
check passa "redirect depois da tag (cat <<'EOF' > s.sh)"  "cat <<'EOF' > s.sh${NL}git commit -m x${NL}EOF"
check passa "gh pr create com corpo heredoc que cita git commit" \
                                                           "gh pr create --title t --body \"\$(cat <<'EOF'${NL}git commit -m x rodou${NL}EOF${NL})\""

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
