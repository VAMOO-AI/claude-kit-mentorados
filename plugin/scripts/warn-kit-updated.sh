#!/usr/bin/env bash
# warn-kit-updated.sh — SessionStart hook.
# Conta em voz alta o que mudou no kit desde a última vez que este mentorado abriu
# uma sessão. Com o auto-update ligado, o plugin se atualiza sozinho e ninguém
# avisa: o indicador de versão nova só aparece dentro do /plugin, e quem não abre
# esse menu nunca vê (o próprio README admite isso em "Atualizar depois").
#
# Não atualiza nada e nunca bloqueia — só lê a versão que ESTA sessão carregou,
# compara com a última já anunciada e imprime o resumo das versões no meio.
# Silencioso quando não há novidade, na primeira instalação, e sempre que faltar
# qualquer peça (sem novidades.txt, sem plugin.json, sem HOME gravável).
#
# Fonte do texto: plugin/novidades.txt — uma linha por versão, mais nova em cima:
#     <versão>|<resumo numa frase>[|setup]
# O 3º campo `setup` marca a versão que mexeu no que vem do /kit-vamoo:setup
# (CLAUDE.md global, barra de status, preferências) — o plugin sozinho não entrega
# essas coisas, então a linha final manda rodar o setup. O `|` é separador: não pode
# aparecer dentro do resumo (o último campo engole tudo que vier depois do 2º `|`).
#
# Estado: ~/.claude/.cache/kit-vamoo/versao-avisada. Fora do diretório do plugin
# de propósito — ~/.claude/plugins/cache/<market>/<plugin>/<versão>/ muda de nome a
# cada release e o marcador iria junto. Não precisa de entrada no ~/.claude/.keep-local:
# a varredura de remoção do kit-setup.sh só mapeia .kit-manifest para skills/, hooks/,
# commands/ e scripts/ — .cache/ está fora do alcance dela.
#
# Testável: CLAUDE_PLUGIN_ROOT (raiz do plugin) e HOME (marcador).
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
[ -n "${PLUGIN_ROOT:-}" ] || exit 0

NOVIDADES="$PLUGIN_ROOT/novidades.txt"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
[ -f "$NOVIDADES" ] && [ -f "$PLUGIN_JSON" ] || exit 0

# Versão que ESTA sessão carregou — não a que está registrada no disco. O hook roda
# a partir do diretório da versão em uso, então este arquivo é sempre o certo.
carregada="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" | head -1)"
[ -n "$carregada" ] || exit 0

CACHE="$HOME/.claude/.cache/kit-vamoo"
MARCA="$CACHE/versao-avisada"
MARCA_RELOAD="$CACHE/reload-avisado"
mkdir -p "$CACHE" 2>/dev/null || exit 0

# maior <a> <b> → verdadeiro quando a > b (ordem de versão, não de string)
maior() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

anterior="$(head -1 "$MARCA" 2>/dev/null | tr -d '[:space:]')"

# Primeira sessão depois de instalar: registra e cala. Sem isso, todo mentorado
# novo abriria a primeira sessão com o histórico inteiro do kit na tela.
if [ -z "$anterior" ]; then
  printf '%s\n' "$carregada" > "$MARCA" 2>/dev/null
  exit 0
fi

# Voltou para uma versão antiga (rollback, clone local mais velho): sem novidade a
# contar — realinha o marcador e sai.
if maior "$anterior" "$carregada"; then
  printf '%s\n' "$carregada" > "$MARCA" 2>/dev/null
  exit 0
fi

