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
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
