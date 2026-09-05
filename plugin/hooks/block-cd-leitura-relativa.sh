#!/usr/bin/env bash
# PreToolUse(Bash): bloqueia LEITURA de caminho relativo depois de um `cd`.
#
# O problema que ele resolve, medido em 03/09/2026: o comando
#   cd /caminho/do/projeto && grep -n "cargos" src/lib/tipos.ts | head -40
# faz o Claude Code PARAR e pedir sua autorização, com esta mensagem:
#   "grep on 'src/lib/tipos.ts' after a cd would search a directory that cannot be
#    determined here, and a Read() deny rule is configured; only you can approve
#    running it anyway."
# Traduzindo: depois do `cd` ele não sabe mais em qual pasta o `grep` vai procurar. Como
# o kit configura regras `Read()` em `permissions.deny` (as que impedem o Claude de ler
# `.env`, chave SSH e afins), ele não consegue PROVAR que essa leitura não cai num
# arquivo proibido — e, na dúvida, pergunta para você. Essa pergunta aparece **até no
# modo bypass**, que é onde as pessoas ligam justamente para não serem interrompidas.
#
# Apagar as regras `Read()` calaria o prompt e derrubaria junto a proteção dos seus
# segredos, que é a única que vale em todos os modos. Então o conserto é o outro lado:
# fazer a leitura usar caminho absoluto, que ele resolve sozinho e libera sem perguntar.
# Este hook bloqueia o padrão e já devolve o comando certo — o Claude lê, corrige e
# segue, sem você precisar aprovar nada.
#
# Escotilha: prefixe o comando com CD_LEITURA_OK=1.
# Lê o JSON do hook via node (sem depender de jq). Falha-aberta: erro => exit 0.
# gatilho: cd
#   (lido pelo hooks/pre-bash.sh: sem uma dessas palavras no payload o hook nem é
#   aberto — nem o node dele roda; ampliou o que o hook pega? amplie a linha.)

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
c="$(cat | node "$H" tool_input.command)"
[ -z "$c" ] && exit 0

# Corpo de heredoc é conteúdo sendo escrito, não comando — some antes de qualquer match.
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
case "$c_cmd" in *CD_LEITURA_OK=1*) exit 0 ;; esac

# Sem `cd` em posição de comando não há ambiguidade de pasta: nada a fazer.
printf '%s\n' "$c_cmd" | grep -qE '(^|;|&&|\|\||\()[[:space:]]*cd[[:space:]]' || exit 0

# Trecho entre aspas some do comando INTEIRO (não linha a linha): argumento com espaço
# — a expressão de um `sed`, um padrão de busca, o corpo de um `gh pr create --body` com
# várias linhas — chegava partido ao separador de palavras e o pedaço do meio, com barra
# dentro, passava por caminho relativo. Dois falsos positivos assim em 03/09, no próprio
# comando que escrevia este kit. Aspas desbalanceadas engolem demais, que é o lado seguro
# para um hook que BLOQUEIA: erra deixando passar, nunca barrando à toa.
c_scan=$(printf '%s' "$c_cmd" | awk 'BEGIN{RS="\0"} { gsub(/"[^"]*"/, " Q "); gsub(/\047[^\047]*\047/, " Q "); print }')

# Procura, nos segmentos depois do `cd`, um comando de leitura com argumento de caminho
# RELATIVO. Token com `-` na frente é flag; `/`, `~` e `$` já são absolutos ou opacos.
rel=$(printf '%s' "$c_scan" | sed -E 's/(&&|\|\||;|\|)/\
/g' | awk '
  BEGIN {
    split("grep rg egrep fgrep cat head tail sed awk nl wc diff cmp xxd od strings jq shasum md5sum file stat bat", L, " ")
    for (i in L) READ[L[i]] = 1
  }
  {
    n = split($0, T, /[ \t]+/)
    i = 1
    while (i <= n && T[i] == "") i++
    cmd = T[i]; sub(/^.*\//, "", cmd)
    # launcher na frente esconde o comando real (o hook do rtk reescreve para `rtk <cmd>`)
    if (cmd == "rtk" || cmd == "command" || cmd == "time" || cmd == "nice") {
      i++; cmd = T[i]; sub(/^.*\//, "", cmd)
    }
    if (!(cmd in READ)) next
    # `sed -i` / `perl -i` é ESCRITA no arquivo, não a leitura que faz o harness escalar.
    if (cmd == "sed" || cmd == "perl") for (j = i + 1; j <= n; j++) if (T[j] ~ /^-i/) next
    for (j = i + 1; j <= n; j++) {
      t = T[j]
      if (t == "" || t == "Q") continue
      p = substr(t, 1, 1)
      if (p == "-" || p == "/" || p == "~" || p == "$") continue
      if (t ~ /\/[^\/]/ || t ~ /\.[A-Za-z]+$/) { print t; exit }
    }
  }' | head -1)
[ -z "$rel" ] && exit 0

# Pasta do `cd`, quando literal — deixa a mensagem já dar o comando pronto.
dir=$(printf '%s' "$c_cmd" | sed -nE 's/.*(^|[;&|(])[[:space:]]*cd[[:space:]]+"([^"]+)".*/\2/p' | head -1)
[ -z "$dir" ] && dir=$(printf '%s' "$c_cmd" | sed -nE "s/.*(^|[;&|(])[[:space:]]*cd[[:space:]]+'([^']+)'.*/\2/p" | head -1)
[ -z "$dir" ] && dir=$(printf '%s' "$c_cmd" | sed -nE 's/.*(^|[;&|(])[[:space:]]*cd[[:space:]]+([^[:space:]"'"'"';&|]+).*/\2/p' | head -1)

if [ -n "$dir" ]; then sugestao="$dir/$rel"; else sugestao="<pasta absoluta>/$rel"; fi
echo "BLOQUEADO pelo hook: ler '$rel' (caminho relativo) depois de um 'cd'. Depois do 'cd' o Claude Code não sabe em que pasta a leitura vai cair e, como há regra Read() em permissions.deny protegendo seus segredos, ele para e pede autorização ao usuário — inclusive no modo bypass. Refaça com caminho absoluto, sem o 'cd': '$sugestao' (ou 'grep -r <padrão> $dir', 'git -C $dir ...'). Se for mesmo necessário rodar assim, prefixe o comando com CD_LEITURA_OK=1." >&2
exit 2
