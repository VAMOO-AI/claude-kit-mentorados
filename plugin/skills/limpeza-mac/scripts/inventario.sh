#!/usr/bin/env bash
# Inventário read-only da limpeza do Mac: não apaga nada, só escreve o plano em TSV.
# Faz fetch --prune em cada repo (única escrita, e é no .git) para saber o que já foi mergeado.
#
# Uso: bash inventario.sh <dir-do-plano> [raiz ...]
#      raízes: as da linha de comando; sem elas, LIMPEZA_RAIZES (separadas por ":");
#      sem as duas, ~/Developer ~/Projects ~/code ~/Documents, as pastas onde se costuma
#      clonar no Mac. Pasta que não existe é ignorada. Só macOS: fora dele, sai 0 sem fazer nada.
# Saída em <dir-do-plano>:
#   repos.txt      um repo por linha (clone principal)
#   worktrees.tsv  repo  branch  path  sha  dirty  estado  lock
#   branches.tsv   repo  branch  sha  estado
#   orfas.tsv      path  kb  conteudo   (dir em .claude/worktrees sem registro no git)
#   builds.tsv     dias-sem-uso  kb  path   (node_modules e .next)
#   pocos.tsv      kb  path   (caches conhecidos; kb "timeout" = du não voltou em POCO_TIMEOUT s)
# estado: ativa(Nh) | merged(ancestral) | merged(PR#N) | pushed(+N) | LOCAL(+N)[track] | sem-origin
set -uo pipefail
[ "$(uname -s)" = Darwin ] || { echo "limpeza-mac: só macOS (aqui: $(uname -s)); nada feito"; exit 0; }
OUT="${1:?uso: inventario.sh <dir-do-plano> [raiz ...]}"; shift
if [ $# -eq 0 ]; then
  if [ -n "${LIMPEZA_RAIZES:-}" ]; then
    IFS=: read -r -a RAIZES <<< "$LIMPEZA_RAIZES"; set -- "${RAIZES[@]}"
  else
    set -- "$HOME/Developer" "$HOME/Projects" "$HOME/code" "$HOME/Documents"
  fi
fi
mkdir -p "$OUT"
AGORA=$(date +%s)
# GNU primeiro: no Linux `stat -f` é outra coisa e não falha
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# -H: raiz que é symlink (~/Developer apontando para outro disco) entra; sem ele o BSD find
# para no link e o inventário sai vazio. O repo vai pelo caminho físico, que é o que o
# `worktree list` devolve: com o do link, toda worktree registrada pareceria órfã.
find -H "$@" -maxdepth 5 -name .git -type d -not -path '*/node_modules/*' 2>/dev/null \
  | sed 's#/\.git$##' | while read -r r; do (cd "$r" && pwd -P); done | sort -u > "$OUT/repos.txt"
echo "repos: $(wc -l < "$OUT/repos.txt" | tr -d ' ')" >&2

# fetch em paralelo; sem `timeout` no macOS, o lowSpeedTime corta remote pendurado
while read -r r; do
  ( GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
      -C "$r" fetch --prune --quiet origin >/dev/null 2>&1
    # origin/HEAD local fica velho quando o default muda no GitHub (pode apontar para uma
    # feature), e aí "ancestral do default" mede contra a branch errada
    git -C "$r" remote set-head origin --auto >/dev/null 2>&1 ) &
done < "$OUT/repos.txt"; wait

default_de() {
  local r="$1" d
  d=$(git -C "$r" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) && { echo "$d"; return; }
  for d in origin/main origin/master; do git -C "$r" rev-parse -q --verify "$d" >/dev/null && { echo "$d"; return; }; done
}
slug_de() { git -C "$1" remote get-url origin 2>/dev/null | sed -E 's#.*github.com[:/]##; s#\.git$##'; }

# "merged(PR#N)" só vale se o SHA local for o head do PR: gh casa pelo NOME da branch, e
# commit feito depois do merge (ou nome reusado) se perderia no -D. Tip só ancestral do head
# também não conta: é a mesma prova que o git-sync e a worktrees pedem antes de apagar.
# E só PR mergeado NO default: branch empilhada mergeada em outra feature não chegou lá.
estado_de() { # estado_de <repo> <branch> <default> <slug>
  local r="$1" b="$2" def="$3" slug="$4" sha ahead n h
  [ -z "$def" ] && { echo sem-origin; return; }
  sha=$(git -C "$r" rev-parse "refs/heads/$b")
  git -C "$r" merge-base --is-ancestor "$sha" "$def" 2>/dev/null && { echo "merged(ancestral)"; return; }
  ahead=$(git -C "$r" rev-list --count "$def..$sha" 2>/dev/null)
  if [ -n "$slug" ]; then
    while IFS=$'\t' read -r n h; do
      [ -z "$h" ] && continue
      if [ "$h" = "$sha" ]; then
        echo "merged(PR#$n)"; return
      fi
    done < <(gh pr list -R "$slug" --head "$b" --base "${def#origin/}" --state merged --json number,headRefOid \
               -q '.[] | "\(.number)\t\(.headRefOid)"' 2>/dev/null)
  fi
  [ -n "$(git -C "$r" branch -r --contains "$sha" 2>/dev/null | head -1)" ] && { echo "pushed(+$ahead)"; return; }
  echo "LOCAL(+$ahead)$(git -C "$r" for-each-ref --format='%(upstream:track)' "refs/heads/$b")"
}

: > "$OUT/worktrees.tsv"; : > "$OUT/branches.tsv"
while read -r r; do
  def=$(default_de "$r"); slug=$(slug_de "$r")
  # worktrees secundárias (a primeira do porcelain é o clone principal)
  git -C "$r" worktree list --porcelain | awk 'BEGIN{RS=""} NR>1 {
      p=""; b=""; l="";
      n=split($0, L, "\n");
      for (i=1; i<=n; i++) {
        if (L[i] ~ /^worktree /) p=substr(L[i], 10);
        if (L[i] ~ /^branch /)   b=substr(L[i], 19);
        if (L[i] ~ /^locked/)    l=(L[i]=="locked") ? "locked" : substr(L[i], 8);
        if (L[i] ~ /^prunable/)  l="PRUNABLE";
      }
      if (b == "") b="-";
      if (l == "") l="-";
      print p "\t" b "\t" l }' |
  while IFS=$'\t' read -r p b l; do
    if [ ! -d "$p" ]; then printf '%s\t%s\t%s\t-\t-\tprunable\t%s\n' "$r" "$b" "$p" "$l"; continue; fi
    sha=$(git -C "$p" rev-parse HEAD 2>/dev/null)
    # --no-optional-locks: status sem reescrever o índice, que é o sinal de atividade abaixo
    dirty=$(git --no-optional-locks -C "$p" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    # `worktree remove` sem --force apaga arquivo IGNORADO calado: .env.local, sqlite, dump.
    # Conta como sujeira o ignorado fora de build que não é cópia idêntica do clone principal
    # (o hook de worktree novo copia o .env de lá, e essa cópia pode sair)
    ign=$(git --no-optional-locks -C "$p" status --porcelain --ignored=matching 2>/dev/null \
      | sed -n 's/^!! //p' | grep -vE '(^|/)(node_modules|\.next|\.turbo|\.vercel|dist|build|\.venv|__pycache__)(/|$)|\.DS_Store$' \
      | while read -r f; do cmp -s "$p/$f" "$r/$f" || echo "$f"; done | wc -l | tr -d ' ')
    dirty=$((dirty + ign))
    idx=$(git -C "$p" rev-parse --git-path index 2>/dev/null)
    case "$idx" in /*) ;; *) idx="$p/$idx";; esac
    idade=$(( (AGORA - $(mtime "$idx")) / 3600 ))
    if [ "$b" = "-" ]; then
      # detached só sai se o HEAD já está no default; squash fica para decisão à mão
      est=detached
      [ -n "$def" ] && git -C "$r" merge-base --is-ancestor "$sha" "$def" 2>/dev/null && est="merged(ancestral)"
    else
      est=$(estado_de "$r" "$b" "$def" "$slug")
    fi
    # branch recém-criada também é ancestral do default: worktree mexida nas últimas 24h é
    # sessão em andamento, não lixo mergeado
    [ "$idade" -lt 24 ] && est="ativa(${idade}h)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$r" "$b" "$p" "$sha" "$dirty" "$est" "$l"
  done >> "$OUT/worktrees.tsv"

  emwt=$(git -C "$r" worktree list --porcelain | sed -n 's#^branch refs/heads/##p')
  git -C "$r" for-each-ref --format='%(refname:short)' refs/heads | while read -r b; do
    printf '%s\n' "$emwt" | grep -qxF "$b" && continue
    case "$b" in main|master|develop|dev|staging|production) continue;; esac
    printf '%s\t%s\t%s\t%s\n' "$r" "$b" "$(git -C "$r" rev-parse "refs/heads/$b")" "$(estado_de "$r" "$b" "$def" "$slug")"
  done >> "$OUT/branches.tsv"
done < "$OUT/repos.txt"

# órfãs: pasta em .claude/worktrees que o git não conhece mais (repo movido, sessão que morreu
# antes do cleanup). O `worktree prune` tira o registro e deixa a árvore inteira no disco.
: > "$OUT/orfas.tsv"
while read -r r; do
  [ -d "$r/.claude/worktrees" ] || continue
  reg=$(git -C "$r" worktree list --porcelain | sed -n 's#^worktree ##p')
  for d in "$r"/.claude/worktrees/*/; do
    d="${d%/}"; [ -d "$d" ] || continue
    printf '%s\n' "$reg" | grep -qxF "$d" && continue
    fontes=$(find "$d" -type f -not -path '*/node_modules/*' -not -path '*/.next/*' -not -name .DS_Store 2>/dev/null | wc -l | tr -d ' ')
    [ -e "$d/.git" ] && tipo="tem-.git" || tipo="sem-.git"
    printf '%s\t%s\t%s,%s-arquivos-fora-de-build\n' "$d" "$(du -sk "$d" | cut -f1)" "$tipo" "$fontes"
  done
done < "$OUT/repos.txt" > "$OUT/orfas.tsv"

# builds: idade pela última entrada do reflog do HEAD — mtime do índice mente, qualquer
# `git status` reescreve. %ct seria a data do COMMIT; a da entrada sai de %gd com --date=unix
while read -r d; do
  root=$(git -C "$(dirname "$d")" rev-parse --show-toplevel 2>/dev/null || dirname "$d")
  t=$(git -C "$root" reflog -1 --date=unix --format=%gd HEAD 2>/dev/null | sed -n 's/.*@{\([0-9]*\)}.*/\1/p')
  [ -z "$t" ] && t=$(git -C "$root" log -1 --format=%ct 2>/dev/null)
  [ -z "$t" ] && t=$(mtime "$root")
  printf '%s\t%s\t%s\n' $(( (AGORA - t) / 86400 )) "$(du -sk "$d" | cut -f1)" "$d"
done < <(find -H "$@" -maxdepth 6 -type d \( -name .vercel -prune -o \( -name node_modules -o -name .next \) -print -prune \) 2>/dev/null) \
  | sort -n > "$OUT/builds.tsv"

for p in \
  "$HOME/.npm" "$HOME/.cache/uv" "$HOME/.bun/install/cache" "$HOME/.yarn/berry/cache" \
  "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/puppeteer" "$HOME/.cache/codex-runtimes" \
  "$HOME/.local/share/claude/versions" "$HOME/.local/share/cursor-agent/versions" \
  "$HOME/Library/Application Support/Claude/vm_bundles" \
  "$HOME/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel" \
  "$HOME/Library/Application Support/Cursor/User/globalStorage" \
  "$HOME/.codex/archived_sessions" "$HOME/.claude/projects" "$HOME/.orbstack" \
  "$HOME/Library/Group Containers"/*.dev.orbstack "$HOME/.Trash"; do
  [ -e "$p" ] || continue
  # du em Group Containers de outro app pode parar num prompt de privacidade do macOS que
  # ninguém vê. Sem `timeout` no Mac: alarm do perl mata o du e o poço sai como "timeout"
  # em vez de segurar o inventário inteiro
  kb=$(perl -e 'alarm shift; exec @ARGV' "${POCO_TIMEOUT:-60}" du -sk "$p" 2>/dev/null)
  [ $? = 142 ] && kb=timeout   # 128 + SIGALRM
  printf '%s\t%s\n' "${kb%%[[:space:]]*}" "$p"
done | sort -rn > "$OUT/pocos.tsv"

awk -F'\t' '{e=$6; sub(/[(\[].*/, "", e); c[e]++} END{for (k in c) printf "worktrees %s: %d\n", k, c[k]}' "$OUT/worktrees.tsv" >&2
awk -F'\t' '{e=$4; sub(/[(\[].*/, "", e); c[e]++} END{for (k in c) printf "branches %s: %d\n", k, c[k]}' "$OUT/branches.tsv" >&2
echo "órfãs: $(wc -l < "$OUT/orfas.tsv" | tr -d ' ')" >&2
awk -F'\t' '{s+=$2} END{printf "builds: %.1f GB em %d dirs\n", s/1048576, NR}' "$OUT/builds.tsv" >&2
