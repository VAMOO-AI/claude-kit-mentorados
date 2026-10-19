#!/usr/bin/env bash
# A contagem de skills que o README anuncia bate com as pastas de plugin/skills/.
#
# O README diz o número em três lugares: a tabela do que vem no repo (`**N skills**`),
# a abertura de "Skills incluídas" (`São N.`) e o parágrafo do catálogo (`As N skills`).
# Em 15/10/2026 dois diziam 26 e um dizia 25, com 26 pastas: skill nova entra, alguém
# atualiza um número e esquece os outros. Nada quebra, só a página mente.
#
# Só esses três formatos contam. "8 skills / 2.000 chars" (teto da skills-projeto) é
# outro número e fica de fora de propósito.
#
# A linha "Hoje:" de docs/pagina-plugin-mentoria.md também conta (0.56.0): ela dizia
# "kit 0.53.9, 28 skills" com a 0.55.0 e 29 pastas, porque nenhum teste a lia. Confere
# skills e comandos contra as pastas e, se a linha citar versão, a do plugin.json.
#
# Uso: bash tests/test-readme-contagem.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
README="$RAIZ/README.md"
SKILLS="$RAIZ/plugin/skills"
[ -f "$README" ] || { echo "README.md não encontrado em $RAIZ"; exit 2; }
[ -d "$SKILLS" ] || { echo "plugin/skills não encontrado em $RAIZ"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

pastas=$(find "$SKILLS" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
echo "plugin/skills/ tem $pastas skills"

# compara <rótulo> <regex ERE com o número no primeiro grupo> [seção]
# Sem seção, procura no arquivo inteiro; com seção, só entre o "## <seção>" e o próximo "## ".
compara() {
  local rotulo="$1" regex="$2" secao="${3:-}" texto achados n
  if [ -n "$secao" ]; then
    texto=$(awk -v s="## $secao" '$0==s{dentro=1;next} dentro&&/^## /{exit} dentro' "$README")
  else
    texto=$(cat "$README")
  fi
  achados=$(printf '%s\n' "$texto" | grep -oE "$regex" | grep -oE '[0-9]+')
  if [ -z "$achados" ]; then
    check "$rotulo: aparece no README" fail
    echo "        → o formato sumiu; se a frase mudou de propósito, atualize este teste"
    return
  fi
  for n in $achados; do
    if [ "$n" = "$pastas" ]; then check "$rotulo: $n = $pastas pastas" ok
    else check "$rotulo: README diz $n, a pasta tem $pastas" fail; fi
  done
}

compara '"**N skills**" na tabela do repo' '\*\*[0-9]+ skills\*\*'
compara '"São N" em Skills incluídas' 'São [0-9]+\.' 'Skills incluídas'
compara '"As N skills" do catálogo' 'As [0-9]+ skills'

# A tabela de "Skills incluídas" tem uma linha por skill (`| **nome** | … |`).
linhas=$(awk '$0=="## Skills incluídas"{d=1;next} d&&/^## /{exit} d&&/^\| \*\*[a-z0-9-]+\*\* \|/' "$README" | wc -l | tr -d ' ')
if [ "$linhas" = "$pastas" ]; then check "tabela de Skills incluídas: $linhas linhas = $pastas pastas" ok
else check "tabela de Skills incluídas: $linhas linhas, a pasta tem $pastas" fail; fi

PAGINA="$RAIZ/docs/pagina-plugin-mentoria.md"
COMANDOS="$RAIZ/plugin/commands"
hoje=$(grep -m1 '^Hoje: ' "$PAGINA" 2>/dev/null)
if [ -z "$hoje" ]; then
  check 'linha "Hoje:" da pagina-plugin-mentoria.md: aparece' fail
  echo "        → o formato sumiu; se a frase mudou de propósito, atualize este teste"
else
  n=$(printf '%s\n' "$hoje" | grep -oE '[0-9]+ skills' | grep -oE '[0-9]+')
  if [ "$n" = "$pastas" ]; then check "pagina-plugin-mentoria.md \"Hoje:\": $n skills = $pastas pastas" ok
  else check "pagina-plugin-mentoria.md \"Hoje:\": diz ${n:-?} skills, a pasta tem $pastas" fail; fi
  cmds=$(find "$COMANDOS" -maxdepth 1 -name '*.md' | sed 's#.*/##; s#\.md$##' | sort | tr '\n' ' ')
  ncmd=$(printf '%s' "$cmds" | wc -w | tr -d ' ')
  m=$(printf '%s\n' "$hoje" | grep -oE '[0-9]+ comandos' | grep -oE '[0-9]+')
  if [ "$m" = "$ncmd" ]; then check "pagina-plugin-mentoria.md \"Hoje:\": $m comandos = plugin/commands/" ok
  else check "pagina-plugin-mentoria.md \"Hoje:\": diz ${m:-?} comandos, plugin/commands/ tem $ncmd" fail; fi
  listados=$(printf '%s\n' "$hoje" | sed -n 's/.*comandos (\([^)]*\)).*/\1/p' | grep -oE '`[a-z0-9-]+`' | tr -d '`' | sort | tr '\n' ' ')
  if [ "$listados" = "$cmds" ]; then check "pagina-plugin-mentoria.md \"Hoje:\": lista os comandos ($cmds)" ok
  else check "pagina-plugin-mentoria.md \"Hoje:\": lista ($listados), plugin/commands/ tem ($cmds)" fail; fi
  versao=$(node -e 'console.log(require(process.argv[1]).version)' "$RAIZ/plugin/.claude-plugin/plugin.json" 2>/dev/null)
  citada=$(printf '%s\n' "$hoje" | grep -oE 'kit [0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9.]+$')
  if [ -z "$citada" ] || [ "$citada" = "$versao" ]; then check "pagina-plugin-mentoria.md \"Hoje:\": versão ${citada:-não citada} (plugin.json: $versao)" ok
  else check "pagina-plugin-mentoria.md \"Hoje:\": cita kit $citada, o plugin.json é $versao" fail; fi
fi

echo
if [ "$falhas" -eq 0 ]; then echo "ok: README, pagina-plugin-mentoria.md e plugin/ batem"; exit 0; fi
echo "$falhas falha(s)"; exit 1
