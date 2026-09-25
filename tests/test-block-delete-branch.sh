#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/block-delete-branch-with-children.sh.
#
# O hook nasceu no time em 31/07/2026, quando deletar a branch de um PR fechou dois PRs
# encadeados de forma IRREVERSÍVEL (base de PR fechado é imutável). Dois bugs depois:
# ignorava o `--repo` do comando e lia o PR no repo da sessão; e contava exemplo dentro de
# heredoc como comando. Tudo com caso aqui.
#
# O `gh` é falso (PATH): responde "o PR tem filho" para que bloquear ou passar seja
# consequência só do parser — sem ele o hook consulta a rede, falha aberto, e a suíte
# daria verde com o parser certo e com o quebrado.
#
# Uso: bash tests/test-block-delete-branch.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/block-delete-branch-with-children.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

falhas=0
FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT
cat > "$FAKE/gh" <<'GH'
#!/bin/sh
echo "$*" >> "${GH_LOG:-/dev/null}"
case "$*" in
  *"pr view"*) echo feat/base ;;
  *"pr list"*) echo 99 ;;
  *) exit 1 ;;
esac
GH
chmod +x "$FAKE/gh"

decide() { # <comando> [cwd]
  CMD="$1" CWD="${2:-$PWD}" node -e \
    'process.stdout.write(JSON.stringify({cwd:process.env.CWD,tool_input:{command:process.env.CMD}}))' \
    | PATH="$FAKE:$PATH" bash "$HOOK" >/dev/null 2>&1
  [ "$?" = 2 ] && echo bloqueia || echo passa
}
check() {
  local got; got=$(decide "$3" "${4:-}")
  if [ "$got" = "$1" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$2" "$1" "$got"; falhas=$((falhas+1)); fi
}
NL=$'\n'; TAB=$'\t'

echo "== baseline: com o gh dizendo que há filho, o merge real bloqueia =="
check bloqueia "gh pr merge N --squash --delete-branch"  'gh pr merge 12 --squash --delete-branch'
check bloqueia "alias curto -d"                          'gh pr merge 12 -d --squash'
check bloqueia "--repo explícito é repassado (e bloqueia)" 'gh pr merge 75 --repo VAMOO-AI/x --squash --delete-branch'

echo
echo "== não pode nem chegar a consultar (pré-condição não casa) =="
check passa "merge sem --delete-branch"        'gh pr merge 12 --squash'
check passa "delete-branch sem número (usa a branch atual)" 'gh pr merge --squash --delete-branch'
check passa "'gh pr merge' dentro de string"   'echo "rode gh pr merge 12 --delete-branch"'
check passa "outro comando do gh"              'gh pr view 12 --json state'
check passa "DELETE_BRANCH_OK=1 é a escotilha" 'DELETE_BRANCH_OK=1 gh pr merge 12 --squash --delete-branch'

echo
echo "== corpo de heredoc é CONTEÚDO, não comando =="
check passa "exemplo dentro do --body de um PR" \
  'gh pr create --body "$(cat <<BODY
Como reproduzir:
gh pr merge 75 --repo VAMOO-AI/x --squash --delete-branch
BODY
)"'
check passa "commit -F com exemplo no corpo" \
  'git commit -F - <<MSG
o hook dispara em: gh pr merge 12 --delete-branch
MSG'
check passa "corpo indentado de <<-MSG continua sendo conteúdo" \
  "git commit -F - <<-MSG${NL}${TAB}exemplo: gh pr merge 12 --delete-branch${NL}${TAB}MSG"

echo
echo "== …mas o que vem DEPOIS do terminador é comando (falha aberta se a tag não fecha) =="
check bloqueia "<<- fecha com o terminador indentado por tab" \
  "git commit -F - <<-MSG${NL}${TAB}nota${NL}${TAB}MSG${NL}gh pr merge 12 --delete-branch"
check bloqueia "tag com hífen fecha o heredoc" \
  "cat > s.sh <<'END-OF-SCRIPT'${NL}nota${NL}END-OF-SCRIPT${NL}gh pr merge 12 --delete-branch"
check bloqueia "\$(cat <<EOF) fechado por EOF)\"" \
  "b=\"\$(cat <<'EOF'${NL}nota${NL}EOF)\"${NL}gh pr merge 12 --delete-branch"
check bloqueia "here-string não é heredoc" \
  "grep -q x <<<\"gh pr merge\"${NL}gh pr merge 12 --delete-branch"
check bloqueia "DELETE_BRANCH_OK=1 citado no heredoc não é a escotilha" \
  "cat > doc.md <<EOF${NL}rode DELETE_BRANCH_OK=1 gh pr merge 12 --delete-branch${NL}EOF${NL}gh pr merge 12 --delete-branch"

echo
echo "== seletor do PR em qualquer posição (falha aberta até 25/09) =="
# O sed antigo só via o número colado no `merge`: `gh pr merge --squash 42 --delete-branch`
# saía sem número, caía no exit 0 e o guard sumia — justamente a ordem que muita gente digita.
check bloqueia "número depois das flags"         'gh pr merge --squash 12 --delete-branch'
check bloqueia "número no fim"                   'gh pr merge --squash --delete-branch 12'
check bloqueia "#número"                         'gh pr merge "#12" -d'
check bloqueia "#número com aspas simples"         "gh pr merge '#12' -d"
check bloqueia "valor de flag com ; entre aspas não corta os argumentos" \
  'gh pr merge --subject "fix; x" 12 --delete-branch'
