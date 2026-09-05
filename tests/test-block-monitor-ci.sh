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
check pass  "log de deploy já em arquivo"          'tail -f /tmp/deploy.log | grep --line-buffered -E "success|failed"'
check pass  "escotilha MONITOR_CI_OK=1"            'MONITOR_CI_OK=1 gh run watch 1 --exit-status'
check pass  "payload sem comando"                  ''

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
