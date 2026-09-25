#!/usr/bin/env bash
# PreToolUse(Bash): bloqueia `gh pr merge --delete-branch` quando a branch do PR é base
# de OUTRO PR aberto.
#
# Por quê: deletar a base fecha o PR filho de forma IRREVERSÍVEL — `gh pr reopen` devolve
# "Could not open the pull request" e `gh pr edit --base` devolve "Cannot change the base
# branch of a closed pull request". Só resta recriar do zero, perdendo review e número.
# Aconteceu no time em 31/07/2026 (um merge matou dois PRs encadeados).
#
# Não é config do servidor: `delete_branch_on_merge` estava false no repo. O gatilho é a
# flag no comando — daí o hook ser no cliente.
#
# Override consciente: prefixe com DELETE_BRANCH_OK=1.
# Lê o JSON do hook via node (sem depender de jq). Falha-aberta: node/gh ausente, offline,
# PR não resolvido => exit 0 (não bloqueia).
# gatilho: merge
#   (lido pelo hooks/pre-bash.sh: sem uma dessas palavras no payload o hook nem é
#   aberto — nem o node dele roda; ampliou o que o hook pega? amplie a linha.)

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
info="$(cat | node "$H" cwd tool_input.workdir tool_input.command)"
cwd="$(printf '%s\n' "$info" | sed -n 1p)"
wd="$(printf '%s\n' "$info"  | sed -n 2p)"
c="$(printf '%s\n' "$info"   | sed '1,2d')"
[ -n "$wd" ] && cwd="$wd"
[ -z "$c" ] && exit 0

