#!/usr/bin/env bash
# Prova de regressão do plugin/scripts/warn-cli-outdated.sh (SessionStart).
#
# O aviso compara a versão instalada com a do canal de update da pessoa
# (autoUpdatesChannel no settings.json). O template do kit grava stable, então quase todo
# mentorado está nele; quem mantém o kit costuma estar em latest. Quem está em stable não
# pode ser mandado para a latest (o auto-update dele ignora essa versão), e o cache é por
# canal, para a troca de canal não reaproveitar a versão do outro. O hook nunca sai com erro.
#
# Veio do kit do time (F8a do núcleo único), onde o canal era lido por jq: sem jq, quem
# estava em stable recebia o aviso da latest. Aqui quem lê é o node, e o bloco "sem jq"
# prova isso.
#
# Uso: bash tests/test-warn-cli-outdated.sh [caminho-do-script]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${1:-$RAIZ/plugin/scripts/warn-cli-outdated.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# PATH sem jq: cada pasta que tem jq vira uma cópia de links sem ele (o padrão do
# test-path-rules.sh).
SEM_JQ=""; n=0; resto="$PATH:"
while [ -n "$resto" ]; do
  d="${resto%%:*}"; resto="${resto#*:}"
  [ -n "$d" ] || continue
  if [ -e "$d/jq" ] || [ -e "$d/jq.exe" ]; then
    n=$((n+1)); mkdir -p "$TMP/sem-jq/$n"
    ln -s "$d"/* "$TMP/sem-jq/$n/" 2>/dev/null
    rm -f "$TMP/sem-jq/$n/jq" "$TMP/sem-jq/$n/jq.exe"
    d="$TMP/sem-jq/$n"
  fi
  SEM_JQ="${SEM_JQ:+$SEM_JQ:}$d"
done
BASE_PATH="$PATH"

# npm falso: registra o que foi perguntado e responde como o registry de hoje,
# com a stable atrás da latest.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/npm" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$HOME/npm.log"
case "$*" in
  *dist-tags.stable*) echo 2.1.273 ;;
  *" version") echo 2.1.281 ;;
esac
EOF
chmod +x "$TMP/bin/npm"

falhas=0
erros=0
casa=""; saida=""
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
tem() { printf '%s' "$saida" | grep >/dev/null -F "$1" && echo ok || echo fail; }
calado() { [ -z "$saida" ] && echo ok || echo fail; }

# Um HOME por caso, com o claude "instalado" num node_modules, como no install
# global via npm — é o caminho em que o aviso sugere `npm i -g`.
nova_casa() { # nova_casa <nome> <versão-instalada> [settings.json]
  casa="$TMP/$1"
  local pkg="$casa/lib/node_modules/@anthropic-ai/claude-code"
  mkdir -p "$pkg/bin" "$casa/bin" "$casa/.claude"
  printf '{"name":"@anthropic-ai/claude-code","version":"%s"}\n' "$2" > "$pkg/package.json"
  printf '#!/usr/bin/env bash\necho "%s (Claude Code)"\n' "$2" > "$pkg/bin/claude"
  chmod +x "$pkg/bin/claude"
  ln -s "$pkg/bin/claude" "$casa/bin/claude"
  if [ -n "${3:-}" ]; then printf '%s\n' "$3" > "$casa/.claude/settings.json"; fi
}
roda() {
  saida=$(HOME="$casa" PATH="$casa/bin:$TMP/bin:$BASE_PATH" bash "$SCRIPT" 2>&1) || erros=$((erros+1))
}
# O refresh do cache roda em background: espera o arquivo aparecer (até 5 s).
espera() { # espera <canal>
  local f="$casa/.claude/.cache/cli-version/$1" i=0
  while [ ! -s "$f" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
}
# Duas rodadas com o refresh no meio; a saída junta as duas, para o aviso da 1ª
# não se esconder atrás do throttle da 2ª.
duas() { # duas <canal>
  local antes
  roda; antes=$saida; espera "$1"; roda; saida="$antes$saida"
}

echo "canal stable"
nova_casa stable 2.1.270 '{"autoUpdatesChannel":"stable"}'
roda
check "sem cache, a 1ª rodada fica calada" "$(calado)"
espera stable
check "o npm é perguntado pela dist-tag stable" \
  "$(grep -q 'dist-tags.stable' "$casa/npm.log" 2>/dev/null && echo ok || echo fail)"
check "o cache do stable guarda a versão do stable" \
  "$([ "$(cat "$casa/.claude/.cache/cli-version/stable" 2>/dev/null)" = 2.1.273 ] && echo ok || echo fail)"
roda
check "avisa a versão do stable, não a da latest" "$(tem '2.1.270 → 2.1.273')"
check "o upgrade sugerido instala o stable" "$(tem 'claude-code@stable')"
roda
check "o aviso não se repete no mesmo dia" "$(calado)"

nova_casa frente 2.1.281 '{"autoUpdatesChannel":"stable"}'
duas stable
check "instalada à frente do stable não vira aviso de downgrade" "$(calado)"

nova_casa troca 2.1.275 '{"autoUpdatesChannel":"stable"}'
mkdir -p "$casa/.claude/.cache/cli-version"
echo 2.1.281 > "$casa/.claude/.cache/cli-version/latest"
duas stable
check "quem trocou para stable não herda a versão cacheada da latest" "$(calado)"

echo "canal latest"
nova_casa latest 2.1.270 '{"theme":"dark"}'
duas latest
check "sem a chave, o npm é perguntado pela latest" \
  "$(grep -qx 'view @anthropic-ai/claude-code version' "$casa/npm.log" 2>/dev/null && echo ok || echo fail)"
check "sem a chave, avisa a latest" "$(tem '2.1.270 → 2.1.281')"
check "sem a chave, o upgrade sugerido instala a latest" "$(tem 'claude-code@latest')"

nova_casa quebrado 2.1.270 '{"autoUpdatesChannel":'
duas latest
check "settings.json quebrado cai na latest em vez de calar" "$(tem '2.1.270 → 2.1.281')"

echo "sem jq no PATH"
BASE_PATH="$SEM_JQ"
nova_casa semjq 2.1.270 '{"autoUpdatesChannel":"stable"}'
duas stable
check "sem jq, o canal stable ainda é lido" "$(tem '2.1.270 → 2.1.273')"
check "sem jq, o upgrade sugerido instala o stable" "$(tem 'claude-code@stable')"
BASE_PATH="$PATH"

check "o hook sai 0 em toda rodada (veio erro em $erros)" "$([ "$erros" -eq 0 ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
