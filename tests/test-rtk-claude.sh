#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/rtk-claude.sh (porte do kit do time, F3 do #241).
#
# Este é o hook do dialeto do Claude Code (comando como string), irmão do
# rtk-codex.sh. A única coisa que ele acrescenta ao `rtk hook claude` cru é a
# guarda de worktree: sessão isolada tem um guard do harness que só lê `git` como
# PRIMEIRO token, então `rtk git add x` é recusado e o comando não roda.
#
# O que a suíte isola: "delegou ao rtk" vs "saiu calado pela guarda". O rtk de
# mentira abaixo reescreve tudo, então quem sair sem reescrita saiu pela guarda.
#
# Uso: bash tests/test-rtk-claude.sh [caminho-do-hook]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${1:-$RAIZ/plugin/hooks/rtk-claude.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }

falhas=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A lista de segredo sai do deny dos settings que o harness carrega. HOME de mentira com o
# template do plugin, que o /kit-vamoo:setup leva para a máquina: no CI não existe ~/.claude,
# e na máquina de quem roda o deny instalado tem o que a pessoa acrescentou.
CASA="$TMP/casa"
mkdir -p "$CASA/.claude"
cp "$RAIZ/plugin/templates/settings.json" "$CASA/.claude/settings.json"
PROJ=""

# `rtk hook claude` de mentira: lê o payload do stdin e devolve updatedInput.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/rtk" <<'MOCK'
#!/bin/bash
if [ "$1" = "hook" ] && [ "$2" = "claude" ]; then
  cat >/dev/null
  echo '{"hookSpecificOutput":{"updatedInput":{"command":"rtk <reescrito>"}}}'
  exit 0
fi
exit 0
MOCK
chmod +x "$TMP/bin/rtk"

saida() { printf '%s' "$1" | HOME="$CASA" CLAUDE_PROJECT_DIR="$PROJ" PATH="$TMP/bin:$PATH" bash "$HOOK" 2>/dev/null; }

# cwd SEMPRE explícito: a guarda lê `.cwd` e cai no $PWD quando ele falta, então
# sem fixar aqui a suíte mudaria de resultado conforme o diretório de onde roda.
CWD_NEUTRO=/Users/alguem/WORKSPACES/PROJETO
CWD_WORKTREE=/Users/alguem/WORKSPACES/PROJETO/.claude/worktrees/feat-x

