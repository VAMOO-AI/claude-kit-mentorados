#!/usr/bin/env bash
# `collect.sh --diff <base>`: base que não resolve sai 3, e segredo em qualquer commit do
# range base..HEAD reprova, não só o que está no HEAD.
#
# O escopo do modo --diff sai de `git diff <base>...HEAD`, e até 28/09/2026 o erro do git ia
# para /dev/null: base com typo, `origin/HEAD` que o clone nunca criou ou fetch que não rodou
# davam escopo vazio, todo check "media" nada e o gate saía limpo, com exit 0 e 0 findings.
# Base que não resolve é "não mediu nada", o mesmo exit 3 que o script já usa para o resto.
# E o exit 3 não pode deixar o findings.json da passada anterior no --out: quem lê o --out
# depois o leria como se fosse desta.
#
# O range: a lista de arquivos vinha do diff, mas o conteúdo vinha do índice (.env) e do
# disco (JWT). `git rm --cached .env` sem --amend, commit novo tirando o .env e JWT
# consertado só no disco davam exit 0 — e o push levava o segredo no histórico.
#
# O untracked: o escopo saía só de `git diff`, que não vê arquivo fora do git. `.env` novo, JWT
# em arquivo novo e migration sem RLS passavam com exit 0, a um `git add -A` do commit. O que o
# .gitignore cobre continua fora: o seed ignora .env e .env.local.
#
# A fixture é um clone de verdade (origin/HEAD existe): `--diff origin/HEAD` é o jeito de
# comparar com a branch padrão sem saber o nome dela, e o teste prova esse comando nos dois
# sentidos, limpo e com segredo.
#
# Uso: bash tests/test-collect-diff-base.sh [caminho-do-collect.sh]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/baseline/scripts/collect.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente — o collect.sh depende dele"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/collect-diff.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

# --- fixture: origin com HEAD em main e um clone dele --------------------------
# -b main no bare: com init.defaultBranch=master o clone não ganharia origin/HEAD
git init -q --bare -b main "$TMP/origin.git"
SEED="$TMP/seed"; REPO="$TMP/repo"
git init -q -b main "$SEED"
git -C "$SEED" config user.email t@t; git -C "$SEED" config user.name t
git -C "$SEED" config commit.gpgsign false
printf '{"name":"fixture"}\n' > "$SEED/package.json"
mkdir -p "$SEED/src"; printf 'export const x = 1;\n' > "$SEED/src/a.ts"
printf '.env\n.env.local\n' > "$SEED/.gitignore"
git -C "$SEED" add package.json src/a.ts .gitignore
git -C "$SEED" commit -qm base
git -C "$SEED" push -q "$TMP/origin.git" main
git clone -q "$TMP/origin.git" "$REPO"
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" checkout -qb feat/x
git -C "$REPO" rev-parse --verify --quiet origin/HEAD >/dev/null \
  || { echo "fixture sem origin/HEAD — o teste não provaria o --diff origin/HEAD"; exit 2; }

# JWT falso montado aqui, para o próprio teste não carregar um literal que scanner acusa
JWT_FAKE="eyJ$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12).eyJ$(printf 'y%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)"

roda() { # roda <n> <base> — deixa EXIT, ERR e o diretório de saída em $TMP/out-<n>
  bash "$SCRIPT" --root "$REPO" --out "$TMP/out-$1" --diff "$2" >"$TMP/stdout-$1" 2>"$TMP/stderr-$1"
  EXIT=$?; ERR="$(cat "$TMP/stderr-$1")"
}
critico_07() { # critico_07 <n> — o findings.json da passada <n> tem CRITICAL do pilar 07?
  [ -f "$TMP/out-$1/findings.json" ] \
    && jq -e '[.findings[] | select(.pilar=="07" and .severity=="CRITICAL")] | length > 0' \
         "$TMP/out-$1/findings.json" >/dev/null 2>&1
}
segredo_untracked() { # segredo_untracked <n> — finding CRITICAL/HIGH do pilar 07 com "untracked" no título?
  [ -f "$TMP/out-$1/findings.json" ] \
    && jq -e '[.findings[] | select(.pilar=="07" and (.severity=="CRITICAL" or .severity=="HIGH")
                                    and (.title | test("untracked")))] | length > 0' \
         "$TMP/out-$1/findings.json" >/dev/null 2>&1
}
ramo() { # ramo <nome> — branch nova a partir de origin/HEAD, sem sobra do cenário anterior
  git -C "$REPO" checkout -q -- . 2>/dev/null
  git -C "$REPO" clean -qfdx   # untracked e ignorado: o .env do cenário anterior entraria no escopo
  git -C "$REPO" checkout -q -b "$1" origin/HEAD
}

