#!/usr/bin/env bash
# O modo sem perguntas do /kit-vamoo:setup: `--sem-perguntas` liga, `--com-perguntas` desliga,
# e a escolha fica em ~/.claude/kit-vamoo/sem-perguntas de um setup para o outro.
#
# Regra `ask` pergunta em qualquer modo de permissão, bypass incluso. Quem trabalha em bypass
# de propósito e não quer ser parado no force push da própria branch não tinha como dispensar
# as do kit: o ask é união, e o setup roda de novo a cada versão marcada com `setup`. O
# test-merge-settings.sh prova a regra do merge sozinha; este roda o kit-setup.sh de ponta a
# ponta, com o template de verdade:
#   (a) setup comum: as regras ask de comando do kit entram e nenhum marcador é gravado;
#   (b) --sem-perguntas na mesma máquina: as de comando do kit saem, a que a pessoa escreveu
#       e a de conector ficam, o deny não muda, e a saída diz o que deixa de pedir confirmação
#       e o que continua barrado;
#   (c) o setup seguinte, sem opção, mantém o modo (é o caso da atualização);
#   (d) --com-perguntas devolve as regras e tira o marcador, e o setup seguinte fica assim;
#   (e) --dry-run não grava marcador nem mexe no settings; as duas opções juntas saem com 2.
#
# Uso: bash tests/test-kit-setup-sem-perguntas.sh [caminho-do-kit-setup.sh]
set -uo pipefail
SETUP="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/kit-setup.sh}"
[ -f "$SETUP" ] || { echo "script não encontrado: $SETUP"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "sem node — pulando"; exit 0; }

HOME_REAL="$HOME"
falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit-setup-sem-perguntas.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
igual() { # igual <descrição> <obtido> <esperado>
  if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado ${3:0:160}, veio ${2:0:160})"; fi
}

