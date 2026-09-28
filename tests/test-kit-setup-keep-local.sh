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
# que é dele; 5 execuções deixam exatamente 3 backups — os 3 mais novos; e num
# ~/.claude do kit do time (com .team-manifest) o setup não toca em nada sem --force.
#
# As regras de subagente mudaram de nome: em disco que não diferencia maiúscula
# (macOS, Windows), o ~/.claude/agents.md é o AGENTS.md que o Claude Code lê em toda
# sessão. O setup instala subagentes.md e tira o agents.md antigo, com backup (o
# .keep-local segura, como segura qualquer remoção). CLAUDE.md da pessoa que ainda
# cita agents.md ganha aviso, e o fim da saída só manda preencher os <campos> quando
# o setup instalou o CLAUDE.md — o que já existia é da pessoa.
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

echo "== agents.md antigo sai com backup, e as regras vão para subagentes.md =="
H7="$TMP/h7"; mkdir -p "$H7/.claude"
echo "agents do kit antigo" > "$H7/.claude/agents.md"
HOME="$H7" bash "$SETUP" >"$TMP/saida7" 2>&1; codigo=$?
check "setup termina com exit 0"                        "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "subagentes.md instalado"                         "$(existe "$H7/.claude/subagentes.md")"
check "agents.md antigo removido"                       "$(sumiu "$H7/.claude/agents.md")"
check "o agents.md antigo foi pro backup"               "$([ "$(cat "$H7"/.claude/backup-kit-*/agents.md 2>/dev/null)" = "agents do kit antigo" ] && echo ok || echo fail)"
check "CLAUDE.md instalado agora: manda preencher os <campos>" "$(grep -q 'preencha os campos' "$TMP/saida7" && echo ok || echo fail)"

echo "== agents.md listado no .keep-local fica, com aviso =="
H8="$TMP/h8"; mkdir -p "$H8/.claude"
echo "meu agents" > "$H8/.claude/agents.md"
printf 'agents.md\n' > "$H8/.claude/.keep-local"
HOME="$H8" bash "$SETUP" >"$TMP/saida8" 2>&1
check "o agents.md protegido continua lá, intacto"      "$([ "$(cat "$H8/.claude/agents.md" 2>/dev/null)" = "meu agents" ] && echo ok || echo fail)"
check "a saída diz que ele foi mantido"                 "$(grep -q 'mantido (está no .keep-local): agents.md' "$TMP/saida8" && echo ok || echo fail)"
check "subagentes.md é instalado mesmo assim"           "$(existe "$H8/.claude/subagentes.md")"

echo "== CLAUDE.md da pessoa que ainda cita agents.md: aviso, sem mexer nele =="
H9="$TMP/h9"; mkdir -p "$H9/.claude"
printf '# minhas regras\nSubagentes: ver ~/.claude/agents.md\n' > "$H9/.claude/CLAUDE.md"
cp "$H9/.claude/CLAUDE.md" "$TMP/claude9-antes"
HOME="$H9" bash "$SETUP" >"$TMP/saida9" 2>&1
check "CLAUDE.md da pessoa intacto"                     "$(cmp -s "$H9/.claude/CLAUDE.md" "$TMP/claude9-antes" && echo ok || echo fail)"
check "avisa que ele ainda cita agents.md"              "$(grep -q 'cita agents.md' "$TMP/saida9" && echo ok || echo fail)"
check "não manda preencher os <campos> de um CLAUDE.md que não instalou" "$(grep -q 'preencha os campos' "$TMP/saida9" && echo fail || echo ok)"
check "o fim da saída aponta o CLAUDE.kit.md"           "$(tail -n 3 "$TMP/saida9" | grep -q 'CLAUDE.kit.md' && echo ok || echo fail)"
# o aviso é pelo nome antigo exato: AGENTS.md de projeto e subagentes.md não contam
H10="$TMP/h10"; mkdir -p "$H10/.claude"
printf '# minhas regras\nNo projeto, o AGENTS.md; subagentes em ~/.claude/subagentes.md\n' > "$H10/.claude/CLAUDE.md"
HOME="$H10" bash "$SETUP" >"$TMP/saida10" 2>&1
check "AGENTS.md e subagentes.md não disparam o aviso"  "$(grep -q 'cita agents.md' "$TMP/saida10" && echo fail || echo ok)"

