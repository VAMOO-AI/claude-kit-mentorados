#!/usr/bin/env bash
# O plugin/templates/gitignore.exemplo segura o que é da máquina e deixa passar o que é do time.
#
# Prova com `git check-ignore` num repo descartável: qualquer `.env.*` fica fora, o
# `.env.example` entra; a config local do Claude Code e os três layouts de worktree dentro
# do repo ficam fora; o `.claude/settings.json` e as skills do projeto entram. Ignorar
# `.claude/` inteiro "por garantia" quebraria a segunda metade, e é por isso que ela é teste.
#
# Uso: bash tests/test-gitignore-exemplo.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
MODELO="$RAIZ/plugin/templates/gitignore.exemplo"
[ -f "$MODELO" ] || { echo "gitignore.exemplo não encontrado em $RAIZ"; exit 2; }
command -v git >/dev/null || { echo "git não encontrado"; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
# Sem isto o excludesFile global de quem roda (ou o ~/.config/git/ignore) responde no
# lugar do modelo e o teste passa por um motivo que o projeto do mentorado não tem.
git -C "$TMP" config core.excludesFile /dev/null
cp "$MODELO" "$TMP/.gitignore"

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
ignorado()  { git -C "$TMP" check-ignore -q --no-index "$1"; }
fora()      { if ignorado "$1"; then check "fica fora do git: $1" ok;  else check "fica fora do git: $1" fail; fi; }
dentro()    { if ignorado "$1"; then check "entra no git: $1" fail; else check "entra no git: $1" ok; fi; }

fora   .env
fora   .env.local
fora   .env.production
fora   .env.staging.local
dentro .env.example

fora   .claude/settings.local.json
fora   .claude/worktrees/feat-x/src/app.ts
fora   .claude-worktrees/feat-x/src/app.ts
fora   .worktrees/feat-x/src/app.ts
dentro .claude/settings.json
dentro .claude/skills/minha-skill/SKILL.md
dentro .claude/agents/revisor.md

fora   node_modules/react/index.js
dentro src/app/page.tsx

echo
if [ "$falhas" -eq 0 ]; then echo "ok: gitignore.exemplo separa máquina de time"; exit 0; fi
echo "$falhas falha(s)"; exit 1
