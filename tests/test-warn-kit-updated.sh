#!/usr/bin/env bash
# Prova do plugin/scripts/warn-kit-updated.sh — o aviso de novidades do SessionStart.
#
# O kit inteiro roda contra um plugin de MENTIRA montado aqui dentro ($TMP): raiz,
# plugin.json e novidades.txt sintéticos, com versões 1.x que não existem no repo.
# É de propósito: se a suíte lesse o plugin.json e o novidades.txt de verdade, todo
# bump quebraria os testes e alguém "consertaria" trocando os números — que é como
# suíte vira carimbo. Que os arquivos de verdade estejam coerentes entre si é
# assunto do tests/test-versao-changelog.sh.
#
# Uso: bash tests/test-warn-kit-updated.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT="$RAIZ/plugin/scripts/warn-kit-updated.sh"
HOOKS_JSON="$RAIZ/plugin/hooks/hooks.json"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/warn-kit.XXXXXX")"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAKE_HOME="$TMP/home"
MARCA="$FAKE_HOME/.claude/.cache/kit-vamoo/versao-avisada"
REG="$FAKE_HOME/.claude/plugins/installed_plugins.json"

# ── o plugin de mentira ───────────────────────────────────────────────────────
ROOT="$TMP/plugin"; mkdir -p "$ROOT/.claude-plugin"
printf '{\n  "name": "kit-vamoo",\n  "version": "1.4.0"\n}\n' > "$ROOT/.claude-plugin/plugin.json"
cat > "$ROOT/novidades.txt" <<'FIM'
# comentário: o script tem que pular esta linha e a vazia abaixo

1.4.0|a quarta coisa
1.3.0|a terceira coisa, que mexe no que vem do setup|setup
1.2.0|a segunda coisa
1.1.0|a primeira coisa
1.0.0|a coisa zero
FIM
# Raiz no passado: assim todo installed_plugins.json escrito durante o teste é mais
# novo que ela, que é a condição pro ramo de reload ser considerado.
touch -t 199001010000 "$ROOT"

falhas=0
check() { if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
          else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi; }
roda() { HOME="$FAKE_HOME" CLAUDE_PLUGIN_ROOT="${2:-$ROOT}" bash "$SCRIPT" 2>/dev/null; }
marca() { cat "$MARCA" 2>/dev/null; }
reset() { rm -rf "$FAKE_HOME"; mkdir -p "$FAKE_HOME/.claude/.cache"; }
semeia() { mkdir -p "$(dirname "$MARCA")"; printf '%s\n' "$1" > "$MARCA"; }
registro() { mkdir -p "$(dirname "$REG")"; printf '%s\n' "$1" > "$REG"; }
linhas() { printf '%s\n' "$1" | wc -l | tr -d ' '; }
bullets() { printf '%s\n' "$1" | grep -c '^• '; }

echo "== primeira instalação: cala e semeia o marcador =="
reset; saida="$(roda)"; codigo=$?
check "exit 0"                          "$([ $codigo -eq 0 ] && echo ok || echo fail)"
check "não imprime nada"                "$([ -z "$saida" ] && echo ok || echo fail)"
check "marcador nasce na versão carregada" "$([ "$(marca)" = 1.4.0 ] && echo ok || echo fail)"

echo "== já avisado na versão carregada: silêncio =="
reset; semeia 1.4.0; saida="$(roda)"; codigo=$?
check "exit 0 sem novidade"             "$([ $codigo -eq 0 ] && echo ok || echo fail)"
check "não imprime nada quando não há novidade" "$([ -z "$saida" ] && echo ok || echo fail)"

echo "== uma versão nova =="
reset; semeia 1.3.0; saida="$(roda)"
check "cabeçalho sem contagem"          "$(printf '%s' "$saida" | grep -q '1.3.0 → 1.4.0\.$' && echo ok || echo fail)"
check "1 bullet"                        "$([ "$(bullets "$saida")" = 1 ] && echo ok || echo fail)"
check "marcador avança pra versão carregada" "$([ "$(marca)" = 1.4.0 ] && echo ok || echo fail)"
check "no máx. 3 linhas"                "$([ "$(linhas "$saida")" -le 3 ] && echo ok || echo fail)"

