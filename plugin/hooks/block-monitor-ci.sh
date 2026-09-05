#!/usr/bin/env bash
# PreToolUse(Monitor): esperar CI/deploy dentro do Monitor é bloqueado.
#
# O Monitor serve para stream de UMA linha por evento (`tail -f | grep --line-buffered`,
# `inotifywait -m`, websocket). Esperar o resultado único de um CI ou de um deploy é outra
# coisa: o certo é Bash com `run_in_background`, que devolve uma notificação quando termina.
# Medido no kit do time (14 dias até 04/09/2026): 199 chamadas de Monitor, 31 erros (15,6%)
# — quase sempre um `gh pr checks` que morre no timeout. A regra existia em prosa e era
# furada; o bloqueio devolve o comando certo pronto, que é o que o agente relê e usa.
#
# Escotilha: MONITOR_CI_OK=1 no próprio comando. Lê o JSON via node (como os demais hooks
# do plugin). Falha-aberta: sem node, sem o helper ou sem comando, sai 0.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
c="$(cat | node "$H" tool_input.command)"
[ -z "$c" ] && exit 0
case "$c" in *MONITOR_CI_OK=1*) exit 0 ;; esac

ci=0
printf '%s' "$c" | grep -qE '(^|[^[:alnum:]_./-])gh[[:space:]]+(pr[[:space:]]+checks|run[[:space:]]+(watch|view|list))' && ci=1
printf '%s' "$c" | grep -qE '(^|[^[:alnum:]_./-])gh[[:space:]]+api[[:space:]]+[^;|&]*(check-runs|/status|/deployments|/runs)' && ci=1
if printf '%s' "$c" | grep -qE '(^|[^[:alnum:]_./-])(npx[[:space:]]+)?vercel([[:space:]]|$)'; then
  printf '%s' "$c" | grep -qE '(^|[[:space:]])(deploy|inspect|ls|list|logs|--prod|--wait)([[:space:]]|$)' && ci=1
fi
printf '%s' "$c" | grep -qE '(^|[^[:alnum:]_./-])supabase[[:space:]]+functions[[:space:]]+deploy' && ci=1
[ "$ci" -eq 1 ] || exit 0

echo "BLOQUEADO pelo hook: Monitor esperando CI/deploy. Monitor é para stream de UMA linha por evento (tail -f | grep --line-buffered, inotifywait); espera de CI/deploy é Bash com run_in_background, que devolve uma notificação só quando termina: 'gh pr checks <n> --watch --fail-fast > /tmp/ci.log 2>&1' · 'gh run watch <id> --exit-status > /tmp/deploy.log 2>&1' · 'vercel ... > /tmp/vercel.log 2>&1'. Precisa mesmo do Monitor aqui? Prefixe o comando com MONITOR_CI_OK=1." >&2
exit 2
