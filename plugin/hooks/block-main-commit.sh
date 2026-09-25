#!/usr/bin/env bash
# PreToolUse(Bash): bloqueia `git commit` que cairia em main/master.
# Mais robusto que a checagem por substring:
#   1) NÃO bloqueia quando "git commit" aparece dentro de string (grep/echo).
#   2) Checa a branch do REPO-ALVO real (git -C <path> ou primeiro `cd <path>`), não só o cwd.
#   3) Ignora o corpo de heredoc: `cat > x.sh <<'EOF' … git commit … EOF` é conteúdo.
# Override: prefixe o comando com HOTFIX_MAIN=1 (commit em main proposital).
# Lê o JSON do hook via node (sem depender de jq). Falha-aberta: erro => exit 0.
# Resolve o helper ao lado do próprio script (funciona rodando do plugin) e,
# se não achar, cai pro ~/.claude de quem instalou pelo install.sh.
# gatilho: commit
#   (lido pelo hooks/pre-bash.sh: sem uma dessas palavras no payload o hook nem é
#   aberto — nem o node dele roda; ampliou o que o hook pega? amplie a linha.)

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
j="$(cat)"
c="$(printf '%s' "$j" | node "$H" tool_input.command)"
cwd="$(printf '%s' "$j" | node "$H" cwd)"
[ -z "$c" ] && exit 0

# Corpo de heredoc é conteúdo sendo escrito, não comando — some antes de qualquer match.
# Sem isto, `cat > script.sh <<'EOF'` com `git commit` e `bash -c` no corpo, numa sessão
# cujo cwd está em main, bloqueava quem só estava ESCREVENDO o script — 3 vezes num
# subagente em 03/09/2026. E o corpo também contaminava o resto: um `cd <worktree>` de
# dentro dele resolvia o repo-alvo e deixava o commit REAL em main passar (falha aberta),
# e um `HOTFIX_MAIN=1` citado num doc virava escotilha.
# Terminador é a tag sozinha na linha; bash também aceita `EOF)` e `EOF)"` fechando um
# `$(cat <<EOF`. Com `<<-` a tag pode vir indentada por tabs. `<<<` é here-string, não
# heredoc. Tag não reconhecida engole o resto do comando — por isso a leniência: ela erra
# pro lado de VER comando demais, nunca de menos.
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
case "$c_cmd" in *HOTFIX_MAIN=1*) exit 0 ;; esac

# Detecta `git commit` como COMANDO (posição de comando), não como argumento de string.
#
# O `-C` aceita path ENTRE ASPAS com espaço. Com `[^[:space:]]+` sozinho,
# `git -C "/Users/x/repo - cópia" commit` não casava, o hook desistia antes de
# olhar a branch, e o commit em main saía — falha aberta, não falso-positivo.
ALVO='git([[:space:]]+-C[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+))?[[:space:]]+commit'

is_commit=0
if printf '%s\n' "$c_cmd" | grep -qE "(^|;|&&|\|\||[({])[[:space:]]*((if|elif|then|do|else|while|until|!)[[:space:]]+)*${ALVO}([[:space:]]|$)"; then
  is_commit=1
fi
# Também pega commits embutidos em bash -c / sh -c.
if [ "$is_commit" = 0 ] \
   && printf '%s' "$c_cmd" | grep -qE '(bash|sh)[[:space:]]+-c' \
   && printf '%s\n' "$c_cmd" | grep -qE "$ALVO"; then
  is_commit=1
fi
[ "$is_commit" = 0 ] && exit 0

# Resolve o repo-alvo: git -C <path>  >  primeiro cd <path>  >  cwd da sessão.
# As aspas quebravam OS DOIS caminhos, e em direções opostas: no `cd "x"` o hook caía
# no cwd da sessão e bloqueava commit legítimo; no `git -C "x"` ele capturava o path
# COM as aspas, o git não resolvia, a branch saía vazia e o commit em main PASSAVA.
# O segundo é falha aberta — é o que a suíte de 30/08 pegou.
#
# O conserto de 30/08 tirou as aspas mas manteve a classe de caractere parando no
# ESPAÇO — que é justamente o caso que motivou a mudança. `cd "/Users/x/icaro-crm
# - cópia/.claude/worktrees/w"` virava `/Users/x/icaro-crm`, um repo que existe e
# está em main: commit legítimo em worktree bloqueado (31/08). Path entre aspas se
# lê até a aspa de fechamento, não até o primeiro espaço.
# O shell expande `~` e `$VAR` antes de o git ver o path; o hook lê a string CRUA.
# Sem reproduzir essas duas expansões, o `git -C "<path>"` interno não resolve e o
# hook decide pelo repo errado — nas duas direções: `cd ~/wt && git commit` bloqueia
# commit legítimo em worktree, e `WT=/repo-em-main; git -C $WT commit` (cwd numa
# feature branch) deixa o commit em main PASSAR. Os dois em 01/09/2026.
# Variável só é expandida quando o PRÓPRIO comando a atribui — é o único valor que
# o hook pode conhecer; sem atribuição, o path segue cru e cai no cwd (falha fechada).
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
    # Expandir o pedaço de texto (`$(mktemp`) fabricaria um path que ninguém pediu — e ele
    # ia parar na mensagem de bloqueio, mandando a pessoa consertar um caminho inventado.
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

