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
# A escotilha é lida depois do parser: citada num doc, não desliga o hook.
case "$c_cmd" in *DELETE_BRANCH_OK=1*) exit 0 ;; esac

# `gh pr merge` em posição de comando + a flag de deleção (-d é o alias curto).
printf '%s\n' "$c_cmd" | grep -qE '(^|;|&&|\|\||\()[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' || exit 0
printf '%s\n' "$c_cmd" | grep -qE '(--delete-branch|[[:space:]]-d([[:space:]]|$))' || exit 0

# Número do PR: `gh pr merge <n>`. Sem número o gh usa o PR da branch atual — nesse caso
# deixamos passar (resolver exigiria rede e o risco cai muito: branch sem PR explícito
# raramente é base de outro).
num=$(printf '%s' "$c_cmd" | sed -nE 's/.*gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+([0-9]+).*/\1/p' | head -1)
[ -z "$num" ] && exit 0

cd "${cwd:-.}" 2>/dev/null || exit 0

# --repo do comando manda mais que o cwd. Sem isto o hook resolve o número do PR no repo
# da SESSÃO: `gh pr merge 75 --repo outra/org` rodado de dentro de outro projeto leria o
# #75 do projeto errado — falso positivo, e a falha simétrica é pior: PR realmente
# encadeado em OUTRO repo passaria batido.
repo_flag=$(printf '%s' "$c_cmd" | sed -nE 's/.*--repo[[:space:]]+["'"'"']?([^[:space:]"'"'"']+).*/\1/p' | head -1)
REPO_ARG=""
[ -n "$repo_flag" ] && REPO_ARG="--repo $repo_flag"

# Timeout curto pra o hook não travar a sessão se a rede cair. `timeout` não existe no
# macOS base (é do coreutils); usa gtimeout quando houver, senão roda direto.
if command -v timeout >/dev/null 2>&1; then TO="timeout 12"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout 12"
else TO=""; fi

# Branch do PR e filhos que apontam pra ela.
head=$($TO gh pr view "$num" $REPO_ARG --json headRefName -q .headRefName 2>/dev/null) || exit 0
[ -z "$head" ] && exit 0

children=$($TO gh pr list $REPO_ARG --base "$head" --state open --json number -q '.[].number' 2>/dev/null) || exit 0
[ -z "$children" ] && exit 0

list=$(printf '%s' "$children" | tr '\n' ' ' | sed 's/ $//' | sed 's/\([0-9]\+\)/#\1/g')
cat >&2 <<MSG
BLOQUEADO pelo hook: o PR #$num tem PR(s) encadeado(s) na sua branch ($head): $list

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
