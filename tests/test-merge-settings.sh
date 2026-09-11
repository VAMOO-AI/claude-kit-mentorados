#!/usr/bin/env bash
# Prova de regressão do plugin/scripts/merge-settings.js.
#
# O merge existe porque o instalador antigo sobrescrevia o settings.json e quem
# tinha permissões próprias perdia tudo. A partir daí ele virou "as suas chaves
# ganham" — mas até 0.8.0 só `permissions.allow` era mesclado: `deny` e `ask`
# ficavam de fora, então quem JÁ tinha o kit instalado nunca recebia barreira
# nova, só permissão nova. Perder um deny é abrir buraco de segurança, e o
# instalador não avisava.
#
# Uso: bash tests/test-merge-settings.sh [caminho-do-merge.js]
#   Sem argumento testa o script do repo. Passe a versão anterior para ver os
#   casos falharem (é o que prova que o teste testa alguma coisa).
set -uo pipefail
MERGE="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/merge-settings.js}"
[ -f "$MERGE" ] || { echo "não achei o merge: $MERGE"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "sem node — pulando"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
falhas=0

cat > "$TMP/kit.json" <<'JSON'
{
  "language": "portuguese",
  "theme": "dark",
  "extraKnownMarketplaces": {
    "vamoo-ai": {
      "source": { "source": "github", "repo": "VAMOO-AI/claude-kit-mentorados" },
      "autoUpdate": true
    }
  },
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": ["Bash(ls:*)", "Bash(npm run:*)", "Bash(git status:*)"],
    "deny": ["Read(**/.env)", "Bash(vercel login:*)"]
  }
}
JSON

# Como fica a máquina de quem instalou o kit meses atrás: modo antigo, poucas
# permissões, nenhum deny, e uma preferência própria que não pode sumir.
#
# O `extraKnownMarketplaces` aqui não é invenção do teste: é o que o próprio
# `/plugin marketplace add` escreve no settings.json de quem instalou. Ele é a
# razão de o merge não poder ser tudo-ou-nada nessa chave — a chave JÁ existe,
# então "o seu ganha" significava que o autoUpdate do kit nunca chegava.
cat > "$TMP/meu.json" <<'JSON'
{
  "theme": "light",
  "statusLine": { "type": "command", "command": "meu-script.sh" },
  "extraKnownMarketplaces": {
    "vamoo-ai": {
      "source": { "source": "directory", "path": "/Users/eu/dev/claude-kit-mentorados" }
    },
    "marketplace-do-meu-time": {
      "source": { "source": "github", "repo": "meu-time/plugins" }
    }
  },
  "permissions": {
    "defaultMode": "default",
    "allow": ["Bash(ls:*)", "Bash(meu-script:*)"]
  }
}
JSON

SAIDA="$(node "$MERGE" "$TMP/kit.json" "$TMP/meu.json" 2>&1)"