echo "== três versões novas, uma delas pede /kit-vamoo:setup =="
reset; semeia 1.1.0; saida="$(roda)"
check "cabeçalho diz 3 versões"         "$(printf '%s' "$saida" | grep -q '(3 versões)' && echo ok || echo fail)"
check "3 bullets"                       "$([ "$(bullets "$saida")" = 3 ] && echo ok || echo fail)"
check "manda rodar /kit-vamoo:setup"    "$(printf '%s' "$saida" | grep -q 'kit-vamoo:setup' && echo ok || echo fail)"
check "cabe em 5 linhas"                "$([ "$(linhas "$saida")" -le 5 ] && echo ok || echo fail)"

echo "== versão sem a flag setup não manda rodar o setup =="
reset; semeia 1.3.0; saida="$(roda)"
check "sem menção ao setup quando nenhuma versão pede" \
  "$(printf '%s' "$saida" | grep -q 'kit-vamoo:setup' && echo fail || echo ok)"

echo "== resumo com | no meio: o 3º campo some, e com ele a linha do setup =="
# Comportamento REAL, não desejado. `IFS='|' read -r v resumo flag` trunca o resumo no
# primeiro "|" e joga o resto no `flag`, que deixa de ser "setup" — a versão pede o
# /kit-vamoo:setup e ninguém fica sabendo. O hook não tem como distinguir separador de
# texto, então quem impede a linha torta de chegar ao release é o gate de formato do
# tests/test-versao-changelog.sh (2 ou 3 campos por linha). Este caso é a prova de que
# a linha torta custa a flag — se um dia ele ficar verde ao contrário, o gate de lá
# deixou de ser necessário e alguém mexeu no parser.
MAL="$TMP/malformado"; mkdir -p "$MAL/.claude-plugin"
cp "$ROOT/.claude-plugin/plugin.json" "$MAL/.claude-plugin/"
cat > "$MAL/novidades.txt" <<'FIM'
1.4.0|resumo com | pipe no meio|setup
1.3.0|a terceira coisa
FIM
reset; semeia 1.3.0; saida="$(roda "" "$MAL")"
check "1 bullet mesmo com a linha torta"  "$([ "$(bullets "$saida")" = 1 ] && echo ok || echo fail)"
check "a flag setup é engolida pelo | do resumo (por isso existe o gate de formato)" \
  "$(printf '%s' "$saida" | grep -q 'kit-vamoo:setup' && echo fail || echo ok)"
check "o resumo sai truncado no primeiro |" \
  "$(printf '%s' "$saida" | grep -q 'pipe no meio' && echo fail || echo ok)"

echo "== mentorado muito atrás: corta em 3 e diz quantas pulou =="
reset; semeia 1.0.0; saida="$(roda)"
check "cabeçalho diz 4 versões"         "$(printf '%s' "$saida" | grep -q '(4 versões — as 3 mais recentes' && echo ok || echo fail)"
check "ainda são 3 bullets"             "$([ "$(bullets "$saida")" = 3 ] && echo ok || echo fail)"
check "corte cabe em 5 linhas"          "$([ "$(linhas "$saida")" -le 5 ] && echo ok || echo fail)"

echo "== marcador que nem está no arquivo (versão pré-histórica) =="
reset; semeia 0.5.0; saida="$(roda)"
check "lista tudo que o arquivo tem (5)" "$(printf '%s' "$saida" | grep -q '(5 versões' && echo ok || echo fail)"
check "marcador vai pra versão carregada mesmo vindo de versão pré-histórica" \
  "$([ "$(marca)" = 1.4.0 ] && echo ok || echo fail)"

echo "== rollback (marcador à frente do carregado): realinha e cala =="
reset; semeia 1.9.0; saida="$(roda)"
check "rollback não imprime nada"       "$([ -z "$saida" ] && echo ok || echo fail)"
check "marcador volta pra versão carregada" "$([ "$(marca)" = 1.4.0 ] && echo ok || echo fail)"