# `git -C <path>` e `cd <path>`: aspas duplas, simples ou nu numa regex só. Cada commit em
# posição de comando é checado com o trecho que vem ATÉ ele — o que vem depois
# (`cd $M⏎git commit⏎cd $F`) ou um `-C` citado na mensagem não muda onde ele caiu, e o
# segundo commit de `git -C $F commit; git -C $M commit` não se esconde atrás do primeiro.
# O trecho termina no `commit`: primeiro o `-C` colado nele, senão um `-C` no mesmo comando,
# senão o último `cd` em posição de comando. O `-C` de outro comando não é o alvo.
Q='("([^"]+)"|'"'"'([^'"'"']+)'"'"'|([^[:space:]"'"'"';&|)]+))'
CORTE="s/((^|[;&|({])[[:space:]]*((if|elif|then|do|else|while|until|!)[[:space:]]+)*${ALVO})([[:space:]]|;|$).*/\\1/p"

checa_alvo() {
  local ate="$1" p p_cru tgt="${cwd:-.}" alvo_incerto="" b
  p=$(printf '%s' "$ate" | sed -nE "s/.*git[[:space:]]+-C[[:space:]]+${Q}[[:space:]]+commit$/\\2\\3\\4/p" | head -1)
  [ -z "$p" ] && p=$(printf '%s' "$ate" | sed -nE "s/.*git[[:space:]]+-C[[:space:]]+${Q}[^;&|]*[[:space:]]commit$/\\2\\3\\4/p" | head -1)
  [ -z "$p" ] && p=$(printf '%s' "$ate" | sed -nE "s/.*(^|[;&|({])[[:space:]]*((if|elif|then|do|else|while|until|!)[[:space:]]+)*cd[[:space:]]+${Q}.*/\\5\\6\\7/p" | head -1)
  # Path que não resolve como repo NÃO vira passe livre: cai de volta no cwd da
  # sessão. Sem isto, um path truncado ou inexistente deixava o commit em main sair.
  p_cru="$p"
  [ -n "$p" ] && p=$(expand_shell_path "$p" "$c_cmd")
  if [ -n "$p" ] && git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then
    tgt="$p"
  elif [ -n "$p" ]; then
    # O comando aponta para um repo que o hook não conseguiu resolver — variável vinda de
    # `$(mktemp -d)`/`$(…)`, path inexistente, expansão que só o shell faz. Cair no cwd
    # continua certo (falha fechada: um `git -C $VAR commit` com VAR em main não pode
    # passar), mas a mensagem afirmava "cairia na branch main (repo: <cwd>)" como se
    # tivesse verificado o alvo do comando — e quem lia ia consertar o repositório errado.
    alvo_incerto="$p_cru"
  fi

  b=$(git -C "$tgt" branch --show-current 2>/dev/null)
  case "$b" in
    main|master)
      if [ -n "$alvo_incerto" ]; then
        echo "BLOQUEADO pelo hook: o comando aponta para '$alvo_incerto', que NÃO resolvi como repo aqui (variável de \$(…), path inexistente, ou expansão que só o shell faz), então decidi pelo cwd da sessão — e ele está em '$b' (repo: $tgt). Não verifiquei a branch do alvo real. Se o alvo é outro repo, escreva o caminho literal; se é repo descartável (fixture, tmpdir de teste), prefixe o comando com HOTFIX_MAIN=1." >&2
      else
        echo "BLOQUEADO pelo hook: git commit cairia na branch '$b' (repo: $tgt). Crie uma feature branch antes (ex.: git checkout -b feat/minha-mudanca). Se foi proposital, rode o comando com HOTFIX_MAIN=1 na frente." >&2
      fi
      exit 2
      ;;
  esac
}

flat=$(printf '%s' "$c_cmd" | tr '\n' ';')
ate=$(printf '%s' "$flat" | sed -nE "$CORTE")
# Sem commit em posição de comando (só dentro de `bash -c "…"`): a linha inteira decide.
if [ -z "$ate" ]; then
  checa_alvo "$flat"
  exit 0
fi
i=0
while [ -n "$ate" ] && [ "$i" -lt 20 ]; do
  i=$((i+1))
  checa_alvo "$ate"
  resto=${flat#"$ate"}
  prox=$(printf '%s' "$resto" | sed -nE "$CORTE")
  [ -z "$prox" ] && break
  ate="$ate$prox"
done
exit 0
