#!/usr/bin/env bash
# O /kit-vamoo:setup inteiro, em HOME temporário, termina com o modo e o allow decididos
# em 18/10/2026 (0.56.0).
#
# O test-merge-settings.sh prova o merge sozinho. Este roda o kit-setup.sh de ponta a
# ponta, que é o que o mentorado executa: template + merge + avisos do CLAUDE.md.
#   (a) HOME vazio: defaultMode auto e nenhum dos allows de execução arbitrária;
#   (b) HOME de quem instalou até a 0.55.0: acceptEdits fica, com aviso do auto, os
#       allows que o kit gravou saem, o allow próprio fica, e o CLAUDE.md que ainda
#       manda pedir "init the context" ganha aviso sem ser editado;
#   (c) Manual com o marcador kit-vamoo/manter-modo-manual continua Manual.
#
# Uso: bash tests/test-kit-setup-permissoes.sh [caminho-do-kit-setup.sh]
set -uo pipefail
SETUP="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/kit-setup.sh}"
[ -f "$SETUP" ] || { echo "script não encontrado: $SETUP"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "sem node — pulando"; exit 0; }

HOME_REAL="$HOME"
falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit-setup-permissoes.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

roda_setup() { # roda_setup <home> — saída em <home>.log
  local h="$1"
  case "$h" in
    "$TMP"/*) ;;
    *) echo "GUARDA: HOME '$h' não está sob o temporário — abortando"; exit 2 ;;
  esac
  [ "$h/.claude" = "$HOME_REAL/.claude" ] && { echo "GUARDA: destino é o ~/.claude real — abortando"; exit 2; }
  HOME="$h" bash "$SETUP" >"$h.log" 2>&1
}

# O caminho do settings vai por argv: no Git Bash o node é nativo do Windows e não acha o
# /tmp/... escrito dentro do código (#220).
modo() { node -e 'const m=(require(process.argv[1]).permissions||{}).defaultMode; console.log(m===undefined?"(nenhum)":m)' "$1/.claude/settings.json"; }
tem_allow() { node -e 'process.exit(((require(process.argv[1]).permissions||{}).allow||[]).includes(process.argv[2]) ? 0 : 1)' "$1/.claude/settings.json" "$2"; }

LEGADOS=('Bash(awk:*)' 'Bash(npx tsx:*)' 'Bash(npm run:*)' 'PowerShell(npm run *)' 'PowerShell(npx tsx *)')

echo "== (a) HOME vazio =="
A="$TMP/a"; mkdir -p "$A"
roda_setup "$A" || falha "setup saiu com erro: $(tail -5 "$A.log")"
[ "$(modo "$A")" = auto ] && ok "defaultMode auto" || falha "defaultMode $(modo "$A"), esperado auto"
for r in "${LEGADOS[@]}"; do
  tem_allow "$A" "$r" && falha "instalação nova traz $r" || ok "instalação nova sem $r"
done
grep -q 'Sem Auto disponível' "$A.log" && ok "a saída diz o que acontece sem Auto" \
  || falha "a saída não explica o fallback para Manual"

echo "== (b) quem instalou até a 0.55.0 =="
B="$TMP/b"; mkdir -p "$B/.claude"
cat > "$B/.claude/settings.json" <<'JSON'
{ "permissions": { "defaultMode": "acceptEdits", "allow": ["Bash(ls:*)", "Bash(awk:*)", "Bash(npx tsx:*)", "Bash(npm run:*)", "PowerShell(npm run *)", "PowerShell(npx tsx *)", "Bash(npm run build)"] } }
JSON
printf '%s\n' '# Minhas regras' '## dotcontext (memória do projeto)' '- Em projeto novo, na 1ª sessão: peça **"init the context"**.' > "$B/.claude/CLAUDE.md"
CLAUDE_ANTES="$(cat "$B/.claude/CLAUDE.md")"
roda_setup "$B" || falha "setup saiu com erro: $(tail -5 "$B.log")"
[ "$(modo "$B")" = acceptEdits ] && ok "acceptEdits é mantido" || falha "modo virou $(modo "$B")"
grep -q 'recomenda "auto"' "$B.log" && ok "a saída recomenda o auto" || falha "a saída não recomenda o auto"
for r in "${LEGADOS[@]}"; do
  tem_allow "$B" "$r" && falha "$r sobreviveu ao setup" || ok "$r saiu"
done
tem_allow "$B" 'Bash(npm run build)' && ok "o allow exato da pessoa fica" || falha "o setup tirou Bash(npm run build)"
[ "$CLAUDE_ANTES" = "$(cat "$B/.claude/CLAUDE.md")" ] && ok "o CLAUDE.md da pessoa não foi editado" \
  || falha "o setup editou o CLAUDE.md da pessoa"
grep -q 'ainda manda usar o dotcontext' "$B.log" && ok "avisa que o CLAUDE.md ainda manda usar o dotcontext" \
  || falha "não avisou do \"init the context\" no CLAUDE.md"
grep -qiE 'init the context|dotcontext' "$B/.claude/CLAUDE.kit.md" \
  && falha "o CLAUDE.kit.md do kit ainda cita o dotcontext" || ok "o CLAUDE.kit.md não cita o dotcontext"

echo "== (c) Manual com o marcador =="
C="$TMP/c"; mkdir -p "$C/.claude/kit-vamoo"
echo '{ "permissions": { "defaultMode": "default" } }' > "$C/.claude/settings.json"
: > "$C/.claude/kit-vamoo/manter-modo-manual"
roda_setup "$C" || falha "setup saiu com erro: $(tail -5 "$C.log")"
[ "$(modo "$C")" = default ] && ok "o marcador segura o Manual" || falha "o marcador não segurou: $(modo "$C")"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; exit 0; fi
echo "$falhas falha(s)"; exit 1