# ── versões entre o que já foi anunciado e o que está carregado ───────────────
novas=0
linhas=""
setup=0
while IFS='|' read -r v resumo flag || [ -n "${v:-}" ]; do
  case "$v" in ''|\#*) continue ;; esac
  v="$(printf '%s' "$v" | tr -d '[:space:]')"
  [ -n "$v" ] || continue
  [ "$v" = "$anterior" ] && break                 # daqui pra baixo já foi contado
  maior "$v" "$carregada" && continue             # linha de versão futura no arquivo
  maior "$v" "$anterior" || continue
  novas=$((novas + 1))
  [ "${flag:-}" = setup ] && setup=1
  if [ "$novas" -le 3 ]; then
    resumo="$(printf '%s' "${resumo:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    linhas="${linhas}• ${v} — ${resumo}
"
  fi
done < "$NOVIDADES"

# ── nada novo carregado: a atualização pode estar baixada e ainda não aplicada ──
if [ "$novas" -eq 0 ]; then
  # Só vale olhar o registro do Claude Code quando ele mudou DEPOIS que esta versão
  # foi instalada — fora disso não há o que checar, e um `node` por sessão é o
  # custo que o pre-bash.sh do kit já pagou pra derrubar (~30 ms cada).
  # O `reload-avisado` é o que impede a repetição: enquanto a sessão velha continuar
  # de pé, todo /clear e todo /compact re-disparam o SessionStart, e sem marcador este
  # aviso voltaria à tela (com um node junto) a cada um deles.
  REG="$HOME/.claude/plugins/installed_plugins.json"
  if [ -f "$REG" ] && [ "$REG" -nt "$PLUGIN_ROOT" ] \
     && { [ ! -f "$MARCA_RELOAD" ] || [ "$REG" -nt "$MARCA_RELOAD" ]; } \
     && command -v node >/dev/null 2>&1; then
    # node, nunca jq: o `"version": 2` do topo do arquivo é o schema, não a versão do
    # plugin — um sed pegaria o 2 e o kit acharia que o mentorado está no futuro.
    # O node só EXTRAI as versões, uma por linha; quem escolhe é o `sort -V` daqui —
    # o mesmo comparador do `maior()`. Dois comparadores discordariam em 0.9.0 vs
    # 0.10.0. E não dá pra pegar a última entrada do array: com o plugin instalado em
    # user e em project o registro tem duas, na ordem em que foram instaladas, então a
    # última pode ser a MAIS VELHA — e aí este aviso calaria justamente para quem tem
    # as duas instalações.
    baixada="$(node -e '
      const fs = require("fs");
      try {
        const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        const e = (j.plugins && j.plugins["kit-vamoo@vamoo-ai"]) || [];
        for (const x of e) if (x && x.version) process.stdout.write(String(x.version) + "\n");
      } catch {}
    ' "$REG" 2>/dev/null | sort -V | tail -1)"
    # `versao-avisada` NÃO é tocado aqui: o anúncio de verdade é o da versão
    # CARREGADA, e gravar agora engoliria o resumo dela na sessão seguinte.
    ja="$(head -1 "$MARCA_RELOAD" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "${baixada:-}" ] && maior "$baixada" "$carregada" && [ "$ja" != "$baixada" ]; then
      printf '%s\n' "$baixada" > "$MARCA_RELOAD" 2>/dev/null
      echo "📦 Kit VAMOO $baixada já foi baixada, mas esta sessão ainda roda a $carregada. Rode \`/reload-plugins\` para aplicar (ou \`--force\`, se ele reclamar do cache de prompt)."
    fi
  fi
  exit 0
fi

printf '%s\n' "$carregada" > "$MARCA" 2>/dev/null

# ── a mensagem: cabeçalho + até 3 versões + uma linha de fechamento ───────────
if [ "$novas" -eq 1 ]; then
  echo "📦 Kit VAMOO atualizado: $anterior → $carregada."
elif [ "$novas" -le 3 ]; then
  echo "📦 Kit VAMOO atualizado: $anterior → $carregada ($novas versões)."
else
  echo "📦 Kit VAMOO atualizado: $anterior → $carregada ($novas versões — as 3 mais recentes abaixo)."
fi
printf '%s' "$linhas"

fim="Tudo: github.com/VAMOO-AI/claude-kit-mentorados/blob/main/CHANGELOG.md"
[ "$setup" -eq 1 ] && fim="$fim · esta atualização mexe no CLAUDE.md/barra de status: rode \`/kit-vamoo:setup\`."
echo "$fim"
exit 0
