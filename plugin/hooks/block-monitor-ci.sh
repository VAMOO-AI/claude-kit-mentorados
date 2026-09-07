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
# 06/09/2026: `gh workflow run/view/list` e `gh run rerun` passavam batido — é a mesma espera
# com outro nome (dispara o workflow, fica olhando). Entraram no mesmo regex. Um teste
# adversarial achou mais quatro furos da mesma família, também fechados: flag antes do
# subcomando (`gh -R o/r pr checks`), invocação por caminho (`/opt/homebrew/bin/gh`),
# `npx vercel@latest` (o `@` desligava o ramo vercel inteiro) e poll de
# `api.vercel.com/vN/deployments` via curl.
#
# LIMITE CONHECIDO, deliberado: um wrapper opaco (`/tmp/espera-ci.sh`) não é detectável — o
# hook lê o texto do comando, e o texto não diz o que o script faz. Heurística por nome de
# arquivo foi recusada: pegaria `deploy.sh` de quem só quer ver log, e não pegaria o wrapper
# de nome neutro. Quem escreve o wrapper sabe o que faz; a escotilha existe para isso.
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

# A fronteira é [^[:alnum:]_.-] e NÃO inclui `/` de propósito: `/opt/homebrew/bin/gh` e
# `./gh` são a mesma espera. O `.` segue excluído para que `.github/...` não vire fronteira.
ci=0
printf '%s' "$c" | grep -qE '(^|[^[:alnum:]_.-])gh[[:space:]]+((-R|--repo)([[:space:]]+|=)[^[:space:]]+[[:space:]]+)?(pr[[:space:]]+checks|run[[:space:]]+(watch|view|list|rerun)|workflow[[:space:]]+(run|view|list))' && ci=1
printf '%s' "$c" | grep -qE '(^|[^[:alnum:]_.-])gh[[:space:]]+api[[:space:]]+[^;|&]*(check-runs|/status|/deployments|/runs)' && ci=1
if printf '%s' "$c" | grep -qE '(^|[^[:alnum:]_.-])(npx[[:space:]]+)?vercel(@[^[:space:]]+)?([[:space:]]|$)'; then
  printf '%s' "$c" | grep -qE '(^|[[:space:]])(deploy|inspect|ls|list|logs|--prod|--wait)([[:space:]]|$)' && ci=1
fi
printf '%s' "$c" | grep -qE '(^|[^[:alnum:]_.-])supabase[[:space:]]+functions[[:space:]]+deploy' && ci=1
printf '%s' "$c" | grep -qE 'api\.vercel\.com/v[0-9]+/(deployments|projects)' && ci=1
[ "$ci" -eq 1 ] || exit 0

echo "BLOQUEADO pelo hook: Monitor esperando CI/deploy. Monitor é para stream de UMA linha por evento (tail -f | grep --line-buffered, inotifywait); espera de CI/deploy é Bash com run_in_background, que devolve uma notificação só quando termina: 'gh pr checks <n> --watch --fail-fast > /tmp/ci.log 2>&1' · 'gh run watch <id> --exit-status > /tmp/deploy.log 2>&1' · 'gh workflow run <arquivo.yml> && gh run watch \$(gh run list -w <arquivo.yml> -L1 --json databaseId --jq .[0].databaseId) --exit-status > /tmp/deploy.log 2>&1' · 'vercel ... > /tmp/vercel.log 2>&1'. Precisa mesmo do Monitor aqui? Prefixe o comando com MONITOR_CI_OK=1." >&2
exit 2
