#!/usr/bin/env bash
# PreToolUse(Bash): bloqueia git checkout/switch/stash/reset --hard no CLONE PRINCIPAL
# quando existe OUTRA sessão ativa (marker <30min em repo-sessions) no mesmo repositório.
#
# Motivo: duas sessões no mesmo diretório trocam a branch e sobrescrevem o working tree
# uma da outra — e a segunda só percebe quando o edit cai no arquivo errado. Worktree
# linkado é livre (git-dir != git-common-dir): é para lá que a skill `worktrees` manda.
# Override consciente: prefixe o comando com PARALLEL_OK=1.
#
# Lê o JSON do hook via node (sem depender de jq). Falha-aberta: qualquer erro => exit 0.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
info="$(cat | node "$H" session_id cwd tool_input.workdir tool_input.command)"
sid="$(printf '%s\n' "$info" | sed -n 1p)"
cwd="$(printf '%s\n' "$info" | sed -n 2p)"
wd="$(printf '%s\n' "$info"  | sed -n 3p)"
c="$(printf '%s\n' "$info"   | sed '1,3d')"
[ -n "$wd" ] && cwd="$wd"
[ -z "$c" ] && exit 0

# Corpo de heredoc é conteúdo sendo escrito, não comando — some antes do match
# ("git checkout" citado num doc não é checkout). Terminador é a tag sozinha na linha;
# bash também aceita `EOF)` e `EOF)"` fechando um `$(cat <<EOF`. Com `<<-` a tag pode vir
# indentada por tabs. `<<<` é here-string, não heredoc. Tag não reconhecida engole o resto
# do comando — e aqui isso é falha ABERTA: o `git checkout` real depois do heredoc some
# junto e o guard nem chega a olhar o repo.
c_cmd=$(printf '%s\n' "$c" | awk '
  BEGIN { inhd=0; dash=0 }
  inhd {
    l=$0; if (dash) sub(/^\t+/, "", l)
    if (l == tag || l == tag";" || l == tag")" || l == tag")\"" || l == tag"\"") { inhd=0 }
    next
  }
  {
    print
    l=$0; gsub(/<<</, "", l)
    if (match(l, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_.-]*[\047"]?/)) {
      t = substr(l, RSTART, RLENGTH); dash = (t ~ /^<<-/)
      gsub(/^<<-?[ \t]*|[\047"]/, "", t); tag=t; inhd=1
    }
  }')
# A escotilha é lida depois do parser: PARALLEL_OK=1 citado num doc não desliga o hook.
case "$c_cmd" in *PARALLEL_OK=1*) exit 0 ;; esac

flat=$(printf '%s' "$c_cmd" | tr '\n' ';')
git_cmd='(^|[;&|(])[[:space:]]*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+'
m=0
printf '%s' "$flat" | grep -qE "${git_cmd}(checkout|switch)([[:space:]]|$)" && m=1
printf '%s' "$flat" | grep -qE "${git_cmd}reset[[:space:]]+--hard" && m=1
if [ "$m" = 0 ] && printf '%s' "$flat" | grep -qE "${git_cmd}stash([[:space:]]|$)"; then
  # stash list/show são read-only; o resto mexe no working tree compartilhado
  printf '%s' "$flat" | grep -qE "${git_cmd}stash[[:space:]]+(list|show)" || m=1
fi
[ "$m" = 0 ] && exit 0

# Resolve o repo-alvo: git -C <path> > primeiro cd <path> > workdir da tool > cwd da sessão.
# Path pode vir entre aspas (`git -C "$W"`, `cd "/x y"`); capturado com elas o git não
# resolve, a checagem falha ABERTA e o checkout perigoso passa — por isso o strip.
# O shell expande `~` e `$VAR` antes de o git ver o path; o hook lê a string CRUA. Sem
# reproduzir essas duas expansões, o `git -C "<path>"` interno não resolve e o hook decide
# pelo repo errado. Variável só é expandida quando o PRÓPRIO comando a atribui — é o único
# valor que o hook pode conhecer; sem atribuição, o path segue cru e cai no cwd.
expand_shell_path() {
  local p="$1" c="$2" name val i=0
  while [ "$i" -lt 5 ]; do
    i=$((i+1))
    case "$p" in *'$'*) ;; *) break ;; esac
    name=$(printf '%s' "$p" | sed -nE 's/^[^$]*\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?.*/\1/p')
    [ -z "$name" ] && break
    val=$(printf '%s' "$c" | sed -nE "s/.*(^|[;&|(]|[[:space:]])${name}=\"([^\"]*)\".*/\2/p" | head -1)
    [ -z "$val" ] && val=$(printf '%s' "$c" | sed -nE "s/.*(^|[;&|(]|[[:space:]])${name}='([^']*)'.*/\2/p" | head -1)
    [ -z "$val" ] && val=$(printf '%s' "$c" | sed -nE "s/.*(^|[;&|(]|[[:space:]])${name}=([^[:space:];&|\"']+).*/\2/p" | head -1)
    [ -z "$val" ] && break
    p=${p//\$\{$name\}/$val}
    p=${p//\$$name/$val}
  done
  case "$p" in
    "~")   p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  printf '%s' "$p"
}

tgt="${cwd:-.}"
p=$(printf '%s' "$c_cmd" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1 | tr -d '"'"'"'')
if [ -n "$p" ]; then
  tgt=$(expand_shell_path "$p" "$c_cmd")
else
  cdp=$(printf '%s' "$c_cmd" | sed -nE "s/.*cd[[:space:]]+[\"']?([^[:space:]'\";&|]+).*/\1/p" | head -1)
  [ -n "$cdp" ] && tgt=$(expand_shell_path "$cdp" "$c_cmd")
fi

root=$(git -C "$tgt" rev-parse --show-toplevel 2>/dev/null)
[ -z "$root" ] && exit 0
gd=$(git -C "$tgt" rev-parse --path-format=absolute --git-dir 2>/dev/null)
gcd=$(git -C "$tgt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
# worktree linkado tem git-dir próprio dentro de .git/worktrees/ => livre
[ -n "$gd" ] && [ -n "$gcd" ] && [ "$gd" != "$gcd" ] && exit 0

h=$(printf '%s' "$root" | shasum 2>/dev/null | awk '{print $1}')
[ -z "$h" ] && exit 0
d="$HOME/.claude/.cache/repo-sessions/$h"
[ -d "$d" ] || exit 0
others=$(find "$d" -type f ! -name .root ! -name "$sid" -mmin -30 2>/dev/null)
[ -z "$others" ] && exit 0
n=$(printf '%s\n' "$others" | grep -c .)
echo "BLOQUEADO pelo hook: $n outra(s) sessão(ões) Claude ativa(s) neste repositório nos últimos 30 min, e '$root' é o CLONE PRINCIPAL compartilhado — checkout/switch/stash/reset aqui troca a branch e sobrescreve o trabalho delas. Trabalhe num worktree próprio (regras na skill worktrees). Se tiver CERTEZA de que nenhuma outra sessão está escrevendo neste clone, prefixe o comando com PARALLEL_OK=1." >&2
exit 2
