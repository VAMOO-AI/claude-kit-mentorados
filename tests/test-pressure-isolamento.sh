#!/usr/bin/env bash
# O skill-pressure-test.sh isola os DOIS modos do ambiente da máquina?
#
# O `--baseline` sempre isolou (`--setting-sources ""`). O `--com-skill` não: ele
# herdava settings, CLAUDE.md, skills e hooks de quem estava rodando. Com ambientes
# diferentes nos dois lados, um "ok" no GREEN podia vir de outra skill instalada ou
# de uma regra do CLAUDE.md do usuário — não do texto da SKILL.md em teste, que é a
# única coisa que o script promete medir. E aqui isso pesa mais que no kit do time:
# quem roda pode ser um mentorado com uma máquina que ninguém revisou.
#
# Este teste troca o `claude` por um de mentira que anota os argumentos: o que se
# prova aqui é a linha de comando, não a resposta do modelo. Também fixa a ordem —
# `--tools` é variádico e engole o que vier depois, então ele tem que continuar
# sendo o último.
#
# E os dois modos rodam no modelo e no effort de produção (`opus`, `medium`). O
# isolamento tira o settings do usuário, e com ele o `effortLevel`; sem --model e
# --effort explícitos o teste mediria o default do CLI, não o modelo do dia a dia.
#
# E sem MCP: o `--setting-sources` não tira os conectores do claude.ai — no kit do
# time, um baseline "isolado" pediu para autorizar o do Supabase, que o cenário nem
# cita. O `--strict-mcp-config` tira.
#
# Uso: bash tests/test-pressure-isolamento.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT="$RAIZ/plugin/scripts/skill-pressure-test.sh"
SKILL_ALVO="$RAIZ/plugin/skills/ship/SKILL.md"
[ -f "$SCRIPT" ]     || { echo "script não encontrado: $SCRIPT"; exit 2; }
[ -f "$SKILL_ALVO" ] || { echo "skill ship não encontrada: $SKILL_ALVO"; exit 2; }

falhas=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$3', veio '$2')"; fi; }

# `claude` de mentira: guarda os argumentos, um por linha, e responde a letra certa.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'MOCK'
#!/bin/bash
cat >/dev/null
printf '%s\n' "$@" > "$ARGS_OUT"
echo "ESCOLHA: A"
MOCK
chmod +x "$TMP/bin/claude"

# O SKILLS_DIR daqui é fixo (plugin/skills ao lado do script), então o cenário
# aponta para uma skill que existe no plugin.
printf -- '---\nskill: ship\nesperado: A\n---\nDecida. ESCOLHA: <letra>\n' > "$TMP/cenario-01-fake.md"

# PRESSURE_MODEL/PRESSURE_EFFORT de quem roda o teste não podem vazar para o default:
# vazio vale como não definido, e PM/PE só entram quando o caso pede.
roda() { # <modo> [flags] → grava os argumentos em $TMP/args
  local modo="$1"; shift
  rm -f "$TMP/args"
  ARGS_OUT="$TMP/args" PATH="$TMP/bin:$PATH" \
    PRESSURE_MODEL="${PM:-}" PRESSURE_EFFORT="${PE:-}" \
    bash "$SCRIPT" "$modo" "$@" "$TMP/cenario-01-fake.md" >/dev/null 2>&1
}
valor_de() { awk -v f="$1" '$0==f{getline; print; exit}' "$TMP/args"; }
tem() { grep -qxF -- "$1" "$TMP/args" && echo sim || echo nao; }

echo "== --baseline continua sem nada da máquina =="
roda --baseline
check "passa --setting-sources"          "$(tem --setting-sources)" sim
check "com valor vazio"                  "$(valor_de --setting-sources)" ""
check "sem ferramenta nenhuma"           "$(valor_de --tools)" ""
check "não injeta SKILL.md no baseline"  "$(tem --append-system-prompt-file)" nao
check "sem MCP nem conector do claude.ai" "$(tem --strict-mcp-config)" sim
check "modelo de produção (opus)"        "$(valor_de --model)" opus
check "effort de produção (medium)"      "$(valor_de --effort)" medium
check "penúltimo argumento é --tools"    "$(tail -2 "$TMP/args" | head -1)" "--tools"

echo
echo "== --com-skill também isola: só a SKILL.md do plugin entra =="
roda --com-skill
check "passa --setting-sources"           "$(tem --setting-sources)" sim
check "valor é project,local"             "$(valor_de --setting-sources)" "project,local"
check "settings do usuário fora"          "$(grep -cxF 'user' "$TMP/args")" 0
check "injeta a SKILL.md do plugin"       "$(valor_de --append-system-prompt-file)" "$SKILL_ALVO"
check "só a ferramenta Skill ligada"      "$(valor_de --tools)" "Skill"
check "--setting-sources aparece uma vez" "$(grep -cxF -- '--setting-sources' "$TMP/args")" 1
check "sem MCP nem conector do claude.ai" "$(tem --strict-mcp-config)" sim
check "modelo de produção (opus)"         "$(valor_de --model)" opus
check "effort de produção (medium)"       "$(valor_de --effort)" medium

echo
echo "== --tools continua por último (é variádico e engole o resto) =="
check "penúltimo argumento é --tools"    "$(tail -2 "$TMP/args" | head -1)" "--tools"

echo
echo "== --model/--effort e PRESSURE_MODEL/PRESSURE_EFFORT trocam o padrão =="
roda --com-skill --model sonnet --effort high
check "--model chega ao claude"          "$(valor_de --model)" sonnet
check "--effort chega ao claude"         "$(valor_de --effort)" high
check "--effort aparece uma vez"         "$(grep -cxF -- '--effort' "$TMP/args")" 1
check "--tools continua por último"      "$(tail -2 "$TMP/args" | head -1)" "--tools"
PM=sonnet PE=high roda --baseline
check "PRESSURE_MODEL troca o padrão"    "$(valor_de --model)" sonnet
check "PRESSURE_EFFORT troca o padrão"   "$(valor_de --effort)" high

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
