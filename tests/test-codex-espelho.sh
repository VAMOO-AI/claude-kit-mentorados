#!/usr/bin/env bash
# O plugin/scripts/codex-espelho.sh (SessionStart, F5 do núcleo único, #241).
#
# O Codex roda os guards de ~/.codex/hooks, que são CÓPIAS (nada aponta para o cache versionado
# do plugin). O espelho leva a versão do plugin para o guard que já está lá, nunca cria guard
# novo, leva o hookjson.js para ~/.codex/scripts e só trabalha quando a versão muda. E o guard
# espelhado barra no payload do Codex (comando em array e tool_input.workdir).
#
# Uso: bash tests/test-codex-espelho.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
ESP="$RAIZ/plugin/scripts/codex-espelho.sh"
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
X="$TMP/codex"; DADOS="$TMP/dados"; mkdir -p "$X/hooks"
printf '#!/bin/bash\n# versao antiga\nexit 0\n' > "$X/hooks/check-careful.sh"
printf '#!/bin/bash\n# versao antiga\nexit 0\n' > "$X/hooks/rtk-codex.sh"
roda() { HOME="$TMP/home" CODEX_HOME="$X" CLAUDE_PLUGIN_DATA="$DADOS" bash "$ESP" 2>&1; }

echo "== guard que já está lá é atualizado; o que não está não é criado =="
out=$(roda)
cmp -s "$RAIZ/plugin/hooks/check-careful.sh" "$X/hooks/check-careful.sh" && ok "check-careful = versão do plugin" || falha "check-careful não foi atualizado"
cmp -s "$RAIZ/plugin/hooks/rtk-codex.sh" "$X/hooks/rtk-codex.sh" && ok "rtk-codex = versão do plugin" || falha "rtk-codex não foi atualizado"
[ -x "$X/hooks/check-careful.sh" ] && ok "executável" || falha "sem +x"
[ -e "$X/hooks/block-main-commit.sh" ] && falha "criou guard que não estava lá" || ok "guard ausente não é criado"
cmp -s "$RAIZ/plugin/scripts/hookjson.js" "$X/scripts/hookjson.js" && ok "hookjson.js em ~/.codex/scripts" || falha "hookjson.js não foi copiado"
case "$out" in *"2 guard(s)"*) ok "avisa quantos atualizou" ;; *) falha "aviso: $out" ;; esac
VER=$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$RAIZ/plugin/.claude-plugin/plugin.json" | head -1)
[ "$(cat "$DADOS/codex-espelho.versao" 2>/dev/null)" = "$VER" ] && ok "versão espelhada gravada ($VER)" || falha "versão espelhada não gravada"

echo
echo "== mesma versão: não mexe e não fala =="
printf '#!/bin/bash\n# mexido na mão\nexit 0\n' > "$X/hooks/check-careful.sh"
out=$(roda)
[ -z "$out" ] && ok "silêncio" || falha "falou: $out"
grep -q 'mexido na mão' "$X/hooks/check-careful.sh" && ok "não reescreve com a versão já espelhada" || falha "reescreveu sem a versão mudar"

echo
echo "== versão nova: atualiza de novo =="
printf '0.0.1\n' > "$DADOS/codex-espelho.versao"
roda >/dev/null
cmp -s "$RAIZ/plugin/hooks/check-careful.sh" "$X/hooks/check-careful.sh" && ok "versão mudou: atualiza" || falha "não atualizou com a versão nova"

echo
echo "== o guard espelhado barra no payload do Codex =="
r=$(printf '%s' '{"tool_input":{"command":["/bin/zsh","-lc","git push --force origin main"],"workdir":"/tmp"},"permission_mode":"default"}' \
    | HOME="$TMP/home" bash "$X/hooks/check-careful.sh" 2>/dev/null)
case "$r" in *'"permissionDecision":"ask"'*) ok "push --force na main em array: ask" ;; *) falha "check-careful espelhado não perguntou: $r" ;; esac

echo
echo "== sem ~/.codex/hooks: nada =="
rm -rf "$X/hooks"; out=$(roda)
[ -z "$out" ] && [ ! -d "$X/hooks" ] && ok "sem pasta de hooks, não cria nada" || falha "mexeu sem ~/.codex/hooks"

echo
echo "== nenhum caminho com versão =="
grep -q 'codex-espelho.sh' "$RAIZ/plugin/hooks/hooks.json" && ok "registrado no SessionStart" || falha "fora do hooks.json"
grep -nE 'cache/[^"]*/[0-9]+\.[0-9]+\.[0-9]+' "$ESP" "$RAIZ/plugin/scripts/codex-optimize.sh" >/dev/null && falha "caminho com número de versão" || ok "nenhum caminho do cache versionado"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
