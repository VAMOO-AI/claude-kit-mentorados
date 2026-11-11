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
#   (b) --sem-perguntas na mesma máquina: o modo de permissão vira bypassPermissions, as regras
#       de comando do kit saem, a que a pessoa escreveu e a de conector ficam, o deny não muda,
#       e a saída diz o que deixa de pedir confirmação, o que ainda pergunta, o que continua
#       barrado e o que falta fazer no app de desktop;
#   (c) o setup seguinte, sem opção, mantém o modo (é o caso da atualização);
#   (d) --com-perguntas devolve as regras e o modo de antes e tira o marcador;
#   (e) --dry-run não grava marcador nem mexe no settings; as duas opções juntas saem com 2;
#   (f) quem troca o modo na mão depois de ligar não é forçado de volta num setup comum;
#   (g) marcador da 0.93.0 (sem a linha modo=bypass) migra para o bypass uma vez;
#   (h) quem já estava em bypass continua nele depois do --com-perguntas;
#   (i) o marcador manter-modo-manual segura o modo.
#
# Até a 0.93.0 o modo só tirava as regras ask e deixava o modo de permissão como estava. Quem
# estava no Auto (ou no Manual, sem Auto na conta) seguia vendo "Permitir" em `gh pr merge`.
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
topo() { # topo <home> <expressão JS sobre s = settings inteiro> → imprime o resultado
  node -e "
const s = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(String($2));" < "$1/.claude/settings.json"
}
poe_modo() { # poe_modo <home> <modo>: a pessoa troca o defaultMode na mão
  MODO_NOVO="$2" node -e "
const s = JSON.parse(require('fs').readFileSync(0, 'utf8'));
s.permissions = s.permissions || {}; s.permissions.defaultMode = process.env.MODO_NOVO;
process.stdout.write(JSON.stringify(s, null, 2) + '\n');" < "$1/.claude/settings.json" > "$1/.claude/settings.novo.json"
  mv "$1/.claude/settings.novo.json" "$1/.claude/settings.json"
}
MARCA=".claude/kit-vamoo/sem-perguntas"
marca_tem() { # marca_tem <home> <linha exata> <descrição>
  if grep -qxF -- "$2" "$1/$MARCA" 2>/dev/null; then ok "$3"
  else falha "$3 — o marcador não tem a linha: $2 (tem: $(tr '\n' ';' < "$1/$MARCA" 2>/dev/null))"; fi
}
diz() { # diz <home> <texto fixo> <descrição>
  if grep -qF -- "$2" "$1.log"; then ok "$3"; else falha "$3 — a saída não tem: $2"; fi
}