echo "== base que não existe: exit 3, com a base no stderr e sem relatório =="
roda 1 origin/nao-existe
[ "$EXIT" -eq 3 ] && ok "--diff origin/nao-existe sai 3" || falha "--diff origin/nao-existe saiu $EXIT (esperado 3)"
printf '%s' "$ERR" | grep -qF 'origin/nao-existe' \
  && ok "stderr diz qual base não resolveu" || falha "stderr não cita a base: ${ERR:-<vazio>}"
[ ! -f "$TMP/out-1/findings.json" ] \
  && ok "não emite findings.json" || falha "emitiu findings.json sem ter base para medir"

echo "== --diff origin/HEAD num diff limpo: exit 0 =="
roda 2 origin/HEAD
[ "$EXIT" -eq 0 ] && ok "diff sem nada: exit 0" || falha "diff sem nada saiu $EXIT (esperado 0): $ERR"

echo "== --diff origin/HEAD com .env commitado depois da base: exit 1 =="
printf 'SEGREDO=1\n' > "$REPO/.env"
git -C "$REPO" add -f .env
git -C "$REPO" commit -qm "env por engano"
roda 3 origin/HEAD
[ "$EXIT" -eq 1 ] && ok ".env no diff: exit 1" || falha ".env no diff saiu $EXIT (esperado 1)"
critico_07 3 && ok "o finding é o .env versionado (pilar 07, CRITICAL)" \
  || falha "sem finding CRITICAL do pilar 07 para o .env"

echo "== exit 3 no mesmo --out: o findings.json da passada anterior não sobra =="
roda 3 origin/nao-existe
[ "$EXIT" -eq 3 ] && ok "base que não resolve, no --out de uma passada com finding: exit 3" \
  || falha "saiu $EXIT (esperado 3)"
[ ! -f "$TMP/out-3/findings.json" ] \
  && ok "o findings.json da passada anterior foi apagado" \
  || falha "o findings.json da passada anterior sobrou — quem lê o --out o tomaria por desta passada"

echo "== segredo em commit do range, fora do HEAD, do índice ou do disco: exit 1 =="
# 1) git rm --cached .env sem --amend: o commit continua com o .env, o índice não
ramo range-rm-cached
printf 'SEGREDO=1\n' > "$REPO/.env"
git -C "$REPO" add -f .env
git -C "$REPO" commit -qm "env por engano"
git -C "$REPO" rm -q --cached .env
roda 5 origin/HEAD
[ "$EXIT" -eq 1 ] && ok "git rm --cached sem --amend: exit 1" \
  || falha "git rm --cached sem --amend saiu $EXIT (esperado 1) — o commit com o .env sobe no push"
critico_07 5 && ok "o finding é do pilar 07, CRITICAL" || falha "sem finding CRITICAL do pilar 07"

# 2) commit novo por cima: um commit traz o .env, o seguinte o apaga
ramo range-por-cima
printf 'SEGREDO=1\n' > "$REPO/.env"
git -C "$REPO" add -f .env
git -C "$REPO" commit -qm "env por engano"
git -C "$REPO" rm -q .env
git -C "$REPO" commit -qm "tira o env"
roda 6 origin/HEAD
[ "$EXIT" -eq 1 ] && ok "commit novo tirando o .env: exit 1" \
  || falha "commit novo tirando o .env saiu $EXIT (esperado 1) — o primeiro commit sobe com ele"
critico_07 6 && ok "o finding é do pilar 07, CRITICAL" || falha "sem finding CRITICAL do pilar 07"

# 3) JWT consertado só no disco: o commit tem o token, o arquivo em disco não
ramo range-disco
printf 'export const k = "%s";\n' "$JWT_FAKE" > "$REPO/src/b.ts"
git -C "$REPO" add src/b.ts
git -C "$REPO" commit -qm "chave"
printf 'export const k = process.env.K;\n' > "$REPO/src/b.ts"
roda 7 origin/HEAD
[ "$EXIT" -eq 1 ] && ok "JWT consertado só no disco: exit 1" \
  || falha "JWT consertado só no disco saiu $EXIT (esperado 1) — o commit sobe com o token"
critico_07 7 && ok "o finding é do pilar 07, CRITICAL" || falha "sem finding CRITICAL do pilar 07"