decide_em() { # <cwd> <comando>
  local out; out=$(saida "$(jq -nc --arg c "$2" --arg d "$1" '{cwd:$d,tool_input:{command:$c}}')")
  case "$out" in *updatedInput*) echo rw ;; *) echo quiet ;; esac
}
check() { # <esperado> <descrição> <comando> [cwd]
  local got; got=$(decide_em "${4:-$CWD_NEUTRO}" "$3")
  if [ "$got" = "$1" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$2" "$1" "$got"; falhas=$((falhas+1)); fi
}

echo "== fora de worktree, delega ao rtk como antes =="
check rw "git status é reescrito"        'git status'
check rw "git add é reescrito"           'git add arquivo.md'
check rw "npm não é git, é reescrito"    'npm run build'

echo
echo "== em worktree isolado, git NÃO pode ganhar prefixo (03/09/2026) =="
check quiet "git add"              'git add arquivo.md'          "$CWD_WORKTREE"
check quiet "git commit"           'git commit -m "x"'           "$CWD_WORKTREE"
check quiet "git status"           'git status'                  "$CWD_WORKTREE"
check quiet "git depois de &&"     'cd app && git log -1'        "$CWD_WORKTREE"
check quiet "git depois de ;"      'echo oi; git diff'           "$CWD_WORKTREE"
check quiet "sudo git"             'sudo git fetch'              "$CWD_WORKTREE"
check quiet "layout .claude-worktrees" 'git status' \
  "/Users/alguem/WORKSPACES/PROJETO/.claude-worktrees/wt1"

echo
echo "== git push NUNCA é reescrito, em nenhum cwd (furo do deny de force push, 20/10/2026) =="
# Todo padrão de force push do deny — Bash(git *push* … main/master …) — começa com `git `.
# Fora de worktree o rtk reescrevia `git push … main` para `rtk git push …`, que o deny não casa;
# e o guard de worktree do harness é por-cwd (não cobre cwd fora de worktree), então em bypass um
# force push em main vazou ao vivo (prova-hm, 20/10/2026). push tem economia de token nula.
check quiet "push -f HEAD:main fora de worktree"  'git push -f origin HEAD:main'
check quiet "push +HEAD:main fora de worktree"    'git push origin +HEAD:main'
check quiet "push --force main"                   'git push --force origin main'
check quiet "push origin main --force"            'git push origin main --force'
check quiet "git -C … push -f (flag global antes)" 'git -C /tmp/x push -f origin HEAD:main'
check quiet "push depois de &&"                   'cd x && git push -f origin main'
check quiet "sudo git push"                       'sudo git push --force origin main'
check quiet "push normal também (economia nula)"  'git push origin feat/x'
check quiet "push -f em worktree segue quiet"     'git push -f origin main'  "$CWD_WORKTREE"
# fronteira: o que NÃO é um push segue reescrito, mesmo com "push" em outro lugar
check rw    "git log --grep=push ainda reescreve" 'git log --grep=push'
check rw    "git status (não é push) reescreve"   'git status'
check rw    "echo push (sem git) reescreve"       'echo push origin main'
# Residual do #377 (20/10/2026): a guarda ancorava o `git` logo após o separador, só com
# `sudo` opcional. Mas o CLI casa o deny depois de atribuição de env e dos wrappers que ele
# tira (`command`, `timeout`, …): `FOO=1 git push …` virava `FOO=1 rtk git push …`, o CLI
# tirava o prefixo e via `rtk git push`, que o deny não casa. Estas FALHAM no #377 e passam
# com o prefixo generalizado.
check quiet "atribuição de env antes do git"      'FOO=1 git push -f origin HEAD:main'
check quiet "GIT_SSH_COMMAND antes do git"        'GIT_SSH_COMMAND=x git push -f origin HEAD:main'
check quiet "wrapper command antes do git"        'command git push -f origin HEAD:main'
check quiet "wrapper timeout com argumento"       'timeout 30 git push --force origin main'
check quiet "env + git push depois de &&"         'ls && FOO=1 git push origin +HEAD:main'
# Fronteira: a generalização do prefixo não pode passar a casar quem não tem `git … push`.
check rw    "push sem git (npm) segue reescrito"  'npm run push-check'
check rw    "git sem push segue reescrito"        'FOO=1 git status'

echo
echo "== o que NÃO é git segue reescrito, inclusive dentro do worktree =="
check rw "npm dentro do worktree"                'npm ci'              "$CWD_WORKTREE"
check rw '"git" dentro de palavra (digitos)'     'echo digitos'        "$CWD_WORKTREE"
check rw "githubCommitSha num curl"              'curl -s https://x/githubCommitSha' "$CWD_WORKTREE"

echo
echo "== comando que toca arquivo de segredo NÃO é reescrito (15/10/2026) =="
# O deny do harness só reconhece a leitura no comando cru. Reescrito para `rtk read`/
# `rtk grep` (este último com allow), ele leu um .env.local falso em bypass e em
# acceptEdits (docs/medicao-guards-2026-10-15.md).
check quiet "cat .env.local"                 'cat /x/app/.env.local'
check quiet "grep -c em .env"                "grep -c '^KEY=' .env"
check quiet "head .env.production"           'head -1 config/.env.production'
check quiet ".env.tokens do kit"             'grep -c X ~/.claude/.env.tokens'
check quiet ".env depois de cd"              'cd app && cat .env'
check rw    ".env.example é commitado: segue reescrito" 'cat .env.example'
check rw    ".env.local.example também"      'cat .env.local.example'
check rw    ".env.1password só tem referência op://" 'cat .env.1password'
check quiet "chave ssh"                      'cat ~/.ssh/id_ed25519.pub'
check quiet "id_rsa"                         'head -1 /home/u/.ssh/id_rsa'
check quiet ".pem"                           'cat certs/server.pem'
check quiet ".netrc"                         'cat ~/.netrc'
check quiet ".npmrc"                         'cat ~/.npmrc'
check quiet "hosts.yml do gh"                'cat ~/.config/gh/hosts.yml'
check quiet "~/.claude.json"                 'jq .oauthAccount ~/.claude.json'
check quiet "serviceAccountKey.json"         'cat serviceAccountKey.json'
check quiet "credenciais da aws"             'cat ~/.aws/credentials'
check quiet "state do claude"                'ls ~/.claude/state/'
check quiet "history.jsonl"                  'head -3 ~/.claude/history.jsonl'
check quiet "config do docker"               'cat ~/.docker/config.json'
check rw    "process.env num grep não é arquivo" 'grep -rn process.env.API src'
check rw    "palavra environment"            'grep -rn environment src'
check rw    "README comum"                   'cat README.md'
# Revisão do #332: o diretório vem no `cd` e o arquivo segue relativo — o nome do diretório
# aparece sem a barra final, ou o arquivo sozinho não tem cara de segredo.
check quiet "cd ~/.aws && cat credentials"   'cd ~/.aws && cat credentials'
check quiet "cd ~/.ssh && cat config"        'cd ~/.ssh && cat config'
check quiet "cd ~/.config/gh && cat hosts.yml" 'cd ~/.config/gh && cat hosts.yml'
check quiet "cd ~/.docker && cat config.json" 'cd ~/.docker && cat config.json'
check quiet "cd ~/.claude && cat state/x.json" 'cd ~/.claude && cat state/x.json'
check quiet "cd ~/.config && cat op/config"  'cd ~/.config && cat op/config'
# Caixa: no APFS (sem distinção de maiúsculas) `cat .ENV.LOCAL` abre o .env.local.
check quiet "caixa alta abre o mesmo arquivo" 'cat .ENV.LOCAL'
check quiet "caixa mista na chave ssh"        'cat ~/.SSH/ID_RSA'
check rw    "~/.claude sem state/backups segue reescrito" 'cat ~/.claude/hooks/pre-bash.sh'
check rw    "~/.config sem gh/op segue reescrito" 'ls ~/.config/zed'

echo
echo "== o que o espelho à mão deixava de fora (20/10/2026) =="
check quiet "auth do Codex"                  'cat ~/.codex/auth.json'
check quiet "auth do Codex depois de cd"     'cd ~/.codex && cat auth.json'
check rw    "config do Codex não é segredo"  'cat ~/.codex/config.toml'
check quiet "token da Vercel, espaço escapado" 'cat ~/Library/Application\ Support/com.vercel.cli/auth.json'
check quiet "token da Vercel entre aspas"    'head -c 0 "$HOME/Library/Application Support/com.vercel.cli/auth.json"'
check quiet "cópia temporária do token da Vercel" 'cat ~/Library/Application\ Support/com.vercel.cli/.auth.json.38107.1778616964077.tmp'
check quiet "token da Vercel no Linux"       'cat ~/.local/share/com.vercel.cli/auth.json'
check quiet "cópia .bak do .env.local"       'cat .env.local.bak-1785263322'
check quiet "cópia .bak do .env"             'cat .env.bak'
check quiet "cópia do cofre fora do env-backups" 'head -c 0 ~/.claude/.env.tokens.bak-2026-10-08'

echo
echo "== a lista vem do deny, não de um espelho =="
# Regra que só a pessoa (ou o projeto) tem no deny também segura a reescrita.
cp "$CASA/.claude/settings.json" "$TMP/kit.json"
jq '.permissions.deny += ["Read(~/segredos-pessoais/**)"]' "$TMP/kit.json" > "$CASA/.claude/settings.json"
check quiet "deny pessoal no settings do usuário" 'cat ~/segredos-pessoais/a.txt'
cp "$TMP/kit.json" "$CASA/.claude/settings.json"
check rw    "…e sem a regra o mesmo comando é reescrito" 'cat ~/segredos-pessoais/a.txt'
mkdir -p "$TMP/proj/.claude"
printf '%s\n' '{"permissions":{"deny":["Read(//**/credenciais-do-cliente.json)"]}}' > "$TMP/proj/.claude/settings.json"
printf '%s\n' '{"permissions":{"deny":["Read(./chaves/**)"]}}' > "$TMP/proj/.claude/settings.local.json"
PROJ="$TMP/proj"
check quiet "deny do projeto (CLAUDE_PROJECT_DIR)" 'cat config/credenciais-do-cliente.json'
check quiet "deny do settings.local do projeto" 'cat chaves/prod.key'
PROJ=""
check rw    "…e fora do projeto o mesmo comando é reescrito" 'cat config/credenciais-do-cliente.json'
# Allow não é deny: a regra Read() de um allow não pode tirar o filtro.
jq '.permissions.allow += ["Read(~/WORKSPACES/**)"]' "$TMP/kit.json" > "$CASA/.claude/settings.json"
check rw    "Read() no allow não conta"      'cat ~/WORKSPACES/app/README.md'
cp "$TMP/kit.json" "$CASA/.claude/settings.json"
# Sem settings nenhum o harness não tem deny de leitura, e reescrever não abre nada.
mv "$CASA/.claude/settings.json" "$TMP/guardado.json"
check rw    "sem settings, nada a proteger"  'cat .env.local'
mv "$TMP/guardado.json" "$CASA/.claude/settings.json"

# O cache da ERE vale enquanto for mais novo que cada settings e que o hook. Para provar que
# ele é lido e que fica velho quando deve, o cache leva uma ERE que nunca casa e o relógio
# dos arquivos anda na mão.
HOOK_ORIG=$HOOK
mkdir -p "$TMP/arvore/hooks" "$TMP/arvore/scripts"; cp "$(dirname "$HOOK_ORIG")/../scripts/hookjson.js" "$TMP/arvore/scripts/"
cp "$HOOK_ORIG" "$TMP/arvore/hooks/hook-copia.sh"; HOOK="$TMP/arvore/hooks/hook-copia.sh"
CACHE="$CASA/.claude/.cache/rtk-segredo/sem-projeto"
check quiet "cache montado no primeiro comando" 'cat .env.local'
[ -f "$CACHE" ] || { printf '  FALHA cache não foi gravado em %s\n' "$CACHE"; falhas=$((falhas+1)); }
estraga_cache() { { head -1 "$CACHE"; echo "${1:-nunca-casa-zzz}"; } > "$TMP/c" && mv "$TMP/c" "$CACHE"; }
estraga_cache; touch -t 203001010000 "$CACHE"
check rw    "cache mais novo que tudo é lido (a ERE estragada vale)" 'cat .env.local'
estraga_cache; touch -t 202001010000 "$CACHE"
check quiet "settings mais novo que o cache refaz a ERE" 'cat .env.local'
estraga_cache; touch -t 202001010000 "$CASA/.claude/settings.json"; touch -t 202101010000 "$CACHE"
check quiet "hook mais novo que o cache refaz a ERE" 'cat .env.local'
# ERE que o grep não aceita (cache corrompido) não pode desligar a proteção: na dúvida,
# nada é reescrito.
estraga_cache '('; touch -t 203001010000 "$CACHE"
check quiet "ERE inválida: nada é reescrito"   'cat README.md'
touch "$CASA/.claude/settings.json"
HOOK=$HOOK_ORIG

# Toda regra Read() do kit segura a reescrita de um `cat` no caminho que ela nega. O
# caminho sai da própria regra: `//**/` vira uma pasta qualquer, `~/` o home, `**` duas
# pastas e cada curinga uma letra.
while IFS= read -r r; do
  p=${r#'Read('}; p=${p%')'}
  c=$p
  case "$c" in '//**/'*) c="/x/proj/${c#'//**/'}" ;; '//'*) c="/${c#'//'}" ;; esac
  c=${c//'**'/a/b}; c=${c//'*'/x}; c=${c//'?'/x}
  check quiet "o deny do kit segura: $r" "cat '$c'"
done < <(jq -r '.permissions.deny[] | select(startswith("Read("))' "$RAIZ/plugin/templates/settings.json")

echo
echo "== saída consumida por outro comando ou arquivo NÃO é reescrita (03/09/2026) =="
# `rtk diff A B | grep -c '^[<>]'` devolveu 0 para 45 linhas de diferença: o filtro do
# rtk formata para o modelo, e o pipe recebeu o formato em vez do diff.
check quiet "pipe para grep -c"          'diff a.txt b.txt | grep -c "^[<>]"'
check quiet "pipe para wc"               'ls src | wc -l'
check quiet "pipe dentro de aspas conta (falso positivo aceito)" 'grep -E "a|b" arquivo.txt'
check quiet '$( ) captura a saída'       'echo "$(git status --short)"'
check quiet "crase captura a saída"      'echo `ls src`'
check quiet "xargs"                      'xargs -n1 echo < lista.txt'
check quiet "> para arquivo"             'git log --oneline > /tmp/log.txt'
check quiet ">> para arquivo"            'ls src >> saida.txt'
check rw    "2>&1 não é arquivo"         'npm test 2>&1'
check rw    ">/dev/null não é arquivo"   'npm run build >/dev/null 2>&1'
check rw    ">&2 não é arquivo"          'echo aviso >&2'
check rw    "|| não encadeia saída"      'ls src || true'
check rw    "&& não encadeia saída"      'cd app && ls'

echo
echo "== fail-open =="
out=$(printf '' | PATH="$TMP/bin:$PATH" bash "$HOOK" 2>/dev/null; echo "rc=$?")
case "$out" in *rc=0*) printf '  ok    payload vazio sai 0\n' ;;
  *) printf '  FALHA payload vazio: %s\n' "$out"; falhas=$((falhas+1)) ;; esac
