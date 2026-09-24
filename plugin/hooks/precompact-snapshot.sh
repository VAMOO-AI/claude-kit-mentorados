#!/usr/bin/env bash
# PreCompact: grava o estado do repositório que o compact apaga.
#
# Depois de um compact o Claude volta sem saber em que branch está, o que já estava
# modificado e se a memória do projeto tem fato escrito e não commitado. O sumário do
# compact guarda a conversa, não o estado do repo — e quem está aprendendo não percebe que
# o agente perdeu o fio: só o vê perguntar de novo, ou mexer no arquivo errado.
#
# O par é o `precompact-devolve.sh`: aqui grava, lá devolve. São dois porque o PreCompact
# NÃO injeta contexto — o stdout dele vai para o log de debug. Quem injeta é o
# SessionStart com matcher `compact`, logo depois (e o UserPromptSubmit, como rede), então o
# snapshot espera em disco até lá.
#
# Entrada: payload do PreCompact (session_id, cwd, trigger), lido por node
# (scripts/hookjson.js) — jq não é pré-requisito do kit.
# Saída: ~/.claude/.cache/precompact/<session_id>.md. Nunca escreve no repo, nunca commita a
# memória: só diz que ela está pendente e onde está o passo. Só git local, sem rede.
# Falha-aberta: sai 0 em qualquer caso. Nunca bloqueia o compact (exit 2 bloquearia).
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0

info="$(cat | node "$H" session_id trigger cwd 2>/dev/null)"
sid="$(printf '%s\n' "$info" | sed -n 1p)"
gatilho="$(printf '%s\n' "$info" | sed -n 2p)"
cwd="$(printf '%s\n' "$info" | sed '1,2d')"
[ -z "$sid" ] && exit 0
case "$sid" in */*|.*) exit 0 ;; esac   # o session_id vira nome de arquivo
[ -z "$cwd" ] && cwd="$PWD"

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[ -z "$root" ] && exit 0

# Junta linhas com ", " — `paste -sd', '` alterna os dois caracteres e sai "a,b c".
junta() { awk 'NR > 1 { printf ", " } { printf "%s", $0 }'; }

branch=$(git -C "$root" branch --show-current 2>/dev/null)
# Corte por caractere, não por byte: `cut -c` no Linux parte acento ao meio.
head=$(git -C "$root" log -1 --format='%h %<(60,trunc)%s' 2>/dev/null | sed 's/ *$//')
# quotePath=false: acento sai como acento, não como \303\247. Nome com espaço ainda vem
# entre aspas, que o sed tira; `cut -c4-` e não o último campo, que o partiria ao meio.
# Rename/cópia vem como `velho -> novo`: fica só o destino. O corte é só nessas linhas e
# no primeiro separador: origem com espaço vem entre aspas, sem espaço não tem seta, e
# um arquivo novo pode ter ` -> ` no nome.
status=$(git -c core.quotePath=false -C "$root" status --porcelain 2>/dev/null)
mod=$(printf '%s' "$status" | grep -c . 2>/dev/null)
nomes=$(printf '%s\n' "$status" | sed '/^$/d' \
  | sed -E -e 's/^([RC]. )"([^"\\]|\\.)*" -> /\1/' -e 's/^([RC]. )[^" ][^ ]* -> /\1/' \
  | cut -c4- | sed 's/^"\(.*\)"$/\1/' | head -3 | junta)
wt=$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | sed 1d | sed 's|.*/||' | junta)
# -uall: sem ele, uma pasta de memória toda nova conta como UMA linha, seja qual for o
# número de arquivos dentro.
mem=$(git -C "$root" status --porcelain --untracked-files=all -- .context/memoria/ 2>/dev/null | grep -c . 2>/dev/null)

d="$HOME/.claude/.cache/precompact"
mkdir -p "$d" 2>/dev/null || exit 0

{
  printf '[estado do repo antes do compact (%s) — %s]\n' "${gatilho:-?}" "$(date '+%d/%m %H:%M')"
  printf '%s · branch %s · HEAD %s\n' "${root##*/}" "${branch:-(destacada)}" "${head:-?}"
  if [ "${mod:-0}" -gt 0 ]; then
    mais=""; [ "$mod" -gt 3 ] && mais=", …"
    printf 'modificados: %s (%s%s)\n' "$mod" "$nomes" "$mais"
  else
    printf 'modificados: nenhum\n'
  fi
  [ -n "$wt" ] && printf 'worktrees: %s\n' "$wt"
  if [ "${mem:-0}" -gt 0 ]; then
    printf 'memória do projeto: %s arquivo(s) escrito(s) e não commitado(s) em .context/memoria — skill memoria-projeto, passo 4 (git status --short .context/memoria/)\n' "$mem"
  fi
  printf 'Confira antes de agir: o que estava em andamento pode ter saído do contexto.\n'
} > "$d/$sid.md" 2>/dev/null

exit 0