# 4) .env que entra só na resolução de um merge: sem --diff-merges o `git log` não mostra
#    diff de commit de merge, e o commit seguinte (que tira o .env) é D — nada acusava
ramo range-merge-lado
printf 'lado\n' > "$REPO/lado.txt"
git -C "$REPO" add lado.txt
git -C "$REPO" commit -qm lado
ramo range-merge
printf 'meu\n' > "$REPO/meu.txt"
git -C "$REPO" add meu.txt
git -C "$REPO" commit -qm meu
git -C "$REPO" merge -q --no-ff --no-commit range-merge-lado >/dev/null 2>&1
printf 'SEGREDO=1\n' > "$REPO/.env"
git -C "$REPO" add -f .env
git -C "$REPO" commit -qm "merge com o .env na resolução"
git -C "$REPO" rm -q .env
git -C "$REPO" commit -qm "tira o env"
roda 8 origin/HEAD
[ "$EXIT" -eq 1 ] && ok ".env só na resolução do merge: exit 1" \
  || falha ".env só na resolução do merge saiu $EXIT (esperado 1) — o commit de merge sobe com ele"
critico_07 8 && ok "o finding é do pilar 07, CRITICAL" || falha "sem finding CRITICAL do pilar 07"

echo "== arquivo novo, untracked e fora do .gitignore: entra no escopo e reprova =="
ramo untracked-env
printf 'SEGREDO=1\n' > "$REPO/.env.production"
roda 11 origin/HEAD
[ "$EXIT" -eq 1 ] && ok ".env.production untracked: exit 1" \
  || falha ".env.production untracked saiu $EXIT (esperado 1) — o próximo git add -A o leva"
segredo_untracked 11 && ok "o finding do pilar 07 diz que é untracked" \
  || falha "sem finding CRITICAL/HIGH do pilar 07 com untracked no título"

ramo untracked-jwt
printf 'export const k = "%s";\n' "$JWT_FAKE" > "$REPO/src/novo.ts"
roda 12 origin/HEAD
[ "$EXIT" -eq 1 ] && ok "JWT em arquivo novo, untracked: exit 1" \
  || falha "JWT em arquivo novo, untracked, saiu $EXIT (esperado 1)"
segredo_untracked 12 && ok "o finding do pilar 07 diz que é untracked" \
  || falha "sem finding CRITICAL/HIGH do pilar 07 com untracked no título"

ramo untracked-migration
mkdir -p "$REPO/supabase/migrations"
printf 'create table public.pedidos (id int);\n' > "$REPO/supabase/migrations/20260928000000_pedidos.sql"
roda 13 origin/HEAD
[ "$EXIT" -eq 1 ] && ok "migration nova, untracked, sem RLS: exit 1" \
  || falha "migration nova, untracked, sem RLS saiu $EXIT (esperado 1)"
jq -e '[.findings[] | select(.pilar=="02" and .severity=="HIGH")] | length > 0' \
     "$TMP/out-13/findings.json" >/dev/null 2>&1 \
  && ok "o finding é a tabela sem RLS (pilar 02, HIGH)" || falha "sem finding HIGH do pilar 02"

ramo untracked-ignorado
printf 'SEGREDO=1\n' > "$REPO/.env"
printf 'K=%s\n' "$JWT_FAKE" > "$REPO/.env.local"
roda 14 origin/HEAD
[ "$EXIT" -eq 0 ] && ok "o que o .gitignore cobre fica fora: exit 0" \
  || falha "arquivo ignorado reprovou o gate: saiu $EXIT (esperado 0)"
git -C "$REPO" clean -qfdx

echo "== clone sem origin/HEAD: o mesmo comando sai 3 e diz como consertar =="
# o caso real: clone feito com init + remote add nunca ganha origin/HEAD — e o .env
# commitado em feat/x continua no diff, então exit 0 aqui seria um CRITICAL escondido
git -C "$REPO" checkout -q -- .
git -C "$REPO" checkout -q feat/x
git -C "$REPO" remote set-head origin -d
roda 4 origin/HEAD
[ "$EXIT" -eq 3 ] && ok "sem origin/HEAD: exit 3" || falha "sem origin/HEAD saiu $EXIT (esperado 3), com o .env no diff"
printf '%s' "$ERR" | grep -qF 'set-head' \
  && ok "stderr aponta o git remote set-head" || falha "stderr não diz como consertar: ${ERR:-<vazio>}"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