check bloqueia "URL do PR"                       'gh pr merge https://github.com/A/B/pull/12 --delete-branch'
check passa "sem seletor continua passando"      'gh pr merge --squash --delete-branch'
check passa "valor de --subject não é o seletor" 'gh pr merge --subject 12 --squash --delete-branch'
check bloqueia "URL entre aspas"                 'gh pr merge "https://github.com/A/B/pull/12" --delete-branch'
check bloqueia "branch como seletor"             'gh pr merge feat/base -d'
check bloqueia "-d colado no ;"                  'gh pr merge 12 --squash -d; git pull'
check bloqueia "-d colado no &&"                 'gh pr merge 12 --squash -d&& git pull'
check bloqueia "flag curta combinada (-sd)"      'gh pr merge -sd 12'
check bloqueia "merge como condição de if"       'if gh pr merge 12 --delete-branch; then :; fi'
check bloqueia "dentro de for … do"              'for n in 12; do gh pr merge 12 -d; done'
check bloqueia "com env na frente"               'GH_PROMPT_DISABLED=1 gh pr merge 12 -d'
check bloqueia "-d depois de \\ de continuação"    "gh pr merge 12 --squash \\${NL}  --delete-branch"
check bloqueia "seletor depois de \\ de continuação" "gh pr merge \\${NL}  12 --squash -d"
check bloqueia "-d depois de --body multi-linha"  "gh pr merge 12 --squash --body \"l1${NL}l2\" --delete-branch"
check bloqueia "-d depois de --body \"\$(cat <<EOF)\"" "gh pr merge 12 --squash --body \"\$(cat <<'EOF'${NL}corpo${NL}EOF${NL})\" --delete-branch"
check bloqueia "-d depois de heredoc fechado por EOF)\"" "gh pr merge 12 --squash --body \"\$(cat <<'EOF'${NL}corpo${NL}EOF)\" --delete-branch"
check bloqueia "aspa escapada no --subject"       'gh pr merge 12 --subject "it\"s" -d'
check passa "--delete-branch=false"              'gh pr merge 12 --delete-branch=false'
check passa "-d de outro comando da linha"       'gh pr merge 12 --squash && git branch -d x'
check passa "-d depois de # é comentário"        'gh pr merge 12 --squash # -d'

GH_LOG=$(mktemp); export GH_LOG
gh_viu() { # gh_viu <descrição> <primeira chamada esperada ao gh> <comando>
  : > "$GH_LOG"; decide "$3" >/dev/null
  if [ "$(head -1 "$GH_LOG")" = "$2" ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s (gh recebeu: %s)\n' "$1" "$(head -1 "$GH_LOG")"; falhas=$((falhas+1)); fi
}
V='--json headRefName -q .headRefName'
gh_viu "-R é o alias curto de --repo"   "pr view 12 --repo A/B $V" 'gh pr merge -R A/B --squash 12 -d'
gh_viu "--repo=X"                       "pr view 12 --repo A/B $V" 'gh pr merge 12 --repo=A/B --delete-branch'
gh_viu "-R antes do pr (gh -R A/B pr merge)" "pr view 12 --repo A/B $V" 'gh -R A/B pr merge 12 -d'
gh_viu "repo sai da URL do PR"          "pr view 12 --repo A/B $V" 'gh pr merge https://github.com/A/B/pull/12 --delete-branch'
# O -R de outro comando virava o repo: `--repo dist`, o gh real falhava e o guard sumia.
gh_viu "-R do cp não é o repo"          "pr view 12 $V" 'cp -R dist out && gh pr merge 12 --squash -d'
gh_viu "-R do chmod depois também não"  "pr view 12 $V" 'gh pr merge 12 --squash -d && chmod -R 755 bin'
gh_viu "--repo de outro gh da linha não vale" "pr view 12 --repo A/B $V" 'gh pr merge 12 --repo A/B -d; gh pr view 1 -R C/D'
# Dois merges na linha: o que tem -d é o que apaga a base (31/07/2026, no time: um merge matou dois PRs encadeados).
gh_viu "checa o merge que tem -d, não o último" "pr view 333 $V" 'gh pr merge 333 --squash -d && gh pr merge 334 --squash'
gh_viu "o mesmo em duas linhas"         "pr view 333 $V" "gh pr merge 333 --squash -d${NL}gh pr merge 334 --squash"
unset GH_LOG

# `\+` é GNU: no sed do macOS o `#` não entrava e a lista de filhos saía "99".
msg=$(CMD='gh pr merge 12 --delete-branch' CWD="$PWD" node -e \
    'process.stdout.write(JSON.stringify({cwd:process.env.CWD,tool_input:{command:process.env.CMD}}))' \
  | PATH="$FAKE:$PATH" bash "$HOOK" 2>&1 >/dev/null)
case "$msg" in
  *"(feat/base): #99"*) printf '  ok    %s\n' "mensagem lista os filhos como #N" ;;
  *) printf '  FALHA %s (veio: %s)\n' "mensagem lista os filhos como #N" "$(printf '%s' "$msg" | head -1)"; falhas=$((falhas+1)) ;;
esac

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
