#!/usr/bin/env bash
# SessionStart(compact): devolve, logo depois do compact, o estado do repositório.
#
# Depois de um compact o Claude volta sem saber em que branch está, o que já estava
# modificado e se a memória do projeto tem fato escrito e não commitado. O sumário do
# compact guarda a conversa, não o estado do repo, e quem está aprendendo não percebe que o
# agente perdeu o fio: só o vê perguntar de novo, ou mexer no arquivo errado.
#
# Até a 0.64 eram dois hooks: o precompact-snapshot.sh gravava o estado em disco no
# PreCompact (que não injeta contexto) e o precompact-devolve.sh o entregava no
# SessionStart(compact), com o UserPromptSubmit de rede. O repo não muda durante o compact,
# então o estado calculado aqui é o mesmo, sem cache, sem session_id virando nome de
# arquivo e sem um processo a mais em todo prompt. O stdout do SessionStart entra no
# contexto (doc de hooks), inclusive no auto-compact no meio de um turno.
#
# Entrada: payload do SessionStart (cwd, source), lido por node (scripts/hookjson.js) —
# jq não é pré-requisito do kit. O repositório vem do `.cwd` do payload: numa sessão de
# worktree do desktop o $PWD do hook pode ser o clone principal.
# Nunca escreve no repo, nunca commita a memória: só diz que ela está pendente e onde está
# o passo. Só git local, sem rede. Falha-aberta: sai 0 em qualquer caso.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0

# O cache do par antigo (um .md por sessão) não tem mais quem o leia: o kit do time também
# fundiu o par num compact-estado.sh em 22/10/2026 e não grava mais lá. A poda só limpa o
# resto que os dois pares deixaram na máquina; por idade, e nunca a pasta inteira.
[ -d "$HOME/.claude/.cache/precompact" ] && find "$HOME/.claude/.cache/precompact" -type f -name '*.md' -mmin +2880 -delete 2>/dev/null

info="$(cat | node "$H" source cwd 2>/dev/null)"
origem="$(printf '%s\n' "$info" | sed -n 1p)"
cwd="$(printf '%s\n' "$info" | sed '1d')"
# O hooks.json já filtra pelo matcher `compact`; isto segura quem chamar o script à mão.
[ -n "$origem" ] && [ "$origem" != compact ] && exit 0
[ -n "$cwd" ] || exit 0

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

printf '[estado do repo depois do compact — %s]\n' "$(date '+%d/%m %H:%M')"
printf '%s · branch %s · HEAD %s\n' "${root##*/}" "${branch:-(destacada)}" "${head:-?}"
if [ "${mod:-0}" -gt 0 ]; then
  mais=""; [ "$mod" -gt 3 ] && mais=", …"
  printf 'modificados: %s (%s%s)\n' "$mod" "$nomes" "$mais"
else
  printf 'modificados: nenhum\n'
fi
[ -n "$wt" ] && printf 'worktrees: %s\n' "$wt"
if [ "${mem:-0}" -gt 0 ]; then
  # O kit do time roda este mesmo arquivo (nucleo.lista) e publica a memória com o
  # publicar-memoria.sh que instala em ~/.claude/scripts; este kit não tem o script.
  if [ -f "$HOME/.claude/scripts/publicar-memoria.sh" ]; then
    printf 'memória do projeto: %s arquivo(s) escrito(s) e não publicado(s) — ~/.claude/scripts/publicar-memoria.sh\n' "$mem"
  else
    printf 'memória do projeto: %s arquivo(s) escrito(s) e não commitado(s) em .context/memoria — skill memoria-projeto, passo 4 (git status --short .context/memoria/)\n' "$mem"
  fi
fi
printf 'Confira antes de agir: o que estava em andamento pode ter saído do contexto.\n'
exit 0
