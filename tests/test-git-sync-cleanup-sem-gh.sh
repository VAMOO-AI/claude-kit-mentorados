#!/usr/bin/env bash
# Prova de regressão do cleanup do plugin/skills/git-sync/scripts/git-sync.sh em
# repositório onde o gh não pode rodar.
#
# Em 28/09/2026, num projeto de cliente (o AGENTS.md do repo proíbe `gh`; os PRs saem pela
# API com um token próprio), o `--cleanup-dry-run` devolveu "gh indisponível — sem prova"
# para as 7 branches locais, todas com PR mergeado e head == tip, e deixou como "keep" um
# worktree com lock de pid morto. A limpeza teve de ser provada à mão, PR a PR.
#
# Três buracos, cobertos aqui:
#   1. prova de PR sem gh: API REST do GitHub com o token que `git-sync.tokenVar` nomeia;
#   2. repo onde o gh não pode nem ser sondado (`git-sync.noGh`): nenhuma chamada ao gh;
#   3. branch remota sua sem cópia local ficava invisível. Agora é listada, com o comando
#      de apagar impresso (nunca executado), e só a sua: lá os dois autores usam o MESMO
#      e-mail, então "sua" é nome + e-mail do autor iguais ao user.name/user.email do clone.
#
# GH_TOKEN/GITHUB_TOKEN do ambiente saem de todos os runs: são o fallback do token da API,
# e um token de CI no ambiente mudaria o caso "sem token".
#
# Uso: bash tests/test-git-sync-cleanup-sem-gh.sh [caminho-do-script]
set -uo pipefail
unset GH_TOKEN GITHUB_TOKEN
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-semgh.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep -qE -- "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
cd "$CLONE"
git config user.email mesmo@x; git config user.name eu; git config commit.gpgsign false
echo base > base.txt; git add base.txt; git commit -qm base
git branch -M main; git remote add origin "$ORIGIN"; git push -qu origin main

squash() { # <branch> <arquivo> — commit na branch, push, squash em main; ecoa o tip
  git checkout -q main; git checkout -qb "$1"
  echo "$1" > "$2"; git add "$2"; git commit -qm "$1"
  git push -qu origin "$1"
  git checkout -q main; git merge -q --squash "$1" >/dev/null && git commit -qm "$1 (squash)"
  git rev-parse "$1"
}

# 'feita': PR mergeado, remoto sobreviveu; 'sumiu': PR mergeado e remoto apagado ([gone])
SHA_FEITA="$(squash feita feita.txt)"
SHA_SUMIU="$(squash sumiu sumiu.txt)"
# 'orfa': nunca teve PR
git checkout -q main; git checkout -qb orfa
echo o > o.txt; git add o.txt; git commit -qm orfa; git push -qu origin orfa
# 'so-remota-minha': PR mergeado, a cópia local já foi apagada — sobrou só a remota
SHA_SOREMOTA="$(squash so-remota-minha soremota.txt)"
# 'so-remota-sem-pr': minha, só no remoto, sem PR
git checkout -q main; git checkout -qb so-remota-sem-pr
echo s > s.txt; git add s.txt; git commit -qm "sem pr"; git push -qu origin so-remota-sem-pr
# 'do-colega': só no remoto, MESMO e-mail e outro nome — não é minha
git checkout -q main; git checkout -qb do-colega
echo c > c.txt; git add c.txt
git -c user.name="Colega" -c user.email=mesmo@x commit -qm "do colega"; git push -qu origin do-colega

git checkout -q main; git push -q origin main
git branch -q -D so-remota-minha so-remota-sem-pr do-colega
git push -q origin --delete sumiu >/dev/null 2>&1
git fetch -q --prune origin

# worktree órfão: branch com PR mergeado, lock de sessão morta
SHA_WT="$(squash wtfeita wt.txt)"
git push -q origin main; git fetch -q origin
git worktree add -q "$TMP/wt" wtfeita 2>/dev/null
git worktree lock --reason "claude session teste (pid 999999 start now)" "$TMP/wt" 2>/dev/null

git config git-sync.noGh true
git config git-sync.tokenVar TESTE_GH_TOKEN
git config git-sync.repo dono/repo

# gh falso: qualquer chamada deixa marca — com git-sync.noGh ele não pode rodar
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/gh-chamado"
exit 0
EOF
# curl falso: responde a API de pulls pelo parâmetro head=dono:<branch> e exige o token
# no cabeçalho lido do stdin (token em argv apareceria no ps)
cat > "$TMP/bin/curl" <<EOF
#!/usr/bin/env bash
hdr="\$(cat)"
case "\$hdr" in *"Bearer segredo-123"*) ;; *) echo '{"message":"Bad credentials"}'; exit 22 ;; esac
url=""; head=""
for a in "\$@"; do
  case "\$a" in head=*) head="\${a#head=}" ;; https://*) url="\$a" ;; esac
done
case "\$url" in
  */repos/dono/repo/pulls*) ;;
  *) echo '{"message":"Not Found"}'; exit 22 ;;