echo "== (a) setup comum: as regras ask de comando do kit entram =="
A="$TMP/a"; mkdir -p "$A/.claude"
cat > "$A/.claude/settings.json" <<'JSON'
{ "permissions": { "defaultMode": "auto",
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
igual "o modo de permissão vira bypassPermissions" "$(conta "$A" 'p.defaultMode')" 'bypassPermissions'
igual "o aviso do modo perigoso da CLI fica dispensado" "$(topo "$A" 's.skipDangerousModePermissionPrompt')" 'true'
[ -f "$A/$MARCA" ] && ok "a escolha fica em ~/$MARCA" || falha "o marcador não foi gravado"
marca_tem "$A" 'modo=bypass' "o marcador registra que o bypass é do modo"
marca_tem "$A" 'modo_anterior=auto' "o marcador guarda o modo de antes"
marca_tem "$A" 'skip_do_kit=1' "o marcador registra que o skip foi posto pelo kit"
diz "$A" 'Modo sem perguntas LIGADO' "a saída diz que o modo está ligado"
for t in 'bypassPermissions' 'Ignorar permissões' 'Allow bypass permissions mode' 'seletor'; do
  diz "$A" "$t" "diz o que falta no app de desktop: $t"
done
for t in 'fora do projeto' 'DROP' 'db reset' 'gh repo delete'; do
  diz "$A" "$t" "diz o que ainda pergunta: $t"
done
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
igual "o modo continua bypassPermissions" "$(conta "$A" 'p.defaultMode')" 'bypassPermissions'
marca_tem "$A" 'modo_anterior=auto' "o modo de antes continua guardado"
[ -f "$A/$MARCA" ] && ok "o marcador continua lá" || falha "o marcador sumiu no setup seguinte"
diz "$A" 'Modo sem perguntas LIGADO' "a saída lembra que o modo está ligado"
igual "o deny continua o mesmo" "$(conta "$A" '(p.deny || []).length')" "$N_DENY"

echo "== (d) --com-perguntas devolve as regras =="
roda_setup "$A" --com-perguntas || falha "setup --com-perguntas saiu com erro: $(tail -5 "$A.log")"
igual "as regras ask de comando do kit voltam, todas" "$(conta "$A" '(p.ask || []).filter(cmd).length')" "$N_CMD"
[ ! -e "$A/$MARCA" ] && ok "o marcador sai" || falha "o marcador ficou depois do --com-perguntas"
igual "o modo de permissão volta ao de antes" "$(conta "$A" 'p.defaultMode')" 'auto'
igual "o skip que o kit pôs sai" "$(topo "$A" 's.skipDangerousModePermissionPrompt === undefined')" 'true'
igual "o deny continua o mesmo" "$(conta "$A" 'JSON.stringify(p.deny)')" "$DENY_A"
roda_setup "$A"
igual "o setup seguinte fica com as perguntas" "$(conta "$A" '(p.ask || []).filter(cmd).length')" "$N_CMD"
grep -q 'Modo sem perguntas LIGADO' "$A.log" && falha "desligado, a saída ainda diz LIGADO" || ok "desligado, a saída não diz LIGADO"

echo "== (e) instalação nova, --dry-run e opções em conflito =="
B="$TMP/b"; mkdir -p "$B"
roda_setup "$B" --sem-perguntas || falha "setup --sem-perguntas em HOME vazio saiu com erro: $(tail -5 "$B.log")"
igual "instalação nova com --sem-perguntas: zero ask de comando" "$(conta "$B" '(p.ask || []).filter(cmd).length')" '0'
[ "$(conta "$B" '(p.deny || []).length')" -gt 100 ] && ok "…e o deny do kit chega inteiro" || falha "o deny do kit não chegou"
igual "instalação nova com --sem-perguntas: bypassPermissions" "$(conta "$B" 'p.defaultMode')" 'bypassPermissions'

C="$TMP/c"; mkdir -p "$C/.claude"
echo '{ "permissions": { "ask": ["Bash(git stash drop *)"] } }' > "$C/.claude/settings.json"
cp "$C/.claude/settings.json" "$TMP/c-antes.json"
roda_setup "$C" --dry-run --sem-perguntas || falha "dry-run saiu com erro: $(tail -5 "$C.log")"
[ ! -e "$C/$MARCA" ] && ok "--dry-run não grava o marcador" || falha "--dry-run gravou o marcador"
cmp -s "$C/.claude/settings.json" "$TMP/c-antes.json" && ok "--dry-run não mexe no settings" || falha "--dry-run alterou o settings"
diz "$C" 'sem perguntas' "--dry-run mostra que ligaria o modo"
diz "$C" 'bypassPermissions' "--dry-run diz que poria o bypass"

D="$TMP/d"; mkdir -p "$D"
roda_setup "$D" --sem-perguntas --com-perguntas; rc=$?
igual "--sem-perguntas com --com-perguntas sai com 2" "$rc" '2'
[ ! -e "$D/.claude" ] && ok "…sem tocar em nada" || falha "o conflito de opções criou ~/.claude"

echo "== (f) quem troca o modo na mão não é forçado de volta num setup comum =="
roda_setup "$B" || falha "setup comum em B saiu com erro: $(tail -5 "$B.log")"
igual "setup comum mantém o bypass" "$(conta "$B" 'p.defaultMode')" 'bypassPermissions'
poe_modo "$B" auto
roda_setup "$B" || falha "setup depois da troca manual saiu com erro: $(tail -5 "$B.log")"
igual "auto escolhido na mão fica no setup comum" "$(conta "$B" 'p.defaultMode')" 'auto'
igual "…e as regras ask de comando seguem fora" "$(conta "$B" '(p.ask || []).filter(cmd).length')" '0'
roda_setup "$B" --sem-perguntas || falha "segundo --sem-perguntas saiu com erro: $(tail -5 "$B.log")"
igual "pedir --sem-perguntas de novo põe o bypass de volta" "$(conta "$B" 'p.defaultMode')" 'bypassPermissions'
marca_tem "$B" 'modo_anterior=auto' "o modo de antes passa a ser o último escolhido"
roda_setup "$B" --com-perguntas || falha "--com-perguntas em B saiu com erro: $(tail -5 "$B.log")"
igual "--com-perguntas volta para o auto" "$(conta "$B" 'p.defaultMode')" 'auto'

echo "== (g) marcador da 0.93.0 migra para o bypass uma vez =="
G="$TMP/g"; mkdir -p "$G/.claude/kit-vamoo"
echo '{ "permissions": { "defaultMode": "auto" } }' > "$G/.claude/settings.json"
printf 'ligado em 20261110-100000 pelo kit-setup.sh --sem-perguntas\n' > "$G/$MARCA"
roda_setup "$G" || falha "setup com o marcador antigo saiu com erro: $(tail -5 "$G.log")"
igual "marcador antigo + setup comum: bypassPermissions" "$(conta "$G" 'p.defaultMode')" 'bypassPermissions'
marca_tem "$G" 'modo=bypass' "o marcador ganha a linha modo=bypass"
marca_tem "$G" 'modo_anterior=auto' "…e guarda o modo de antes"
poe_modo "$G" plan
roda_setup "$G" || falha "setup depois da migração saiu com erro: $(tail -5 "$G.log")"
igual "depois de migrar, o modo escolhido na mão fica" "$(conta "$G" 'p.defaultMode')" 'plan'

echo "== (h) quem já estava em bypass continua nele =="
H="$TMP/h"; mkdir -p "$H/.claude"
echo '{ "skipDangerousModePermissionPrompt": true, "permissions": { "defaultMode": "bypassPermissions" } }' > "$H/.claude/settings.json"
roda_setup "$H" --sem-perguntas || falha "--sem-perguntas em H saiu com erro: $(tail -5 "$H.log")"
roda_setup "$H" --com-perguntas || falha "--com-perguntas em H saiu com erro: $(tail -5 "$H.log")"
igual "bypass que já era da pessoa fica depois do --com-perguntas" "$(conta "$H" 'p.defaultMode')" 'bypassPermissions'
igual "…e o skip dela também" "$(topo "$H" 's.skipDangerousModePermissionPrompt')" 'true'

echo "== (i) manter-modo-manual segura o modo =="
I="$TMP/i"; mkdir -p "$I/.claude/kit-vamoo"
echo '{ "permissions": { "defaultMode": "default" } }' > "$I/.claude/settings.json"
: > "$I/.claude/kit-vamoo/manter-modo-manual"
roda_setup "$I" --sem-perguntas || falha "--sem-perguntas em I saiu com erro: $(tail -5 "$I.log")"
igual "com o manter-modo-manual o Manual fica" "$(conta "$I" 'p.defaultMode')" 'default'
igual "…mas as regras ask de comando saem" "$(conta "$I" '(p.ask || []).filter(cmd).length')" '0'
diz "$I" 'manter-modo-manual' "a saída diz que o marcador segurou o modo"
diz "$I" 'não em bypass' "a saída diz que o modo não está em bypass"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