out=$(printf '%s' '{"cwd":"/x","tool_input":{"command":"git status"}}' | PATH="/usr/bin:/bin" bash "$HOOK" 2>/dev/null; echo "rc=$?")
case "$out" in *rc=0*) printf '  ok    sem rtk no PATH sai 0 sem reescrever\n' ;;
  *) printf '  FALHA sem rtk: %s\n' "$out"; falhas=$((falhas+1)) ;; esac
# Sem node não dá para ler o deny nem o payload: o hook não reescreve. Reescrever às cegas
# devolveria ao harness um `cat .env.local` que ele não reconhece como leitura.
mkdir -p "$TMP/bin-sem-node"
cp "$TMP/bin/rtk" "$TMP/bin-sem-node/"
ln -s "$(command -v cat)" "$TMP/bin-sem-node/cat"
out=$(printf '%s' '{"cwd":"/x","tool_input":{"command":"ls src"}}' | HOME="$CASA" PATH="$TMP/bin-sem-node" "$(command -v bash)" "$HOOK" 2>/dev/null; echo "rc=$?")
case "$out" in *updatedInput*) printf '  FALHA sem node reescreveu: %s\n' "$out"; falhas=$((falhas+1)) ;;
  *rc=0*) printf '  ok    sem node sai 0 sem reescrever\n' ;;
  *) printf '  FALHA sem node: %s\n' "$out"; falhas=$((falhas+1)) ;; esac

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