esac
case "\$head" in
  dono:feita)           echo '[{"number":10,"merged_at":"2026-09-01T00:00:00Z","head":{"sha":"$SHA_FEITA"}}]' ;;
  dono:sumiu)           echo '[{"number":11,"merged_at":"2026-09-01T00:00:00Z","head":{"sha":"$SHA_SUMIU"}}]' ;;
  dono:so-remota-minha) echo '[{"number":12,"merged_at":"2026-09-01T00:00:00Z","head":{"sha":"$SHA_SOREMOTA"}}]' ;;
  dono:wtfeita)         echo '[{"number":13,"merged_at":"2026-09-01T00:00:00Z","head":{"sha":"$SHA_WT"}}]' ;;
  dono:orfa)            echo '[{"number":14,"merged_at":null,"head":{"sha":"x"}}]' ;;
  "")                   echo '[{"number":20,"title":"PR aberto","head":{"ref":"orfa"},"user":{"login":"eu"}}]' ;;
  *)                    echo '[]' ;;
esac
EOF
chmod +x "$TMP/bin/gh" "$TMP/bin/curl"

printf 'OUTRO=1\nexport TESTE_GH_TOKEN="segredo-123"\n' > "$TMP/tokens"
run() { GIT_SYNC_TOKENS_FILE="$TMP/tokens" PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$CLONE" --status-only "$@" 2>&1; }

echo "== dry-run prova pela API REST, sem gh =="
OUT="$(run --cleanup-dry-run)"
check 'sumiu — SQUASH de PR #11 merged, head == tip'           "[gone] provada pela API"              "$OUT"
check 'feita — PR #10 merged, head == tip.*git push origin --delete feita' "remoto vivo provado pela API" "$OUT"
refute 'orfa — .*(head == tip|SQUASH)'                         "orfa: PR fechado sem merge não prova" "$OUT"
check 'CANDIDATO: .*/wt \(wtfeita\) \[squash: PR #13 merged, head == tip\].*lock stale' "worktree órfão com lock morto vira candidato" "$OUT"
check 'so-remota-minha — PR #12 merged, head == tip → git push origin --delete so-remota-minha' "remota minha sem cópia local listada com o comando" "$OUT"
check 'so-remota-sem-pr — .*sem PR merged'                     "remota minha sem PR: listada sem veredito de apagar" "$OUT"
refute 'do-colega'                                             "remota do colega (mesmo e-mail) fica de fora" "$OUT"
refute 'segredo-123'                                           "token nunca aparece na saída"         "$OUT"
refute 'gh indisponível'                                       "não cai no 'sem prova'"               "$OUT"

echo "== PRs abertos saem pela API =="
OUT="$(run)"
check '#20 PR aberto \(orfa, eu\)'                             "lista de PRs abertos sem gh"          "$OUT"
check 'cleanup: .*--cleanup-dry-run'                           "run padrão aponta o cleanup"          "$OUT"

echo "== apply apaga só o local provado e nunca o remoto =="
OUT="$(run --cleanup-apply)"
check 'deleted branch sumiu \(-D — squash de PR #11'           "[gone] provada: apagada"              "$OUT"
check 'deleted branch feita \(-D — PR #10 merged, head == tip\)' "remoto vivo: local apagada"         "$OUT"
check 'removed worktree .*/wt'                                 "worktree órfão removido"              "$OUT"
git show-ref --verify --quiet refs/heads/orfa && printf '  ok    %s\n' "orfa continua" \
  || { printf '  FALHA %s\n' "orfa apagada sem prova"; falhas=$((falhas+1)); }
for r in feita so-remota-minha so-remota-sem-pr do-colega; do
  if git ls-remote --exit-code --heads origin "$r" >/dev/null 2>&1; then printf '  ok    %s\n' "remota $r intacta"
  else printf '  FALHA %s\n' "remota $r apagada pelo script"; falhas=$((falhas+1)); fi
done

echo "== sem token: 'sem prova', nunca 'sem PR' =="
OUT="$(PATH="$TMP/bin:$PATH" GIT_SYNC_TOKENS_FILE="$TMP/nao-existe" bash "$SCRIPT" --cwd "$CLONE" --status-only --cleanup-dry-run 2>&1)"
refute 'so-remota-sem-pr — ! sem PR'                            "sem token não afirma ausência de PR"  "$OUT"
check 'so-remota-sem-pr — \(sem prova'                                "sem token: diz que não tem prova"     "$OUT"

echo "== --no-gh na linha de comando faz o mesmo que git-sync.noGh =="
git config --unset git-sync.noGh
OUT="$(run --no-gh --cleanup-dry-run)"
check 'so-remota-minha — PR #12 merged, head == tip → git push origin --delete so-remota-minha' "--no-gh: prova pela API" "$OUT"
git config git-sync.noGh true

echo "== git-sync.noGh / --no-gh: nenhum dos runs acima chamou o gh =="
if [ -e "$TMP/gh-chamado" ]; then printf '  FALHA %s\n' "git-sync.noGh: gh foi chamado ($(tr '\n' ';' < "$TMP/gh-chamado"))"; falhas=$((falhas+1))
else printf '  ok    %s\n' "git-sync.noGh: gh nunca chamado"; fi

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