check() { # check <descrição> <filtro jq> <esperado>
  local got; got="$(python3 -c "
import json,sys
d=json.load(open('$TMP/meu.json',encoding='utf-8'))
print(json.dumps($2, ensure_ascii=False))
" 2>/dev/null)"
  if [ "$got" = "$3" ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$1" "$3" "$got"; falhas=$((falhas+1)); fi
}

echo "== o que o kit precisa entregar =="
check "deny do kit chega em quem já tinha o kit" \
  "len(d['permissions'].get('deny') or [])" "2"
check "allow vira união, sem duplicar o que já havia" \
  "len(d['permissions']['allow'])" "4"
check "chave nova do kit é preenchida" "d.get('language')" '"portuguese"'

echo "== o que é seu e não pode ser tocado =="
check "tema que você escolheu continua o seu" "d['theme']" '"light"'
check "statusLine própria sobrevive" "d['statusLine']['command']" '"meu-script.sh"'
check "sua permissão própria continua na lista" \
  "'Bash(meu-script:*)' in d['permissions']['allow']" "true"
check "seu modo de permissão NÃO é trocado pelo do kit" \
  "d['permissions']['defaultMode']" '"default"'

echo "== o kit precisa se manter atualizado sozinho =="
check "auto-update do kit é ligado em quem já tinha o marketplace" \
  "d['extraKnownMarketplaces']['vamoo-ai'].get('autoUpdate')" "true"
check "a fonte que você já tinha NÃO é trocada pela do kit" \
  "d['extraKnownMarketplaces']['vamoo-ai']['source']['source']" '"directory"'
check "marketplace de outro time continua no arquivo" \
  "'marketplace-do-meu-time' in d['extraKnownMarketplaces']" "true"
printf '%s' "$SAIDA" | grep -q 'extraKnownMarketplaces.vamoo-ai.autoUpdate' \
  && echo "  ok    a saída nomeia o auto-update que ligou" \
  || { echo "  FALHA a saída não nomeia o auto-update: $SAIDA"; falhas=$((falhas+1)); }

echo "== quem desligou o auto-update de propósito não é religado =="
cat > "$TMP/desligado.json" <<'JSON'
{
  "extraKnownMarketplaces": {
    "vamoo-ai": {
      "source": { "source": "github", "repo": "VAMOO-AI/claude-kit-mentorados" },
      "autoUpdate": false
    }
  }
}
JSON
SAIDA_OFF="$(node "$MERGE" "$TMP/kit.json" "$TMP/desligado.json" 2>&1)"
python3 -c "
import json,sys
d=json.load(open('$TMP/desligado.json',encoding='utf-8'))
sys.exit(0 if d['extraKnownMarketplaces']['vamoo-ai']['autoUpdate'] is False else 1)
" 2>/dev/null \
  && echo "  ok    autoUpdate:false continua false" \
  || { echo "  FALHA o kit religou um auto-update que a pessoa desligou"; falhas=$((falhas+1)); }
printf '%s' "$SAIDA_OFF" | grep -qi 'auto-update' \
  && echo "  ok    avisa que manteve a escolha da pessoa" \
  || { echo "  FALHA não avisou sobre o auto-update desligado: $SAIDA_OFF"; falhas=$((falhas+1)); }

echo "== quem nunca teve marketplace nenhum ganha o bloco inteiro =="
echo '{}' > "$TMP/zerado.json"
node "$MERGE" "$TMP/kit.json" "$TMP/zerado.json" >/dev/null 2>&1
python3 -c "
import json,sys
d=json.load(open('$TMP/zerado.json',encoding='utf-8'))
m=d.get('extraKnownMarketplaces',{}).get('vamoo-ai',{})
sys.exit(0 if m.get('autoUpdate') is True and m.get('source',{}).get('repo')=='VAMOO-AI/claude-kit-mentorados' else 1)
" 2>/dev/null \
  && echo "  ok    fonte e auto-update chegam juntos" \
  || { echo "  FALHA settings zerado não recebeu o marketplace do kit"; falhas=$((falhas+1)); }

echo "== o instalador precisa dizer o que fez =="
printf '%s' "$SAIDA" | grep -q 'permissions.deny (+2)' \
  && echo "  ok    a saída nomeia as barreiras acrescentadas" \
  || { echo "  FALHA a saída não nomeia o deny acrescentado: $SAIDA"; falhas=$((falhas+1)); }
printf '%s' "$SAIDA" | grep -q 'recomenda "acceptEdits"' \
  && echo "  ok    avisa que seu modo difere do recomendado, sem trocar" \
  || { echo "  FALHA não avisou sobre o modo divergente: $SAIDA"; falhas=$((falhas+1)); }

echo "== rodar duas vezes não pode mudar nada =="
ANTES="$(cat "$TMP/meu.json")"
node "$MERGE" "$TMP/kit.json" "$TMP/meu.json" >/dev/null 2>&1
[ "$ANTES" = "$(cat "$TMP/meu.json")" ] \
  && echo "  ok    idempotente" \
  || { echo "  FALHA a segunda passada mudou o arquivo"; falhas=$((falhas+1)); }

echo "== settings.json quebrado não pode ser sobrescrito =="
echo '{ isso não é json' > "$TMP/ruim.json"
node "$MERGE" "$TMP/kit.json" "$TMP/ruim.json" >/dev/null 2>&1
grep -q 'isso não é json' "$TMP/ruim.json" \
  && echo "  ok    arquivo inválido fica intacto" \
  || { echo "  FALHA o arquivo inválido foi sobrescrito"; falhas=$((falhas+1)); }

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
