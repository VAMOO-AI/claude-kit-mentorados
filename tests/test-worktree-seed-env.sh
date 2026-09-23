#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/worktree-seed-env.sh.
#
# O bug que ele fecha: o worktree nasce só com o que está commitado, o `.env.local` fica
# para trás e o sintoma aparece três camadas depois ("Failed to fetch" na tela de login).
# Os casos rodam em repos git de verdade, com worktree de verdade — o hook decide tudo por
# `git rev-parse`, então repo falso não prova nada.
#
# Além do que o time prova, aqui entram duas decisões do kit público: `.npmrc` e
# `.bunfig.toml` (token de registry) não são copiados, só citados; e a cópia só acontece se
# a branch do WORKTREE também ignora o arquivo — senão o segredo entraria no próximo commit.
#
# Uso: bash tests/test-worktree-seed-env.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/worktree-seed-env.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
DISPATCH="$(cd "$(dirname "$HOOK")" && pwd)/pre-prompt.sh"
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
PRINCIPAL="$TMP/repo"
mkdir -p "$PRINCIPAL"
git -C "$PRINCIPAL" init -q -b main
printf '%s\n' '.env' '.env.*' '!.env.example' 'node_modules/' '.npmrc' > "$PRINCIPAL/.gitignore"
printf 'VITE_SUPABASE_URL=\n' > "$PRINCIPAL/.env.example"
printf '{}\n' > "$PRINCIPAL/package.json"
git -C "$PRINCIPAL" add .gitignore .env.example package.json
git -C "$PRINCIPAL" -c user.email=t@t -c user.name=t commit -q -m init

printf 'VITE_SUPABASE_URL=https://exemplo.supabase.co\nVITE_KEY=segredo\n' > "$PRINCIPAL/.env.local"
printf 'SUPABASE_DB_URL=postgres://exemplo\n' > "$PRINCIPAL/.env"
printf '//registry.npmjs.org/:_authToken=npm_tokensecreto\n' > "$PRINCIPAL/.npmrc"
chmod 600 "$PRINCIPAL/.env.local"

roda() { ( cd "$1" && bash "$HOOK" ) >"$TMP/out" 2>"$TMP/err" </dev/null; echo $?; }
sha()  { shasum "$1" | awk '{print $1}'; }
carimbo() { printf '%s/claude-seed-env' "$(git -C "$1" rev-parse --path-format=absolute --git-dir)"; }
vazou() { grep -qF -e segredo -e postgres://exemplo -e npm_tokensecreto "$TMP/out" "$TMP/err"; }

WT="$PRINCIPAL/.claude/worktrees/feat-x"
git -C "$PRINCIPAL" worktree add -q -b feat/x "$WT" main

echo "== worktree novo recebe os env ignorados, e só eles =="
rc=$(roda "$WT")
[ "$rc" = 0 ] && ok "sai 0" || falha "esperava rc=0, veio $rc"
[ -s "$WT/.env.local" ] && ok ".env.local chegou e não está vazio" || falha ".env.local não chegou"
[ -s "$WT/.env" ] && ok ".env chegou e não está vazio" || falha ".env não chegou"
[ "$(sha "$WT/.env.local")" = "$(sha "$PRINCIPAL/.env.local")" ] \
  && ok ".env.local é byte-a-byte o do clone principal" || falha ".env.local difere do original"
# GNU primeiro: no stat do coreutils, `-f` é "status do sistema de arquivos" e SAI 0 com
# formato inválido — o fallback na ordem inversa nunca dispara no Ubuntu do CI.
modo() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }
[ "$(modo "$WT/.env.local")" = "600" ] \
  && ok "permissão 600 preservada (cp -p)" || falha "permissão do .env.local não veio junto (veio $(modo "$WT/.env.local"))"
grep -q '.env.local' "$TMP/out" && ok "o hook disse o que copiou" || falha "não avisou: $(cat "$TMP/out")"
vazou && falha "VAZOU conteúdo de env/registry no stdout/stderr" || ok "não ecoou conteúdo de nenhum arquivo"
[ -e "$WT/.env.example" ] && [ "$(git -C "$WT" status --porcelain .env.example)" = "" ] \
  && ok ".env.example continua o versionado (não foi sobrescrito por cópia)" || falha ".env.example mexido"
