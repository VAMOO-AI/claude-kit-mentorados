#!/usr/bin/env bash
# Prova do plugin/hooks/block-monitor-ci.sh (PreToolUse em Monitor): espera de CI/deploy é
# bloqueada com o comando certo na mensagem; stream de eventos passa; escotilha passa.
#
# Uso: bash tests/test-block-monitor-ci.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/block-monitor-ci.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

falhas=0
ERR=$(mktemp); trap 'rm -f "$ERR"' EXIT
decide() { # <comando>
  C="$1" node -e 'process.stdout.write(JSON.stringify({tool_input:{command:process.env.C}}))' | bash "$HOOK" >/dev/null 2>"$ERR"
  [ $? -eq 2 ] && echo block || echo pass
}
check() { # <esperado> <descrição> <comando>
  local got; got=$(decide "$3")
  if [ "$got" = "$1" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$2" "$1" "$got"; falhas=$((falhas+1)); fi
}

echo "== espera de CI/deploy: bloqueia =="
check block "gh pr checks em loop"                 'prev=""; while true; do s=$(gh pr checks 123 --json name,bucket); echo "$s"; sleep 30; done'
check block "gh run watch"                         'gh run watch 987654 --exit-status'
check block "gh run view em poll"                  'while true; do gh run view 1 --json status | jq -r .status; sleep 20; done'
check block "gh api check-runs"                    'while true; do gh api repos/o/r/commits/abc/check-runs --jq ".check_runs[].conclusion"; sleep 30; done'
check block "gh workflow run"                      'gh workflow run deploy.yml --ref main'
check block "gh workflow view em poll"             'while true; do gh workflow view deploy.yml --json state; sleep 30; done'
check block "gh workflow list"                     'gh workflow list --all'
check block "gh run rerun --watch"                 'gh run rerun 987654 --failed --watch'
check block "gh -R antes do subcomando"            'gh -R o/r pr checks 74 --watch --fail-fast > /tmp/ci.log 2>&1'
check block "gh --repo=x antes do subcomando"      'gh --repo=o/r pr checks 74 --watch'
check block "gh --repo x + run watch"              'gh --repo o/r run watch 123 --exit-status'
check block "gh por caminho absoluto"              '/opt/homebrew/bin/gh pr checks 90 --watch --fail-fast'
check block "gh por caminho relativo"              './gh run watch 123 --exit-status'
check block "vercel por caminho absoluto"          '/opt/homebrew/bin/vercel deploy --prod'
check block "npx vercel@latest deploy"             'npx vercel@latest deploy --prod'
check block "npx vercel@versão pinada"             'npx vercel@33.0.1 --prod'
check block "poll da API da Vercel via curl"       'while true; do s=$(curl -sS -H "Authorization: Bearer $T" "https://api.vercel.com/v13/deployments/dpl_abc?teamId=$ORG" | jq -r .readyState); case "$s" in READY|ERROR) break;; esac; sleep 15; done'
check block "vercel deploy"                        'vercel deploy --prod --yes 2>&1'
check block "npx vercel inspect"                   'npx vercel inspect https://x.vercel.app --wait'
check block "vercel logs"                          'vercel logs https://x.vercel.app'
check block "supabase functions deploy"            'supabase functions deploy minha-fn --project-ref abc'
grep -q 'run_in_background' "$ERR" && printf '  ok    mensagem traz o comando certo (run_in_background)\n' || { printf '  FALHA mensagem sem run_in_background: %s\n' "$(cat "$ERR")"; falhas=$((falhas+1)); }
grep -q 'gh pr checks <n> --watch --fail-fast' "$ERR" && printf '  ok    mensagem traz o gh pr checks pronto\n' || { printf '  FALHA mensagem sem o gh pr checks pronto\n'; falhas=$((falhas+1)); }

echo
echo "== stream de eventos: passa =="
check pass  "tail -f com grep line-buffered"       'tail -f /var/log/app.log | grep --line-buffered ERROR'
check pass  "inotifywait"                          'inotifywait -m --format "%e %f" /watched/dir'
check pass  "poll de comentários no PR (gh api issues)" 'while true; do gh api "repos/o/r/issues/123/comments?since=$last" --jq ".[].body"; sleep 30; done'
check pass  "vercel dev (servidor, não deploy)"    'vercel dev 2>&1 | grep --line-buffered -E "Ready|Error"'
check pass  "gh pr view (não é checks)"            'while true; do gh pr view 12 --json state --jq .state; sleep 60; done'
check pass  "gh workflow enable (não espera nada)" 'gh workflow enable deploy.yml'
check pass  "tail no arquivo do workflow"          'tail -f .github/workflows/e2e.yml'
check pass  "gh run download (não é espera)"       'gh run download 123 --name artefato'
check pass  "gh -R + pr view (poll de comentário)" 'while true; do gh -R o/r pr view 74 --comments; sleep 30; done'
check pass  "gh pr list com -R depois"             'gh pr list -R o/r --state open'
check pass  "binário de terceiro terminado em gh"  'my-gh runner start --watch'
check pass  "arquivo cujo nome parece o comando"   'tail -f docs/gh-run-watch.md'
check pass  "caminho que só começa com gh"         'tail -f /tmp/ghost/app.log'
check pass  "log de deploy já em arquivo"          'tail -f /tmp/deploy.log | grep --line-buffered -E "success|failed"'
check pass  "escotilha MONITOR_CI_OK=1"            'MONITOR_CI_OK=1 gh run watch 1 --exit-status'
check pass  "payload sem comando"                  ''

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