# Corpo de heredoc é CONTEÚDO, não comando. Sem tirar, um `gh pr create --body "$(cat <<EOF
# … gh pr merge 12 --delete-branch …
# EOF)"` dispara: o `^` do matcher casa qualquer linha, inclusive as de dentro do heredoc.
# Terminador é a tag sozinha na linha; bash também aceita `EOF)` e `EOF)"` fechando um
# `$(cat <<EOF`. Com `<<-` a tag pode vir indentada por tabs. `<<<` é here-string, não
# heredoc. Tag não reconhecida engole o resto do comando — inclusive o `gh pr merge
# --delete-branch` REAL escrito depois dele, e aí o guard some (falha aberta).
c_cmd=$(printf '%s\n' "$c" | awk '
  BEGIN { inhd=0; dash=0 }
  inhd {
    l=$0; if (dash) sub(/^\t+/, "", l)
    # O que sobra depois da tag (`)"`, `)" --delete-branch`) fecha a aspa e o `$(` do `--body "$(cat <<EOF`;
    # sem devolver isso, a aspa aberta engoliria o resto do comando.
    if (l == tag || l == tag";" || l == tag"\"" || substr(l, 1, length(tag) + 1) == tag")") { inhd=0; print substr(l, length(tag) + 1) }
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
case "$c_cmd" in *DELETE_BRANCH_OK=1*) exit 0 ;; esac

# Cada `gh pr merge` com deleção vira uma linha "<seletor>\t<repo>". Tokenizador por
# segmento de comando (`;`, `&`, `|`, `(`, `{`, fim de linha), respeitando aspas — por regex
# na linha inteira ele errava de três jeitos até 25/09, todos falha aberta:
# - `gh pr merge --squash 42 -d`: número depois de flag não era achado;
# - `cp -R dist out && gh pr merge 12 -d`: o `-R` do cp virava o repo, o gh falhava, exit 0;
# - `gh pr merge 333 -d && gh pr merge 334`: checava o #334, e o #333 apagava a base dele.
# Seletor é o primeiro argumento posicional (número, #número, URL ou branch — o gh aceita os
# três), pulando o VALOR das flags que levam um. `--repo`/`-R`/`--repo=X` valem antes ou
# depois do `pr merge`; sem eles, o repo de uma URL. Sem seletor o gh usa o PR da branch
# atual — aí deixamos passar (resolver exigiria rede e o risco cai muito, já que uma branch
# sem PR explícito raramente é base de outra).
alvos=$(printf '%s\n' "$c_cmd" | awk '
  function flush() { if (tok != "" || hadq) toks[++n] = tok; tok = ""; hadq = 0 }
  function endseg(   i, t, del, sel, repo) {
    flush(); i = 1
    while (i <= n && (toks[i] ~ /^(if|then|do|else|elif|while|until|!|time|sudo|command|nohup)$/ || toks[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
    if (i > n || toks[i] != "gh") { n = 0; return }
    i++; repo = ""
    while (i <= n && toks[i] ~ /^-/) {
      if (toks[i] ~ /^(-R|--repo)$/) { repo = toks[i + 1]; i += 2 }
      else { if (toks[i] ~ /^--repo=/) repo = substr(toks[i], 8); i++ }
    }
    if (i + 1 > n || toks[i] != "pr" || toks[i + 1] != "merge") { n = 0; return }
    del = 0; sel = ""
    for (i += 2; i <= n; i++) {
      t = toks[i]
      if (t ~ /^(-R|--repo)$/) { repo = toks[++i]; continue }
      if (t ~ /^--repo=/) { repo = substr(t, 8); continue }
      if (t ~ /^(-t|--subject|-b|--body|-F|--body-file|-A|--author-email|--match-head-commit)$/) { i++; continue }
      if (t == "--delete-branch" || t == "--delete-branch=true") { del = 1; continue }
      if (t ~ /^--/) continue
      if (t ~ /^-[A-Za-z]+$/) { if (t ~ /d/) del = 1; continue }
      if (t ~ /^-/) continue
      if (sel == "") sel = t
    }
    if (del && sel != "") print sel "\t" repo
    n = 0
  }
  # A aspa atravessa linha (`--body "l1⏎l2" -d`), `\` no fim da linha continua o comando e
  # `\"` é aspa literal: sem isso o `-d` da linha seguinte não pertencia a merge nenhum.
  {
    cont = 0
    for (k = 1; k <= length($0); k++) {
      ch = substr($0, k, 1)
      if (ch == "\\" && q != "\047") {
        if (k == length($0)) { if (q == "") cont = 1; break }
        tok = tok substr($0, ++k, 1); continue
      }
      if (q != "") { if (ch == q) q = ""; else tok = tok ch; continue }
      if (ch == "\"" || ch == "\047") { q = ch; hadq = 1; continue }
      if (ch == "#" && tok == "") break
      if (ch == " " || ch == "\t") { flush(); continue }
      if (ch ~ /[;&|(){}]/) { endseg(); continue }
      tok = tok ch
    }
    if (q != "") tok = tok " "
    else if (!cont) endseg()
    else flush()
  }
  END { endseg() }')
[ -z "$alvos" ] && exit 0

cd "${cwd:-.}" 2>/dev/null || exit 0

# Timeout curto pra o hook não travar a sessão se a rede cair. `timeout` não existe no
# macOS base (é do coreutils); usa gtimeout quando houver, senão roda direto.
if command -v timeout >/dev/null 2>&1; then TO="timeout 12"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout 12"
else TO=""; fi

# --repo do comando manda mais que o cwd. Sem isto o hook resolve o número do PR no repo
# da SESSÃO: `gh pr merge 75 --repo outra/org` rodado de dentro de outro projeto leria o
# #75 do projeto errado — falso positivo, e a falha simétrica é pior: PR realmente
# encadeado em OUTRO repo passaria batido.
while IFS=$'\t' read -r sel repo_flag; do
  num=${sel#\#}
  case "$num$repo_flag" in *'$'*|*'`'*) continue ;; esac
  case "$num" in
    http*/pull/*)
      [ -z "$repo_flag" ] && repo_flag=$(printf '%s' "$num" | sed -nE 's#^https?://[^/]+/([^/]+/[^/]+)/pull/.*#\1#p')
      num=$(printf '%s' "$num" | sed -nE 's#.*/pull/([0-9]+).*#\1#p')
      [ -z "$num" ] && continue ;;
  esac
  REPO_ARG=""
  [ -n "$repo_flag" ] && REPO_ARG="--repo $repo_flag"

  # Branch do PR e filhos que apontam pra ela.
  head=$($TO gh pr view "$num" $REPO_ARG --json headRefName -q .headRefName </dev/null 2>/dev/null) || continue
  [ -z "$head" ] && continue

  children=$($TO gh pr list $REPO_ARG --base "$head" --state open --json number -q '.[].number' </dev/null 2>/dev/null) || continue
  [ -z "$children" ] && continue

  case "$num" in *[!0-9]*) rotulo=$num ;; *) rotulo="#$num" ;; esac
  list=$(printf '%s' "$children" | tr '\n' ' ' | sed 's/ $//' | sed -E 's/([0-9]+)/#\1/g')
cat >&2 <<MSG
BLOQUEADO pelo hook: o PR $rotulo tem PR(s) encadeado(s) na sua branch ($head): $list

Deletar essa branch FECHA esses PRs e eles NÃO REABREM (base de PR fechado é imutável) — só recriando do zero.

Faça nesta ordem:
  1. gh pr merge $num --squash            # SEM --delete-branch
  2. para cada filho: git rebase --onto origin/main <sha-da-base-antiga> && git push --force-with-lease
     (o squash reescreveu o ancestry; 'git merge origin/main' daria conflito)
  3. gh pr edit <filho> --base main
  4. git push origin --delete $head       # agora sim

Override consciente: prefixe DELETE_BRANCH_OK=1.
MSG
  exit 2
done <<ALVOS
$alvos
ALVOS
exit 0