[ -z "$(git -C "$WT" status --porcelain)" ] && ok "o worktree continua limpo para o git (nada copiado entra em commit)" \
  || falha "a cópia aparece no git status: $(git -C "$WT" status --porcelain)"

echo
echo "== .npmrc com token: citado pelo nome, não copiado =="
[ -e "$WT/.npmrc" ] && falha "copiou o .npmrc (token de registry) por padrão" || ok ".npmrc não foi copiado"
grep -q '.npmrc' "$TMP/out" && ok "…mas o aviso diz que ele existe no clone principal" || falha "não citou o .npmrc: $(cat "$TMP/out")"

echo
echo "== node_modules: avisa, não automatiza =="
grep -q 'node_modules' "$TMP/out" && ok "avisou que falta node_modules" || falha "sem aviso de node_modules"
[ -e "$WT/node_modules" ] && falha "criou node_modules" || ok "não criou nem linkou node_modules"

echo
echo "== segunda passada: carimbo faz o caminho quente sair calado =="
rc=$(roda "$WT")
[ "$rc" = 0 ] && ok "sai 0" || falha "esperava rc=0, veio $rc"
[ -s "$TMP/out" ] && falha "repetiu aviso: $(cat "$TMP/out")" || ok "stdout vazio (carimbo no git-dir do worktree)"

echo
echo "== colisão de verdade: sem o carimbo, arquivo existente NÃO é sobrescrito =="
rm -f "$(carimbo "$WT")"
printf 'VITE_SUPABASE_URL=http://127.0.0.1:54321\n' > "$WT/.env.local"
ANTES=$(sha "$WT/.env.local")
rc=$(roda "$WT")
[ "$rc" = 0 ] && ok "sai 0" || falha "esperava rc=0, veio $rc"
[ "$(sha "$WT/.env.local")" = "$ANTES" ] \
  && ok ".env.local do worktree sobreviveu (é o do worktree, não o do clone)" || falha "SOBRESCREVEU o .env.local do worktree"

echo
echo "== caso misto: um env existe, o outro não — a decisão é por arquivo =="
# O estado de todo dia: alguém copiou o .env.local à mão e esqueceu o .env. Um `break` no
# lugar do `continue` passaria em todos os casos acima e falharia só aqui.
rm -f "$(carimbo "$WT")" "$WT/.env"
ANTES=$(sha "$WT/.env.local")
rc=$(roda "$WT")
[ "$rc" = 0 ] && ok "sai 0" || falha "esperava rc=0, veio $rc"
[ "$(sha "$WT/.env.local")" = "$ANTES" ] \
  && ok ".env.local presente continua intocado" || falha "sobrescreveu o .env.local que já existia"
[ "$(sha "$WT/.env")" = "$(sha "$PRINCIPAL/.env")" ] \
  && ok ".env ausente foi semeado na mesma passada" || falha ".env não foi copiado (decisão virou do laço, não do arquivo)"
grep -q '.env.local' "$TMP/out" && falha "anunciou um .env.local que não copiou: $(cat "$TMP/out")" || ok "o aviso nomeia só o que foi copiado"

echo
echo "== branch do worktree que NÃO ignora o env: não copia, e diz por quê =="
# O check-ignore do clone principal lê o .gitignore da main. Se a branch do worktree
# tirou o padrão, a cópia vira "untracked" e o próximo `git add .` publica o segredo.
WT2="$PRINCIPAL/.claude/worktrees/sem-ignore"
git -C "$PRINCIPAL" worktree add -q -b feat/sem-ignore "$WT2" main
printf '%s\n' 'node_modules/' > "$WT2/.gitignore"
git -C "$WT2" -c user.email=t@t -c user.name=t commit -q -am "tira o .env do gitignore"
rc=$(roda "$WT2")
[ "$rc" = 0 ] && ok "sai 0" || falha "esperava rc=0, veio $rc"
[ -e "$WT2/.env.local" ] && falha "copiou .env.local para uma branch que não o ignora" || ok ".env.local não foi copiado"
[ -e "$WT2/.env" ] && falha "copiou .env para uma branch que não o ignora" || ok ".env não foi copiado"
grep -q 'não copiei' "$TMP/out" && ok "avisou por que não copiou" || falha "calou sobre o env que ficou para trás: $(cat "$TMP/out")"
[ -z "$(git -C "$WT2" status --porcelain)" ] && ok "nada novo aparece no git status" || falha "git status sujo: $(git -C "$WT2" status --porcelain)"
vazou && falha "VAZOU conteúdo" || ok "não ecoou conteúdo"