roda_setup() { # roda_setup <home> [args] — saída em <home>.log, devolve o exit
  local h="$1"; shift
  case "$h" in
    "$TMP"/*) ;;
    *) echo "GUARDA: HOME '$h' não está sob o temporário — abortando"; exit 2 ;;
  esac
  [ "$h/.claude" = "$HOME_REAL/.claude" ] && { echo "GUARDA: destino é o ~/.claude real — abortando"; exit 2; }
  HOME="$h" bash "$SETUP" "$@" >"$h.log" 2>&1
}
# O settings chega pelo stdin, aberto pelo bash: no Git Bash o node é nativo do Windows e não
# acha o /tmp/... passado por argumento.
conta() { # conta <home> <expressão JS sobre p = permissions> → imprime o resultado
  node -e "
const p = JSON.parse(require('fs').readFileSync(0, 'utf8')).permissions || {};
const cmd = (r) => /^(Bash|PowerShell)\\(/.test(r);
process.stdout.write(String($2));" < "$1/.claude/settings.json"
}
MARCA=".claude/kit-vamoo/sem-perguntas"
diz() { # diz <home> <texto fixo> <descrição>
  if grep -qF -- "$2" "$1.log"; then ok "$3"; else falha "$3 — a saída não tem: $2"; fi
}

echo "== (a) setup comum: as regras ask de comando do kit entram =="
A="$TMP/a"; mkdir -p "$A/.claude"
cat > "$A/.claude/settings.json" <<'JSON'
{ "permissions": { "defaultMode": "bypassPermissions",
    "ask": ["Bash(meu-deploy-perigoso *)", "mcp__meu-conector__enviar"],
    "deny": ["Bash(meu-deny:*)"] } }
JSON
roda_setup "$A" || falha "setup saiu com erro: $(tail -5 "$A.log")"
N_CMD="$(conta "$A" '(p.ask || []).filter(cmd).length')"
N_DENY="$(conta "$A" '(p.deny || []).length')"
DENY_A="$(conta "$A" 'JSON.stringify(p.deny)')"
[ "$N_CMD" -gt 100 ] && ok "o template traz as regras ask de comando ($N_CMD com a da pessoa)" \
  || falha "esperava mais de 100 regras ask de comando, veio $N_CMD"
[ ! -e "$A/$MARCA" ] && ok "sem a opção, nenhum marcador é gravado" || falha "o setup comum gravou o marcador"
grep -q 'sem perguntas' "$A.log" && falha "o setup comum fala do modo sem perguntas" || ok "o setup comum não fala do modo"

echo "== (b) --sem-perguntas: as de comando do kit saem, o resto fica =="
roda_setup "$A" --sem-perguntas || falha "setup --sem-perguntas saiu com erro: $(tail -5 "$A.log")"
igual "só a ask de comando da pessoa sobra" "$(conta "$A" 'JSON.stringify((p.ask || []).filter(cmd))')" '["Bash(meu-deploy-perigoso *)"]'
igual "a ask de conector da pessoa fica" "$(conta "$A" '(p.ask || []).includes("mcp__meu-conector__enviar")')" 'true'
igual "o deny não muda em nada" "$(conta "$A" 'JSON.stringify(p.deny)')" "$DENY_A"
igual "o modo de permissão da pessoa fica" "$(conta "$A" 'p.defaultMode')" 'bypassPermissions'
[ -f "$A/$MARCA" ] && ok "a escolha fica em ~/$MARCA" || falha "o marcador não foi gravado"
diz "$A" 'Modo sem perguntas LIGADO' "a saída diz que o modo está ligado"
for t in 'push --force' 'checkout -f' 'restore .' 'stash drop' 'supabase secrets set' 'migration repair' '.pem'; do
  diz "$A" "$t" "diz que deixa de pedir confirmação: $t"
done
for t in 'force push na main' 'db push' 'login' '.env'; do
  diz "$A" "$t" "diz o que continua barrado: $t"
done
diz "$A" '--com-perguntas' "ensina a desligar"

echo "== (c) o setup seguinte, sem opção, mantém o modo =="
roda_setup "$A" || falha "segundo setup saiu com erro: $(tail -5 "$A.log")"
igual "as regras de comando do kit não voltam" "$(conta "$A" '(p.ask || []).filter(cmd).length')" '1'
[ -f "$A/$MARCA" ] && ok "o marcador continua lá" || falha "o marcador sumiu no setup seguinte"
diz "$A" 'Modo sem perguntas LIGADO' "a saída lembra que o modo está ligado"
igual "o deny continua o mesmo" "$(conta "$A" '(p.deny || []).length')" "$N_DENY"

echo "== (d) --com-perguntas devolve as regras =="
roda_setup "$A" --com-perguntas || falha "setup --com-perguntas saiu com erro: $(tail -5 "$A.log")"
igual "as regras ask de comando do kit voltam, todas" "$(conta "$A" '(p.ask || []).filter(cmd).length')" "$N_CMD"
[ ! -e "$A/$MARCA" ] && ok "o marcador sai" || falha "o marcador ficou depois do --com-perguntas"
igual "o deny continua o mesmo" "$(conta "$A" 'JSON.stringify(p.deny)')" "$DENY_A"
roda_setup "$A"
igual "o setup seguinte fica com as perguntas" "$(conta "$A" '(p.ask || []).filter(cmd).length')" "$N_CMD"
grep -q 'Modo sem perguntas LIGADO' "$A.log" && falha "desligado, a saída ainda diz LIGADO" || ok "desligado, a saída não diz LIGADO"

echo "== (e) instalação nova, --dry-run e opções em conflito =="
B="$TMP/b"; mkdir -p "$B"
roda_setup "$B" --sem-perguntas || falha "setup --sem-perguntas em HOME vazio saiu com erro: $(tail -5 "$B.log")"
igual "instalação nova com --sem-perguntas: zero ask de comando" "$(conta "$B" '(p.ask || []).filter(cmd).length')" '0'
[ "$(conta "$B" '(p.deny || []).length')" -gt 100 ] && ok "…e o deny do kit chega inteiro" || falha "o deny do kit não chegou"

C="$TMP/c"; mkdir -p "$C/.claude"
echo '{ "permissions": { "ask": ["Bash(git stash drop *)"] } }' > "$C/.claude/settings.json"
cp "$C/.claude/settings.json" "$TMP/c-antes.json"
roda_setup "$C" --dry-run --sem-perguntas || falha "dry-run saiu com erro: $(tail -5 "$C.log")"
[ ! -e "$C/$MARCA" ] && ok "--dry-run não grava o marcador" || falha "--dry-run gravou o marcador"
cmp -s "$C/.claude/settings.json" "$TMP/c-antes.json" && ok "--dry-run não mexe no settings" || falha "--dry-run alterou o settings"
diz "$C" 'sem perguntas' "--dry-run mostra que ligaria o modo"

D="$TMP/d"; mkdir -p "$D"
roda_setup "$D" --sem-perguntas --com-perguntas; rc=$?
igual "--sem-perguntas com --com-perguntas sai com 2" "$rc" '2'
[ ! -e "$D/.claude" ] && ok "…sem tocar em nada" || falha "o conflito de opções criou ~/.claude"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
