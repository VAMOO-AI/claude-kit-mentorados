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
# o embrulhava. Correção pedida em vinilana/dotcontext#93; na 0.56.0 o MCP saiu também
# (plugin/.mcp.json removido), e a trava fica contra a volta do hook.
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

# D13 de 09/11/2026. Sem `timeout`, um hook de comando herda 600 s (doc de hooks): um
# `git fetch` pendurado na rede segurava a abertura da sessão por 10 minutos. Toda entrada
# declara o teto dela, e nenhuma passa de 60 s.
sem_teto="$(node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  for (const [evento, grupos] of Object.entries(j.hooks || {}))
    for (const g of grupos)
      for (const h of g.hooks || [])
        if (!(Number.isInteger(h.timeout) && h.timeout >= 1 && h.timeout <= 60))
          console.log(evento + ":" + (h.command || "").replace(/.*PLUGIN_ROOT}\//, "").replace(/"/g, "") + " (timeout=" + h.timeout + ")");
' "$HOOKS_JSON")"
check "toda entrada do hooks.json tem timeout inteiro entre 1 e 60 s" "$([ -z "$sem_teto" ] && echo ok || echo fail)"
[ -n "$sem_teto" ] && printf '        → sem teto: %s\n' "$(printf '%s' "$sem_teto" | tr '\n' ';')"

# Um dispatcher só no SessionStart: quatro entries eram quatro `sh` + quatro `bash` + três
# `node` lendo o mesmo payload, antes do 1º prompt. O compact-estado fica na entrada dele,
# porque só roda com o matcher `compact`.
ss="$(node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  for (const g of j.hooks.SessionStart || [])
    console.log((g.matcher || "-") + "\t" + (g.hooks || []).map((h) => h.command.replace(/.*PLUGIN_ROOT}\//, "").replace(/"/g, "")).join(","));
' "$HOOKS_JSON")"
esperado="$(printf -- '-\thooks/session-start.sh\ncompact\thooks/compact-estado.sh')"
check "SessionStart: o dispatcher session-start.sh sozinho, mais o compact-estado no matcher compact" "$([ "$ss" = "$esperado" ] && echo ok || echo fail)"
[ "$ss" = "$esperado" ] || printf '        → veio: %s\n' "$(printf '%s' "$ss" | tr '\n\t' ';|')"
for f in scripts/warn-branch-worktree.sh scripts/warn-kit-updated.sh hooks/warn-skills-projeto.sh hooks/warn-doc-ancorado.sh; do
  grep -qF "$f" "$RAIZ/plugin/hooks/session-start.sh" 2>/dev/null \
    && check "o session-start.sh chama $f" ok || check "o session-start.sh chama $f" fail
  [ -f "$RAIZ/plugin/$f" ] && check "$f existe" ok || check "$f existe" fail
done

# O path-rules injeta regra de quem EDITA (não commitar .env, migration irreversível, lockfile):
# no Read ele abria um node em toda leitura de arquivo para nunca ter o que dizer a mais.
m="$(node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const g = (j.hooks.PreToolUse || []).find((x) => (x.hooks || []).some((h) => h.command.includes("path-rules.sh")));
  console.log(g ? g.matcher : "");' "$HOOKS_JSON")"
check "path-rules: matcher Edit|Write|NotebookEdit, sem Read (veio: $m)" "$([ "$m" = 'Edit|Write|NotebookEdit' ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
