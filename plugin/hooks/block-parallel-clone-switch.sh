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
# gatilho: checkout switch reset stash
#   (lido pelo hooks/pre-bash.sh: sem uma dessas palavras no payload o hook nem é
#   aberto — nem o node dele roda; ampliou o que o hook pega? amplie a linha.)

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
# `|` solto NÃO entra no anchor: o `\|` de uma alternação de grep fazia o PADRÃO de busca
# passar por comando (18/09/2026, bloqueou um `grep -n "git push\|git checkout -b"`). `||` é
# operador de verdade e continua no anchor — `cmd || git checkout` tem que bloquear.
# `rtk git checkout` executa o mesmo checkout — o prefixo não pode escapar o guard.
# O `-C` aceita path entre aspas com espaço: com `[^[:space:]]+` sozinho, `git -C "/x y"
# checkout` não casava e o hook saía 0 antes de olhar o repo (falha aberta).
git_cmd='(^|[;&({]|\|\|)[[:space:]]*((if|elif|then|do|else|while|until|!)[[:space:]]+)*(rtk[[:space:]]+)?git([[:space:]]+-C[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+))?[[:space:]]+'
# Resolve o repo-alvo de CADA verbo: git -C <path> > último cd <path> antes dele > workdir
# da tool > cwd da sessão.
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
    # `D=$(mktemp -d)` ou `D=`pwd``: o valor só existe depois de o shell EXECUTAR aquilo.
    # Expandir o pedaço de texto (`$(mktemp`) fabricaria um path que ninguém pediu.
    case "$val" in *'$('*|*'`'*) break ;; esac
    p=${p//\$\{$name\}/$val}
    p=${p//\$$name/$val}
  done
  case "$p" in
    "~")   p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  printf '%s' "$p"
}

# Cada checkout/switch/stash/reset em posição de comando é checado com o trecho que vem ATÉ
# ele — o mesmo laço do block-main-commit. Resolver um alvo só para a linha inteira deixava
# três furos (issue claude-config-team#229): o `cd -`/`cd ..` que vem DEPOIS do checkout
# virava o alvo; o segundo checkout de `git -C $WT checkout x; git checkout main` se escondia
# atrás do `-C` do primeiro; e um `cd` dentro de `( … )` já fechado contava, embora não saia
# do subshell. Alvo: o `-C` colado no verbo; senão o último `cd` antes dele; senão o cwd.
# Alvo que não resolve como repo (`cd -`, `$HOME/x` sem atribuição, path inexistente) volta
# para o cwd — sair 0 ali deixava o checkout no clone passar.
Q='("([^"]+)"|'"'"'([^'"'"']+)'"'"'|([^[:space:]"'"'"';&|)]+))'
VERBO='(checkout|switch|reset|stash)'
CORTE="s/(${git_cmd}${VERBO})([[:space:]]|[;&|)]|$).*/\\1/p"

# reset só com --hard e stash fora de list/show mexem no working tree compartilhado.
perigoso() { # <verbo> <argumentos até o próximo separador>
  case "$1" in
    checkout|switch) return 0 ;;
    reset) case " $2 " in *[[:space:]]--hard[[:space:]]*) return 0 ;; esac ;;
    stash) case "$(printf '%s' "$2" | awk '{print $1}')" in list|show) ;; *) return 0 ;; esac ;;
  esac
  return 1
}

alvo_de() { # <trecho que termina no verbo> — define tgt e alvo_incerto
  local ate="$1" p p_cru sem_sub
  tgt="${cwd:-.}"; alvo_incerto=""
  p=$(printf '%s' "$ate" | sed -nE "s/.*git[[:space:]]+-C[[:space:]]+${Q}[[:space:]]+${VERBO}$/\\2\\3\\4/p" | head -1)
  if [ -z "$p" ]; then
    sem_sub="$ate"
    while :; do
      p=$(printf '%s' "$sem_sub" | sed -E 's/\([^()]*\)//g')
      [ "$p" = "$sem_sub" ] && break
      sem_sub="$p"
    done
    # `cd` só depois de separador, `{` ou palavra-chave (if/then/do...) — sem âncora, o `cd` de `abcd` casava.
    p=$(printf '%s' "$sem_sub" | sed -nE "s/.*(^|[;&|({])[[:space:]]*((if|elif|then|do|else|while|until|!)[[:space:]]+)*cd[[:space:]]+${Q}.*/\\5\\6\\7/p" | head -1)
  fi
  [ -z "$p" ] && return 0
  p_cru="$p"
  p=$(expand_shell_path "$p" "$c_cmd")
  case "$p" in /*) ;; *) p="${cwd:-.}/$p" ;; esac
  if git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then
    tgt="$p"
  else
    # Decidir pelo cwd continua certo (falha fechada), mas a mensagem não pode afirmar que
    # conferiu o alvo do comando — quem lê ia consertar o repositório errado.
    alvo_incerto="$p_cru"
  fi
}

checa_clone() { # usa tgt e alvo_incerto do alvo_de
  local root gd gcd h d others n
  root=$(git -C "$tgt" rev-parse --show-toplevel 2>/dev/null)
  [ -z "$root" ] && return 0
  gd=$(git -C "$tgt" rev-parse --path-format=absolute --git-dir 2>/dev/null)
  gcd=$(git -C "$tgt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  # worktree linkado tem git-dir próprio dentro de .git/worktrees/ => livre
  [ -n "$gd" ] && [ -n "$gcd" ] && [ "$gd" != "$gcd" ] && return 0

  h=$(printf '%s' "$root" | shasum 2>/dev/null | awk '{print $1}')
  [ -z "$h" ] && return 0
  d="$HOME/.claude/.cache/repo-sessions/$h"
  [ -d "$d" ] || return 0
  others=$(find "$d" -type f ! -name .root ! -name "$sid" -mmin -30 2>/dev/null)
  [ -z "$others" ] && return 0
  n=$(printf '%s\n' "$others" | grep -c .)
  echo "BLOQUEADO pelo hook: $n outra(s) sessão(ões) Claude ativa(s) neste repositório nos últimos 30 min, e '$root' é o CLONE PRINCIPAL compartilhado — checkout/switch/stash/reset aqui troca a branch e sobrescreve o trabalho delas. Trabalhe num worktree próprio (regras na skill worktrees). Se tiver CERTEZA de que nenhuma outra sessão está escrevendo neste clone, prefixe o comando com PARALLEL_OK=1." >&2
  [ -n "$alvo_incerto" ] && echo "O comando aponta para '$alvo_incerto', que NÃO resolvi como repo aqui (variável de \$(…), path inexistente, cd -, ou expansão que só o shell faz), então decidi pelo cwd da sessão. Se o alvo é outro repo, escreva o caminho literal." >&2
  exit 2
}

ate=$(printf '%s' "$flat" | sed -nE "$CORTE")
i=0
while [ -n "$ate" ] && [ "$i" -lt 20 ]; do
  i=$((i+1))
  resto=${flat#"$ate"}
  verbo=$(printf '%s' "$ate" | sed -nE 's/.*[[:space:]]([a-z]+)$/\1/p')
  args=$(printf '%s' "$resto" | sed -E 's/[;&|)].*//')
  if perigoso "$verbo" "$args"; then alvo_de "$ate"; checa_clone; fi
  prox=$(printf '%s' "$resto" | sed -nE "$CORTE")
  [ -z "$prox" ] && break
  ate="$ate$prox"
done
exit 0
