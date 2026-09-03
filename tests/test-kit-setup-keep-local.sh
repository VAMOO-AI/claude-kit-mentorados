#!/usr/bin/env bash
# Prova de regressão do .keep-local e da rotação de backups do plugin/scripts/kit-setup.sh.
#
# A remoção de "fantasmas" lê o ~/.claude/.kit-manifest da instalação antiga e apaga
# o que está listado — inclusive a skill que a pessoa editou e o script que ela
# escreveu com um nome que o manifesto também tinha. Até 0.18.0 não havia como
# dizer "isso aqui é meu, deixa". Agora há: ~/.claude/.keep-local, um caminho por
# linha, relativo a ~/.claude, `#` comenta, glob simples. E cada execução criava um
# backup-kit-<data> sem nunca apagar nenhum; agora ficam os 3 mais recentes.
#
# O que precisa continuar valendo: fantasma sem .keep-local sai (com backup); com
# .keep-local fica; o glob funciona; o .keep-local NÃO impede o kit de instalar o
# que é dele; e 5 execuções deixam exatamente 3 backups — os 3 mais novos.
#
# Uso: bash tests/test-kit-setup-keep-local.sh [caminho-do-kit-setup.sh]
set -uo pipefail
SETUP="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/kit-setup.sh}"
[ -f "$SETUP" ] || { echo "script não encontrado: $SETUP"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "sem node — pulando"; exit 0; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit-setup-keep.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
existe() { [ -e "$1" ] && echo ok || echo fail; }
sumiu()  { [ ! -e "$1" ] && echo ok || echo fail; }
n_backups() { local n=0 d; for d in "$1"/.claude/backup-kit-*/; do [ -d "$d" ] && n=$((n+1)); done; echo "$n"; }

# Uma instalação antiga: skills, hook, comando e script listados no manifesto, e
# uma skill própria que o manifesto nunca conheceu.
monta_home() { # monta_home <dir>
  local h="$1/.claude"
  mkdir -p "$h/skills/skill-do-kit" "$h/skills/minha-skill" "$h/skills/meu-projeto-a" \
           "$h/skills/meu-projeto-b" "$h/skills/so-minha" "$h/hooks" "$h/commands" "$h/scripts"
  echo "do kit" > "$h/skills/skill-do-kit/SKILL.md"
  echo "editei" > "$h/skills/minha-skill/SKILL.md"
  echo "a" > "$h/skills/meu-projeto-a/SKILL.md"
  echo "b" > "$h/skills/meu-projeto-b/SKILL.md"
  echo "nunca no manifesto" > "$h/skills/so-minha/SKILL.md"
  echo "hook velho" > "$h/hooks/hook-velho.sh"
  echo "cmd velho" > "$h/commands/cmd-velho.md"
  echo "meu script" > "$h/scripts/meu-script.sh"
  printf '%s\n' skill/skill-do-kit skill/minha-skill skill/meu-projeto-a skill/meu-projeto-b \
                hook/hook-velho.sh command/cmd-velho.md script/meu-script.sh > "$h/.kit-manifest"
}

echo "== sem .keep-local: tudo que o manifesto lista sai, com backup =="
H1="$TMP/h1"; monta_home "$H1"
HOME="$H1" bash "$SETUP" >"$TMP/saida1" 2>&1; codigo=$?
check "setup termina com exit 0"                        "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "skill do manifesto removida"                     "$(sumiu "$H1/.claude/skills/skill-do-kit")"
check "skill editada também sai (não tinha proteção)"   "$(sumiu "$H1/.claude/skills/minha-skill")"
check "hook e comando do manifesto removidos"           "$([ ! -e "$H1/.claude/hooks/hook-velho.sh" ] && [ ! -e "$H1/.claude/commands/cmd-velho.md" ] && echo ok || echo fail)"
check "script do manifesto removido"                    "$(sumiu "$H1/.claude/scripts/meu-script.sh")"
check "skill fora do manifesto nunca é tocada"          "$(existe "$H1/.claude/skills/so-minha/SKILL.md")"
check "o que saiu está no backup"                       "$([ "$(cat "$H1"/.claude/backup-kit-*/skills/minha-skill/SKILL.md 2>/dev/null)" = "editei" ] && echo ok || echo fail)"
check "manifesto apagado (a limpeza rodou)"             "$(sumiu "$H1/.claude/.kit-manifest")"

echo "== com .keep-local: o que está lá fica, o resto sai =="
H2="$TMP/h2"; monta_home "$H2"
cat > "$H2/.claude/.keep-local" <<'EOF'
# o que é meu e o kit não remove
skills/minha-skill        # editei essa
skills/meu-projeto-*
  scripts/meu-script.sh
./hooks/                  # a pasta inteira
EOF
HOME="$H2" bash "$SETUP" >"$TMP/saida2" 2>&1; codigo=$?
check "setup termina com exit 0"                        "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "caminho exato protegido fica"                    "$(existe "$H2/.claude/skills/minha-skill/SKILL.md")"
check "glob protege as duas skills meu-projeto-*"       "$([ -e "$H2/.claude/skills/meu-projeto-a/SKILL.md" ] && [ -e "$H2/.claude/skills/meu-projeto-b/SKILL.md" ] && echo ok || echo fail)"
check "linha com espaço na frente vale"                 "$(existe "$H2/.claude/scripts/meu-script.sh")"
check "pasta listada protege o que está dentro"         "$(existe "$H2/.claude/hooks/hook-velho.sh")"
check "o que NÃO está no .keep-local sai"               "$([ ! -e "$H2/.claude/skills/skill-do-kit" ] && [ ! -e "$H2/.claude/commands/cmd-velho.md" ] && echo ok || echo fail)"
check "conteúdo protegido intacto"                      "$([ "$(cat "$H2/.claude/skills/minha-skill/SKILL.md")" = "editei" ] && echo ok || echo fail)"
check "saída nomeia o que foi mantido"                  "$(grep -q 'keep-local' "$TMP/saida2" && echo ok || echo fail)"
check "protegido não vai pro backup (não saiu)"         "$([ ! -e "$H2"/.claude/backup-kit-*/skills/minha-skill ] && echo ok || echo fail)"

echo "== .keep-local protege contra remoção, não contra instalação =="
H3="$TMP/h3"; mkdir -p "$H3/.claude"
echo "agents antigo" > "$H3/.claude/agents.md"
printf 'agents.md\n' > "$H3/.claude/.keep-local"
HOME="$H3" bash "$SETUP" >/dev/null 2>&1
check "agents.md do kit é instalado por cima mesmo listado" "$([ "$(cat "$H3/.claude/agents.md")" != "agents antigo" ] && echo ok || echo fail)"
check "a versão antiga foi pro backup"                  "$([ "$(cat "$H3"/.claude/backup-kit-*/agents.md 2>/dev/null)" = "agents antigo" ] && echo ok || echo fail)"

echo "== --dry-run não remove nem cria backup =="
H4="$TMP/h4"; monta_home "$H4"
HOME="$H4" bash "$SETUP" --dry-run >"$TMP/saida4" 2>&1; codigo=$?
check "dry-run termina com exit 0 (sem backup nenhum)"  "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "fantasma continua lá"                            "$(existe "$H4/.claude/skills/skill-do-kit/SKILL.md")"
check "nenhum backup criado"                            "$([ "$(n_backups "$H4")" = 0 ] && echo ok || echo fail)"
check "manifesto continua lá"                           "$(existe "$H4/.claude/.kit-manifest")"

echo "== rotação: 5 execuções deixam 3 backups, os mais novos =="
H5="$TMP/h5"; mkdir -p "$H5/.claude"
# A 1ª execução num HOME vazio não tem o que copiar — é o caso em que o glob de
# backup-kit-* não casa nada, e onde o script já morreu calado uma vez (set -e +
# pipefail no `for` sem match). A partir da 2ª há agents.md, statusline etc.; o
# carimbo tem resolução de segundo, daí o sleep.
HOME="$H5" bash "$SETUP" >"$TMP/saida5" 2>&1; codigo=$?
check "1ª execução em HOME vazio termina com exit 0"    "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "e chega ao fim (imprime Pronto.)"                "$(grep -q 'Pronto' "$TMP/saida5" && echo ok || echo fail)"
for i in 2 3 4 5; do sleep 1; HOME="$H5" bash "$SETUP" >/dev/null 2>&1; done
check "exatamente 3 backup-kit-* depois de 5 execuções" "$([ "$(n_backups "$H5")" = 3 ] && echo ok || echo fail)"
# os que ficaram são os 3 nomes mais altos (data mais nova) de todos os que já existiram
mkdir -p "$H5/.claude/backup-kit-20200101-000000/x" "$H5/.claude/backup-kit-20200102-000000/x"
HOME="$H5" bash "$SETUP" >/dev/null 2>&1
check "backups antigos plantados são os que saem"       "$([ ! -e "$H5/.claude/backup-kit-20200101-000000" ] && [ ! -e "$H5/.claude/backup-kit-20200102-000000" ] && echo ok || echo fail)"
check "continua com 3"                                  "$([ "$(n_backups "$H5")" = 3 ] && echo ok || echo fail)"
check "o backup desta execução é um dos 3"              "$(/bin/ls -d "$H5"/.claude/backup-kit-*/ | sort | tail -n 1 | grep -q "$(date +%Y%m%d)" && echo ok || echo fail)"
check "instalação segue íntegra (CLAUDE.md e settings)" "$([ -f "$H5/.claude/CLAUDE.md" ] && python3 -m json.tool "$H5/.claude/settings.json" >/dev/null 2>&1 && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