echo "== baixada mas não aplicada: avisa e NÃO mexe no marcador =="
reset; semeia 1.4.0
registro '{"version":2,"plugins":{"kit-vamoo@vamoo-ai":[{"scope":"user","version":"1.5.0"}]}}'
saida="$(roda)"
check "manda rodar /reload-plugins"     "$(printf '%s' "$saida" | grep -q 'reload-plugins' && echo ok || echo fail)"
check "cita a baixada e a carregada"    "$(printf '%s' "$saida" | grep -q '1.5.0' && printf '%s' "$saida" | grep -q '1.4.0' && echo ok || echo fail)"
check "marcador de versão avisada intocado no reload" "$([ "$(marca)" = 1.4.0 ] && echo ok || echo fail)"
check "aviso de reload é uma linha só"  "$([ "$(linhas "$saida")" = 1 ] && echo ok || echo fail)"

echo "== duas instalações (user + project) fora de ordem: vale a MAIOR, não a última =="
# O bug que isto cobre: `e.map(...).pop()` pegava a última entrada do array — que é a
# ordem de instalação, não a de versão. Com project 1.5.0 instalado antes do user 0.9.0,
# o aviso calava justamente pra quem tem as duas.
reset; semeia 1.4.0
registro '{"version":2,"plugins":{"kit-vamoo@vamoo-ai":[{"scope":"project","version":"1.5.0"},{"scope":"user","version":"0.9.0"}]}}'
saida="$(roda)"
check "avisa da 1.5.0 mesmo com a 0.9.0 por último no array" \
  "$(printf '%s' "$saida" | grep -q '1.5.0' && echo ok || echo fail)"
check "não confunde a 0.9.0 com a versão baixada" \
  "$(printf '%s' "$saida" | grep -q '0.9.0' && echo fail || echo ok)"

echo "== ordem de versão, não de string: 1.10.0 é maior que 1.9.0 =="
reset; semeia 1.4.0
registro '{"version":2,"plugins":{"kit-vamoo@vamoo-ai":[{"scope":"user","version":"1.9.0"},{"scope":"project","version":"1.10.0"}]}}'
saida="$(roda)"
check "escolhe a 1.10.0 e não a 1.9.0"  "$(printf '%s' "$saida" | grep -q '1\.10\.0' && echo ok || echo fail)"

echo "== registro com entrada sem version não quebra nem inventa aviso =="
reset; semeia 1.4.0
registro '{"version":2,"plugins":{"kit-vamoo@vamoo-ai":[{"scope":"user"},{"scope":"project","version":"1.4.0"}]}}'
saida="$(roda)"; codigo=$?
check "exit 0 com entrada capenga"      "$([ $codigo -eq 0 ] && echo ok || echo fail)"
check "silêncio com entrada capenga"    "$([ -z "$saida" ] && echo ok || echo fail)"

echo "== o \"version\":2 do installed_plugins.json não pode virar versão =="
reset; semeia 1.4.0
registro '{"version":2,"plugins":{}}'
saida="$(roda)"
check "silêncio (não leu o schema como versão)" "$([ -z "$saida" ] && echo ok || echo fail)"

echo "== sessão sem novidade não paga um node =="
reset; semeia 1.4.0
registro '{"version":2,"plugins":{"kit-vamoo@vamoo-ai":[{"version":"1.4.0"}]}}'
touch -t 210001010000 "$ROOT"          # raiz do plugin mais nova que o registro
BIN="$TMP/bin"; mkdir -p "$BIN"; REAL_NODE="$(command -v node)"
printf '#!/usr/bin/env bash\necho n >> "%s/nodes"\nexec "%s" "$@"\n' "$TMP" "$REAL_NODE" > "$BIN/node"
chmod +x "$BIN/node"; rm -f "$TMP/nodes"
nodes() { [ -f "$TMP/nodes" ] && wc -l < "$TMP/nodes" | tr -d ' ' || echo 0; }
com_node() { HOME="$FAKE_HOME" CLAUDE_PLUGIN_ROOT="$ROOT" PATH="$BIN:$PATH" bash "$SCRIPT" 2>/dev/null; }
saida="$(com_node)"
check "silêncio quando o registro é mais velho que a versão carregada" \
  "$([ -z "$saida" ] && echo ok || echo fail)"
check "nenhum node foi aberto"          "$([ "$(nodes)" = 0 ] && echo ok || echo fail)"

