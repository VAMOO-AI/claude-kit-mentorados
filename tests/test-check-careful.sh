#!/usr/bin/env bash
# Prova de regressão do hooks/check-careful.sh.
#
# Os casos vieram de 291 disparos reais colhidos nos transcripts em 29/08/2026
# (`/harness-check`): 14 dias, 318 pedidos de confirmação, dos quais ~140 na
# regra de `git push --force`. 125 desses 140 (89%) eram `git commit -F -` —
# o `-F` do heredoc casava com o `-f` do force porque o matcher usava `grep -i`
# e as duas metades da regra eram testadas no comando inteiro, não no trecho
# do push.
#
# Um `ask` de PreToolUse ATRAVESSA o bypass permissions. Cada falso positivo
# aqui é uma interrupção real no meio do trabalho — por isso o hook é testado.
#
# Este hook lê o JSON com node (o kit não exige jq), mas o teste monta o JSON com
# jq quando existe — e cai pro python3 quando não.
#
# Uso: bash tests/test-check-careful.sh [caminho-do-hook]
#   Sem argumento testa o hook do repo. Rode contra a versão anterior
#   (`git show <base>:hooks/check-careful.sh`) para ver os casos falharem.
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/check-careful.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }

falhas=0
# decide <comando> → imprime "ask" ou "pass"
decide() {
  local out
  out=$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' | bash "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; then echo ask; else echo pass; fi
}
check() { # check <esperado> <descrição> <comando>
  local got; got=$(decide "$3")
  if [ "$got" = "$1" ]; then
    printf '  ok    %s\n' "$2"
  else
    printf '  FALHA %s (esperado %s, veio %s)\n' "$2" "$1" "$got"; falhas=$((falhas+1))
  fi
}

echo "== não pode interromper (falsos positivos medidos em produção) =="
check pass "commit com heredoc -F e push na mesma linha" \
  'git add e2e/spec.ts && git commit -F - <<EOF && git push -u origin feat/x'
check pass "commit -q -F - seguido de push" \
  'cd /repo && git commit -q -F - <<EOF
msg
EOF
git push'
check pass "push normal com rm -f depois" \
  'git push origin main && rm -f /tmp/lixo.txt'
check pass "rm -rf .next (sem barra no fim)" 'rm -rf .next && npm run build'
check pass "rm -rf de pasta temporária da sessão" \
  'rm -rf /private/tmp/claude-501/sessao/scratchpad/tr'
check pass "rm -rf tmp-verify" 'rm -rf tmp-verify && docker info'
check pass "git add com paths explícitos depois do -A" 'git add -A src supabase && git commit -m wip'
check pass "grep -f não é push force" 'git push && grep -f padroes.txt arquivo.log'

echo "== tem que continuar perguntando (o que o hook existe para pegar) =="
check ask  "push --force" 'git push --force origin main'
check ask  "push -f" 'rtk git push -f origin feat/x'
check ask  "push --force-with-lease" 'git push --force-with-lease'
check ask  "rm -rf em pasta de código" 'rm -rf src/app/pagina'
check ask  "rm -rf no home" 'rm -rf ~/WORKSPACES/PROJETO'
check ask  "git add -A sozinho" 'git add -A && git commit -m wip'
check ask  "git add . sozinho" 'git add .'
check ask  "git -C outro-repo add -A" 'git -C /outro/repo add -A'
check ask  "DROP TABLE" 'psql -c "drop table clientes;"'
check ask  "TRUNCATE" 'psql -c "truncate public.pedidos cascade;"'
check ask  "supabase db reset" 'npx supabase db reset'
check ask  "cat .env.local via Bash (contorna o deny de Read)" 'cat app/.env.local'
check ask  "head .env" 'head -20 .env'
check pass ".env.example é público" 'cat .env.example'
check pass "contar chave sem ler valor" 'grep -c "^STRIPE_KEY=" .env.local'
check pass "append no .env é escrita, não leitura" \
  'grep -q SECRET .env.local || cat >> .env.local <<EOF'
check ask  "ler o cofre de tokens" 'head -6 ~/.claude/.env.tokens'

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
