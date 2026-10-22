#!/usr/bin/env bash
# warn-sem-node.sh — UserPromptSubmit (roda primeiro no pre-prompt.sh).
# Os guards do kit começam com `command -v node || exit 0`: falham aberto para não travar a
# sessão de quem não tem node. O custo era o silêncio: sem node, block-main-commit,
# check-careful, block-parallel-clone-switch, block-delete-branch-with-children,
# block-cd-leitura-relativa e path-rules saem 0 e nada protege, sem
# ninguém ficar sabendo. Este hook é quem fala, uma vez por sessão.
#
# Sem node não há systemMessage (o pre-prompt.sh precisa do node para montar o JSON), então
# o aviso chega ao modelo como contexto e pede a ele que avise a pessoa.
# Só builtins depois do `command -v`, mais um mkdir: a máquina sem node é justamente a que
# pode não ter outras coisas (no Windows, o Git Bash sem o node no PATH). Sem como gravar o
# marcador, avisa em todo prompt — repetir é melhor que calar. Nunca bloqueia.
# Porte de VAMOO-AI/claude-config-team#312, onde o binário que falta é o jq.
command -v node >/dev/null 2>&1 && exit 0

IFS= read -r -d '' payload || true
sid=""
re='"session_id"[[:space:]]*:[[:space:]]*"([^"]*)"'
[[ $payload =~ $re ]] && sid="${BASH_REMATCH[1]//[^A-Za-z0-9_-]/}"

dir="$HOME/.claude/.cache"
marker="$dir/warn-sem-node"
if [ -n "$sid" ]; then
  anterior=""
  [ -f "$marker" ] && IFS= read -r anterior < "$marker"
  [ "$anterior" = "$sid" ] && exit 0
  { [ -d "$dir" ] || mkdir -p "$dir"; } 2>/dev/null && printf '%s\n' "$sid" > "$marker" 2>/dev/null
fi

echo "⚠️ Os guard-rails do kit estão DESLIGADOS nesta máquina: falta o node no PATH. Sem ele, block-main-commit, check-careful, block-parallel-clone-switch, block-delete-branch-with-children, block-cd-leitura-relativa e path-rules saem sem checar nada. Na sua próxima resposta, avise a pessoa disso e peça para instalar o Node.js LTS (Mac: brew install node, ou o instalador de nodejs.org; Windows: o instalador de nodejs.org ou winget install OpenJS.NodeJS.LTS; Linux: sudo apt-get install -y nodejs) e reiniciar o Claude Code. Até lá, trate commit na main, comando destrutivo e troca de branch no clone como sem proteção."
exit 0
