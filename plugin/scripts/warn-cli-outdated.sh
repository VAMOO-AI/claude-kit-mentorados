#!/usr/bin/env bash
# warn-cli-outdated.sh — SessionStart hook.
# Avisa quando o binário do Claude Code está atrás do publicado no npm, no canal de
# update da pessoa (autoUpdatesChannel no settings.json: o template do kit grava stable).
# Nunca atualiza sozinho e NUNCA bloqueia: a consulta de rede roda em background e grava
# cache; o hook só lê o cache da rodada anterior. Silencioso quando em dia.
set -uo pipefail

# Quem está em stable não pode ser mandado para a latest, que o auto-update dele
# ignora. Sem a chave, settings quebrado ou outro canal: latest, como sempre foi.
# Lê por node, não por jq: jq não é pré-requisito do kit, e sem ele quem está em stable
# recebia o aviso da latest.
canal="$(node -e '
  try {
    const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (typeof s.autoUpdatesChannel === "string") process.stdout.write(s.autoUpdatesChannel);
  } catch {}
' "$HOME/.claude/settings.json" 2>/dev/null)"
[ "$canal" = stable ] || canal=latest

CACHE_DIR="$HOME/.claude/.cache/cli-version"
# Um cache por canal: quem troca de canal não herda a versão do outro.
VERSAO_F="$CACHE_DIR/$canal"
NOTIFIED_F="$CACHE_DIR/notified_at"
TTL=$((24 * 3600))
mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0

now=$(date +%s)

# GNU antes do BSD: no Linux o `stat -f` é "file system" e o %m vira nome de arquivo,
# a saída vem com lixo e a conta do TTL derruba o script.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# 1) refresh do cache em background se venceu (não bloqueia a sessão)
campo=version
[ "$canal" = stable ] && campo=dist-tags.stable
if [ ! -s "$VERSAO_F" ] || [ $((now - $(mtime "$VERSAO_F"))) -gt "$TTL" ]; then
  ( npm view @anthropic-ai/claude-code "$campo" 2>/dev/null \
      | tr -d '[:space:]' > "$VERSAO_F.tmp" \
      && [ -s "$VERSAO_F.tmp" ] && mv "$VERSAO_F.tmp" "$VERSAO_F" \
      || rm -f "$VERSAO_F.tmp" ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

alvo="$(cat "$VERSAO_F" 2>/dev/null)"
[ -z "$alvo" ] && exit 0

# 2) versão instalada — lê o package.json do install (sem spawnar o próprio claude)
cur=""
bin="$(command -v claude 2>/dev/null)"
if [ -n "$bin" ]; then
  real="$(readlink -f "$bin" 2>/dev/null || echo "$bin")"
  pkg="$(dirname "$(dirname "$real")")/package.json"
  [ -f "$pkg" ] && cur="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pkg" | head -1)"
fi
[ -z "$cur" ] && cur="$(claude --version 2>/dev/null | awk '{print $1}')"
[ -z "$cur" ] && exit 0

[ "$cur" = "$alvo" ] && exit 0
# menor-ou-igual => em dia (ou à frente, em build local ou vindo de outro canal)
[ "$(printf '%s\n%s\n' "$cur" "$alvo" | sort -V | tail -1)" = "$cur" ] && exit 0

# 3) throttle: no máximo 1 aviso a cada 24h
if [ -f "$NOTIFIED_F" ] && [ $((now - $(mtime "$NOTIFIED_F"))) -lt "$TTL" ]; then
  exit 0
fi
touch "$NOTIFIED_F" 2>/dev/null

# 4) comando de upgrade conforme o método de instalação
if [ -n "${real:-}" ] && [ "${real#*/node_modules/}" != "$real" ]; then
  cmd="npm i -g @anthropic-ai/claude-code@$canal"
elif brew list --cask claude-code >/dev/null 2>&1; then
  cmd="brew upgrade --cask claude-code"
else
  cmd="claude update"
fi

auto=""
grep -q '"autoUpdates"[[:space:]]*:[[:space:]]*false' "$HOME/.claude.json" 2>/dev/null \
  && auto=" Auto-update está OFF em ~/.claude.json."

echo "⬆️ Claude Code $cur → $alvo disponível no canal $canal. Rode fora da sessão: \`$cmd\` (a sessão atual continua na $cur; o upgrade só vale no próximo start).$auto"
exit 0