echo "== --dry-run mostra a remoção e o aviso, sem fazer =="
H11="$TMP/h11"; mkdir -p "$H11/.claude"
echo "agents antigo" > "$H11/.claude/agents.md"
printf 'Subagentes: ver ~/.claude/agents.md\n' > "$H11/.claude/CLAUDE.md"
HOME="$H11" bash "$SETUP" --dry-run >"$TMP/saida11" 2>&1
check "dry-run não remove o agents.md"                  "$([ "$(cat "$H11/.claude/agents.md" 2>/dev/null)" = "agents antigo" ] && echo ok || echo fail)"
check "dry-run não instala o subagentes.md"             "$(sumiu "$H11/.claude/subagentes.md")"
check "dry-run mostra a remoção do agents.md"           "$(grep -q 'dry-run.*rm .*agents\.md' "$TMP/saida11" && echo ok || echo fail)"
check "dry-run mostra o aviso do CLAUDE.md"             "$(grep -q 'cita agents.md' "$TMP/saida11" && echo ok || echo fail)"

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
echo "subagentes antigo" > "$H3/.claude/subagentes.md"
printf 'subagentes.md\n' > "$H3/.claude/.keep-local"
HOME="$H3" bash "$SETUP" >/dev/null 2>&1
check "subagentes.md do kit é instalado por cima mesmo listado" "$([ "$(cat "$H3/.claude/subagentes.md")" != "subagentes antigo" ] && echo ok || echo fail)"
check "a versão antiga foi pro backup"                  "$([ "$(cat "$H3"/.claude/backup-kit-*/subagentes.md 2>/dev/null)" = "subagentes antigo" ] && echo ok || echo fail)"

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
# pipefail no `for` sem match). A partir da 2ª há subagentes.md, statusline etc.; o
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

echo "== ~/.claude do kit do time (.team-manifest): sai 0 sem tocar em nada =="
# O setup já rodou uma vez por cima do kit do time: trocou as regras de subagente e a barra
# de status de lá pelas daqui, mexeu no settings e deixou um backup-kit-* no ~/.claude
# do time. Quem grava o .team-manifest é o update.sh do time; este kit nunca grava.
H6="$TMP/h6"; mkdir -p "$H6/.claude/skills/vamoo-verificacao" "$H6/.claude/scripts"
for f in CLAUDE.md subagentes.md statusline-command.sh skills/vamoo-verificacao/SKILL.md; do
  echo "do time" > "$H6/.claude/$f"
done
echo '{"permissions":{"allow":["Bash(bun test:*)"]}}' > "$H6/.claude/settings.json"
echo "skill/vamoo-verificacao" > "$H6/.claude/.team-manifest"
retrato() { find "$1" -print | LC_ALL=C sort; find "$1" -type f -exec cksum {} + | LC_ALL=C sort; }
antes="$(retrato "$H6")"
HOME="$H6" bash "$SETUP" >"$TMP/saida6" 2>&1; codigo=$?
check "sai com exit 0"                                  "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "nenhum arquivo criado, apagado ou alterado"      "$([ "$(retrato "$H6")" = "$antes" ] && echo ok || echo fail)"
check "nenhum backup-kit-* criado"                      "$([ "$(n_backups "$H6")" = 0 ] && echo ok || echo fail)"
check "a saída diz que o ~/.claude é do kit do time"    "$(grep -q 'kit do time' "$TMP/saida6" && echo ok || echo fail)"
# A skill setup para quando lê "Nada feito": trocar essa frase solta a skill de novo
# por cima do CLAUDE.md do time.
check "a saída diz 'Nada feito', o sinal de parada da skill" "$(grep -q 'Nada feito' "$TMP/saida6" && echo ok || echo fail)"
HOME="$H6" bash "$SETUP" --force >/dev/null 2>&1; codigo=$?
check "com --force o setup roda mesmo assim"            "$([ "$codigo" -eq 0 ] && [ "$(cat "$H6/.claude/subagentes.md")" != "do time" ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
