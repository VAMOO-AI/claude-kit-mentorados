#!/usr/bin/env bash
# Prova de regressão do boot da sessão (plugin/hooks/hooks.json).
#
# O Claude Code só processa o 1º prompt depois que os hooks de SessionStart terminam.
# Até a 0.38.1 o plugin chamava ali o `hook dispatch` do dotcontext 1.1.1, que recalcula
# o fingerprint do repo a cada sessão, sem TTL: lê e faz hash de todo arquivo, e o ignore
# dele só vale na raiz — `node_modules` aninhado, `.claude/worktrees/` e `.next` entram na
# conta. Em três repos medidos em 24/09/2026 foram de 33 mil a 110 mil arquivos por
# checagem; com o teto de 10 s, 45 de 76 execuções foram cortadas no meio. O dispatch saiu
# de todo evento — nenhum hook chama `dotcontext hook dispatch`, direto ou pelo script que
# o embrulhava. O MCP do dotcontext continua (plugin/.mcp.json). Correção pedida em
# vinilana/dotcontext#93.
#
# Uso: bash tests/test-hooks-boot.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOKS_JSON="$RAIZ/plugin/hooks/hooks.json"
[ -f "$HOOKS_JSON" ] || { echo "hooks.json não encontrado: $HOOKS_JSON"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

# Um evento e um comando por linha, separados por TAB — o mesmo leitor do
# test-hooks-convidado.sh. jq não é pré-requisito de quem instala o kit.
comandos="$(node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  for (const [evento, grupos] of Object.entries(j.hooks || {}))
    for (const g of grupos)
      for (const h of g.hooks || []) console.log(evento + "\t" + (h.command || ""));
' "$HOOKS_JSON")" || { echo "hooks.json ilegível"; exit 2; }
[ -n "$comandos" ] || { echo "hooks.json sem comando nenhum"; exit 2; }

dispatch="$(printf '%s\n' "$comandos" | grep -E 'dotcontext-session|hook dispatch' | cut -f1 | sort -u)"
check "nenhum hook, em evento nenhum, chama o dispatch do dotcontext" "$([ -z "$dispatch" ] && echo ok || echo fail)"
[ -n "$dispatch" ] && printf '        → em: %s\n' "$(printf '%s' "$dispatch" | tr '\n' ' ')"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
