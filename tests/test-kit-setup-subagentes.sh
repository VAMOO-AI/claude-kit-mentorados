#!/usr/bin/env bash
# O kit-setup.sh troca o ~/.claude/agents.md antigo pelo subagentes.md sem apagar o
# AGENTS.md de ninguém (0.42.0).
#
# Até a 0.41.x o setup instalava ~/.claude/agents.md. Em disco que não diferencia
# maiúscula (o APFS padrão do Mac, o NTFS do Windows) esse arquivo responde por
# ~/.claude/AGENTS.md, que o Claude Code lê em toda sessão. O setup passou a instalar
# subagentes.md e tira o agents.md antigo, com backup.
#
# O risco mora no mesmo disco: `[ -e ~/.claude/agents.md ]`, `cp` e `rm` também acertam um
# AGENTS.md que a pessoa escreveu (o do Codex, por exemplo). O setup só remove o arquivo
# gravado com o nome exato `agents.md`, o que ele mesmo instalava. O caso (b) só existe em
# disco que não diferencia maiúscula (o Mac); o (d), em disco que diferencia (o ubuntu do
# CI). Porte do test-update-subagentes.sh do kit do time: lá quem diz o que o kit instalou
# é o manifesto; aqui o setup nunca registrou o agents.md, e o .keep-local faz o papel do
# caso (c).
#
# Uso: bash tests/test-kit-setup-subagentes.sh [caminho-do-kit-setup.sh]
set -uo pipefail
SETUP="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/kit-setup.sh}"
[ -f "$SETUP" ] || { echo "script não encontrado: $SETUP"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "sem node — pulando"; exit 0; }
TPL="$(cd "$(dirname "$SETUP")/.." && pwd)/templates"

HOME_REAL="$HOME"
falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit-setup-subagentes.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

# Nome como está gravado no disco. Sem diferença de maiúscula, `[ -e dir/AGENTS.md ]` é
# verdade também para um agents.md, então existência aqui nunca é `-e`/`-f`: o glob
# devolve a caixa gravada.
tem() { # tem <dir> <nome exato>
  local e
  for e in "$1"/* "$1"/.*; do [ "${e##*/}" = "$2" ] && return 0; done
  return 1
}

roda_setup() { # roda_setup <home> [args] — saída em <home>.log
  local h="$1"; shift
  case "$h" in
    "$TMP"/*) ;;
    *) echo "GUARDA: HOME '$h' não está sob o temporário — abortando"; exit 2 ;;
  esac
  [ "$h/.claude" = "$HOME_REAL/.claude" ] && { echo "GUARDA: destino é o ~/.claude real — abortando"; exit 2; }
  HOME="$h" bash "$SETUP" "$@" >"$h.log" 2>&1
}

conteudo() { cat "$1" 2>/dev/null; }

: > "$TMP/sonda"
if [ -e "$TMP/SONDA" ]; then
  SEM_CAIXA=1; echo "disco NÃO diferencia maiúscula: rodam (a), (b) e (c); o (d) só existe no ubuntu"
else
  SEM_CAIXA=0; echo "disco diferencia maiúscula: rodam (a), (c) e (d); o (b) só existe no Mac"
fi

echo "== (a) agents.md que o kit instalou sai, com backup, e o subagentes.md entra =="
A="$TMP/a"
mkdir -p "$A/.claude"
echo "regras antigas do kit" > "$A/.claude/agents.md"
roda_setup "$A"
if tem "$A/.claude" subagentes.md && cmp -s "$TPL/subagentes.md" "$A/.claude/subagentes.md"; then
  ok "subagentes.md instalado, igual ao do kit"
else falha "subagentes.md não foi instalado"; fi
if tem "$A/.claude" agents.md || tem "$A/.claude" AGENTS.md; then
  falha "o agents.md do kit continua em ~/.claude"
else ok "o agents.md do kit saiu de ~/.claude"; fi
bk="$(ls -d "$A/.claude"/backup-kit-* 2>/dev/null | head -1)"
if [ -n "$bk" ] && tem "$bk" agents.md && [ "$(conteudo "$bk/agents.md")" = "regras antigas do kit" ]; then
  ok "o agents.md removido está no backup"
else falha "o agents.md removido não está no backup"; fi
grep -q "agents.md antigo removido" "$A.log" \
  && ok "o setup diz que tirou o agents.md" || falha "o setup tirou o agents.md calado (ou não tirou)"
roda_setup "$A"
grep -qi "agents.md" "$A.log" \
  && falha "a 2ª execução ainda mexe no agents.md" || ok "a 2ª execução não mexe mais no agents.md"

if [ "$SEM_CAIXA" = 1 ]; then
  echo "== (b) AGENTS.md que a pessoa escreveu fica =="
  B="$TMP/b"
  mkdir -p "$B/.claude"
  echo "minhas regras" > "$B/.claude/AGENTS.md"
  roda_setup "$B" --dry-run
  grep -q 'dry-run.*rm .*agents\.md' "$B.log" \
    && falha "o dry-run anuncia a remoção do AGENTS.md alheio" || ok "o dry-run não anuncia remoção nenhuma"
  roda_setup "$B"
  if tem "$B/.claude" AGENTS.md && [ "$(conteudo "$B/.claude/AGENTS.md")" = "minhas regras" ]; then
    ok "o AGENTS.md alheio continua lá, com o mesmo conteúdo"
  else falha "o AGENTS.md alheio foi apagado ou sobrescrito"; fi
  grep -q "AGENTS.md" "$B.log" && grep -q "não foi instalado pelo kit" "$B.log" \
    && ok "o setup avisa que deixou o AGENTS.md, que não é dele" || falha "o setup não disse nada sobre o AGENTS.md"
  grep -q "agents.md antigo removido" "$B.log" \
    && falha "o setup diz que removeu o agents.md" || ok "o setup não diz que removeu nada"
fi

echo "== (c) agents.md listado no .keep-local fica como está =="
C="$TMP/c"
mkdir -p "$C/.claude"
echo "cópia minha" > "$C/.claude/agents.md"
printf 'agents.md\n' > "$C/.claude/.keep-local"
roda_setup "$C"
if tem "$C/.claude" agents.md && [ "$(conteudo "$C/.claude/agents.md")" = "cópia minha" ]; then
  ok "o agents.md protegido pelo .keep-local não é tocado"
else falha "o agents.md do .keep-local foi apagado ou sobrescrito"; fi

if [ "$SEM_CAIXA" = 0 ]; then
  echo "== (d) agents.md e AGENTS.md lado a lado: só o do kit sai =="
  D="$TMP/d"
  mkdir -p "$D/.claude"
  echo "regras antigas do kit" > "$D/.claude/agents.md"
  echo "minhas regras" > "$D/.claude/AGENTS.md"
  roda_setup "$D"
  tem "$D/.claude" agents.md && falha "o agents.md do kit continua lá" || ok "o agents.md do kit saiu"
  if tem "$D/.claude" AGENTS.md && [ "$(conteudo "$D/.claude/AGENTS.md")" = "minhas regras" ]; then
    ok "o AGENTS.md alheio ficou intacto"
  else falha "o AGENTS.md alheio foi apagado ou sobrescrito"; fi
fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; fi
exit "$falhas"
