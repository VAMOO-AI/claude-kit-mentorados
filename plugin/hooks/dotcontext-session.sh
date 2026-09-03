#!/usr/bin/env bash
#
# SessionStart: injeta o resumo do `.context/` do projeto (dotcontext) na abertura
# da sessão. É o único evento em que o dispatch do dotcontext devolve algo útil.
#
# Só roda onde há `.context/` — e o motivo é tempo, não gosto. Em repositório git
# SEM `.context/`, o `hook dispatch` do dotcontext 1.1.1 sai varrendo o repo e não
# volta em menos de 10 s (medido em 03/09/2026 em três repos reais, 130–150% de
# CPU; em pasta vazia ou repo com `.context/` responde em 0,2–0,6 s). Com o teto
# de 60 s do hook, cada sessão aberta num projeto sem dotcontext esperaria um
# minuto para receber o aviso "this repository does not have .context/ yet". O
# CLAUDE.md do kit já ensina o `init the context`; o aviso não paga o minuto.
#
# Binário global (`npm i -g @dotcontext/cli`, ou bun) responde em ~0,6 s; o `npx`
# leva ~1,3 s porque resolve o pacote a cada chamada. Usa o que houver.
#
# Até 0.18.0 este dispatch rodava também no PostToolUse de Write|Edit|Bash: 1,27 s
# por chamada para devolver `{"continue":true}` sem tocar arquivo nenhum. Saiu.
set -u

[ "$PWD" = "$HOME" ] && exit 0

tem_context=0
[ -d "$PWD/.context" ] && tem_context=1
if [ "$tem_context" -eq 0 ]; then
  raiz="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$raiz" ] && [ -d "$raiz/.context" ] && tem_context=1
fi
[ "$tem_context" -eq 1 ] || exit 0

if command -v dotcontext >/dev/null 2>&1; then
  dotcontext hook dispatch --source claude-code
else
  npx -y @dotcontext/cli@1.1.1 hook dispatch --source claude-code
fi
exit 0