echo "== registro mais novo que a versão carregada: aí sim abre o node =="
touch -t 199001010000 "$ROOT"          # agora a raiz é a velha: o registro mudou depois
registro '{"version":2,"plugins":{"kit-vamoo@vamoo-ai":[{"version":"1.5.0"}]}}'
saida="$(com_node)"
check "1 node"                          "$([ "$(nodes)" = 1 ] && echo ok || echo fail)"
check "avisa do reload quando o registro é mais novo" \
  "$(printf '%s' "$saida" | grep -q 'reload-plugins' && echo ok || echo fail)"
check "marcador segue na versão carregada depois do aviso de reload" \
  "$([ "$(marca)" = 1.4.0 ] && echo ok || echo fail)"

echo "== /clear e /compact re-disparam o SessionStart: o aviso de reload não repete =="
saida2="$(com_node)"; saida3="$(com_node)"
check "2ª e 3ª execuções calam"         "$([ -z "$saida2" ] && [ -z "$saida3" ] && echo ok || echo fail)"
check "node continua em 1 chamada"      "$([ "$(nodes)" = 1 ] && echo ok || echo fail)"

echo "== saiu outra versão enquanto a sessão velha seguia de pé: avisa de novo =="
sleep 1   # mtime de segundo inteiro: o registro precisa ser estritamente mais novo
registro '{"version":2,"plugins":{"kit-vamoo@vamoo-ai":[{"version":"1.6.0"}]}}'
saida="$(com_node)"
check "avisa da versão mais nova que baixou depois" \
  "$(printf '%s' "$saida" | grep -q '1.6.0' && echo ok || echo fail)"

echo "== sem novidades.txt: silêncio, exit 0 =="
reset; semeia 1.2.0
VAZIO="$TMP/vazio"; mkdir -p "$VAZIO/.claude-plugin"
cp "$ROOT/.claude-plugin/plugin.json" "$VAZIO/.claude-plugin/"
saida="$(roda "" "$VAZIO")"; codigo=$?
check "exit 0 sem novidades.txt"        "$([ $codigo -eq 0 ] && echo ok || echo fail)"
check "silêncio sem novidades.txt"      "$([ -z "$saida" ] && echo ok || echo fail)"
check "marcador intocado sem novidades.txt" "$([ "$(marca)" = 1.2.0 ] && echo ok || echo fail)"

echo "== o hook está mesmo pendurado no SessionStart =="
# Caminho errado no hooks.json é no-op silencioso: o Claude Code não reclama, e o
# `bash -n` do CI não abre o JSON. Aqui se prova que todo comando registrado aponta
# pra arquivo que existe — e que este script é um deles.
if [ -f "$HOOKS_JSON" ] && command -v node >/dev/null 2>&1; then
  faltando="$(node -e '
    const fs = require("fs"), path = require("path");
    const raiz = process.argv[2];
    const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const faltam = [];
    for (const evento of Object.values(j.hooks || {}))
      for (const grupo of evento)
        for (const h of grupo.hooks || []) {
          const m = String(h.command || "").match(/\$\{CLAUDE_PLUGIN_ROOT\}\/([^"\s]+)/);
          if (m && !fs.existsSync(path.join(raiz, "plugin", m[1]))) faltam.push(m[1]);
        }
    process.stdout.write(faltam.join(" "));
  ' "$HOOKS_JSON" "$RAIZ" 2>/dev/null)"
  check "todo comando do hooks.json aponta pra arquivo existente" \
    "$([ -z "$faltando" ] && echo ok || echo fail)"
  [ -n "$faltando" ] && printf '        → não existe(m): %s\n' "$faltando"
  no_sessionstart="$(node -e '
    const fs = require("fs");
    const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const cmds = (j.hooks.SessionStart || []).flatMap((g) => (g.hooks || []).map((h) => h.command || ""));
    process.stdout.write(cmds.some((c) => c.includes("warn-kit-updated.sh")) ? "sim" : "nao");
  ' "$HOOKS_JSON" 2>/dev/null)"
  check "warn-kit-updated.sh está no bloco SessionStart" \
    "$([ "$no_sessionstart" = sim ] && echo ok || echo fail)"
else
  check "hooks.json legível (node disponível)" fail
fi

echo
[ "$falhas" -eq 0 ] && { echo "tudo verde"; exit 0; }
echo "$falhas falha(s)"; exit 1