echo
echo "== clone principal e worktree fora do .claude/worktrees não são semeados =="
rc=$(roda "$PRINCIPAL")
[ "$rc" = 0 ] && ok "no clone principal sai 0" || falha "esperava rc=0, veio $rc"
[ -s "$TMP/out" ] && falha "falou algo no clone principal: $(cat "$TMP/out")" || ok "calado no clone principal"

FORA="$TMP/fora/.claude/worktrees/impostor"
mkdir -p "$TMP/fora"
git -C "$PRINCIPAL" worktree add -q -b feat/fora "$FORA" main
rc=$(roda "$FORA")
[ "$rc" = 0 ] && ok "worktree fora da árvore do clone sai 0" || falha "esperava rc=0, veio $rc"
[ -e "$FORA/.env.local" ] && falha "copiou credencial para worktree fora do .claude/worktrees do repo" \
  || ok "não copiou para worktree fora do .claude/worktrees do clone principal"

IRMAO="$TMP/meu-worktree"
git -C "$PRINCIPAL" worktree add -q -b feat/irmao "$IRMAO" main
rc=$(roda "$IRMAO")
[ -e "$IRMAO/.env.local" ] && falha "semeou worktree irmão (git worktree add ../x)" || ok "worktree irmão (git worktree add ../x) não é semeado"

echo
echo "== repo sem env ignorado: nada a fazer, sem ruído =="
LIMPO="$TMP/limpo"; mkdir -p "$LIMPO"
git -C "$LIMPO" init -q -b main
printf 'node_modules/\n' > "$LIMPO/.gitignore"
git -C "$LIMPO" add .gitignore
git -C "$LIMPO" -c user.email=t@t -c user.name=t commit -q -m init
LWT="$LIMPO/.claude/worktrees/feat-y"
git -C "$LIMPO" worktree add -q -b feat/y "$LWT" main
rc=$(roda "$LWT")
[ "$rc" = 0 ] && ok "sai 0" || falha "esperava rc=0, veio $rc"
[ -s "$TMP/out" ] && falha "falou sem ter o que dizer: $(cat "$TMP/out")" || ok "calado"

echo
echo "== fora de git: fail-open =="
NADA="$TMP/nada/.claude/worktrees/x"; mkdir -p "$NADA"
rc=$(roda "$NADA")
[ "$rc" = 0 ] && ok "diretório sem git sai 0" || falha "esperava rc=0, veio $rc"

echo
echo "== pelo dispatcher do UserPromptSubmit, como o Claude Code chama =="
WT3="$PRINCIPAL/.claude/worktrees/pelo-dispatcher"
git -C "$PRINCIPAL" worktree add -q -b feat/dispatcher "$WT3" main
S=s1 D="$WT3" node -e 'process.stdout.write(JSON.stringify({session_id:process.env.S,cwd:process.env.D,prompt:"oi"}))' > "$TMP/payload.json"
( cd "$WT3" && bash "$DISPATCH" ) <"$TMP/payload.json" >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && ok "dispatcher sai 0" || falha "dispatcher saiu $rc: $(cat "$TMP/err")"
[ "$(sha "$WT3/.env.local" 2>/dev/null)" = "$(sha "$PRINCIPAL/.env.local")" ] \
  && ok "o worktree aberto por EnterWorktree ganha o .env.local no primeiro prompt" || falha "o dispatcher não semeou o worktree"
grep -q '.env.local' "$TMP/out" && ok "o aviso chega na saída do dispatcher" || falha "sem aviso na saída do dispatcher: $(cat "$TMP/out")"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
