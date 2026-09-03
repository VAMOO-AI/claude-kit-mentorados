#!/usr/bin/env bash
# UserPromptSubmit: avisa quando a branch do repositório mudou ENTRE dois prompts da
# mesma sessão.
#
# O caso que ele pega: você está trabalhando, outra sessão (Codex, outro terminal do
# Claude) dá checkout/switch no mesmo clone, e o seu próximo edit cai na branch errada
# sem nada indicar. O block-parallel-clone-switch impede a troca partindo daqui; este
# avisa quando a troca veio de fora.
#
# Só avisa — nunca bloqueia, nunca troca de branch. Lê o JSON do hook via node (sem
# depender de jq). Falha-aberta: qualquer erro sai 0 e o prompt segue.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
info="$(cat | node "$H" session_id cwd)"
sid="$(printf '%s\n' "$info" | sed -n 1p)"
cwd="$(printf '%s\n' "$info" | sed '1d')"
[ -z "$sid" ] && exit 0
[ -z "$cwd" ] && cwd="$PWD"

branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
[ -z "$branch" ] && exit 0

dir="$HOME/.claude/.cache/branch-guard"
mkdir -p "$dir" 2>/dev/null || exit 0
# Um arquivo por sessão, para sempre, viraria centenas. Sessão de uma semana atrás não
# volta a mandar prompt; um `find` numa pasta pequena custa menos que o node acima.
find "$dir" -type f -mtime +7 -delete 2>/dev/null
marker="$dir/$sid"

anterior=$(cat "$marker" 2>/dev/null)
printf '%s' "$branch" > "$marker" 2>/dev/null

if [ -n "$anterior" ] && [ "$anterior" != "$branch" ]; then
  echo "⚠️ branch-guard: a branch mudou entre um prompt e outro ($anterior → $branch). Outra sessão pode ter trocado — confirme antes de editar (skill worktrees)."
fi
exit 0
