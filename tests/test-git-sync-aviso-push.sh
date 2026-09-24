#!/usr/bin/env bash
# Prova do aviso "NUNCA foi ao GitHub" do plugin/skills/git-sync/scripts/git-sync.sh.
#
# Medido em 17/09/2026, neste repo: o relatório disse
#
#   ! fix/readme-memoria-so-no-clone: 2 commit(s) e NUNCA foi ao GitHub — 'git push -u …'
#
# para uma branch que foi ao GitHub, virou o PR #91, mergeou em 10/09 e teve a remota
# deletada no merge. O aviso INFERIA "nunca pushado" da ausência de upstream e de
# origin/<branch> — e squash merge produz exatamente esse estado. Seguir o conselho
# recriaria a branch remota e abriria um PR vazio.
#
# O próprio script já tem a prova certa em outro lugar: o --cleanup-apply consulta o gh
# por PR mergeado cuja head == tip, justamente porque squash quebra a ancestralidade. A
# varredura de branches locais não reusava isso.
#
# Os ramos:
#   - PR mergeado com head == tip  → não diz "nunca foi"; diz que é sobra, e não manda pushar;
#   - gh responde e não há PR      → mantém o "push -u", que aí é o conselho certo;
#   - gh sem acesso ao repo        → não afirma nem um nem outro; diz que não deu para saber;
#   - conta ativa não enxerga, outra do keyring sim → a prova usa a conta que enxerga.
#
# Uso: bash tests/test-git-sync-aviso-push.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-aviso.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <regex> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
cd "$CLONE" || exit 2
git config user.email t@t; git config user.name t; git config commit.gpgsign false
echo base > base.txt; git add base.txt; git commit -qm base
git branch -M main; git remote add origin "$ORIGIN"; git push -qu origin main

# `mergeada`: o estado que o squash merge deixa — commits locais, sem upstream, sem
# origin/<branch>, e o conteúdo já em main pelo PR.
git checkout -q -b mergeada
echo a > a.txt; git add a.txt; git commit -qm "feat: a"
SHA_MERGEADA="$(git rev-parse HEAD)"

# `sozinha`: mesma forma, mas nunca foi a lugar nenhum.
git checkout -q -b sozinha main
echo b > b.txt; git add b.txt; git commit -qm "feat: b"

git checkout -q main

# No caso real as duas estavam em worktree (é o que sobra quando a sessão termina e o PR
# mergeia). Aqui o aviso sai da varredura de TODAS as branches locais, então o worktree
# não é condição — mas é o cenário que aconteceu.
git -C "$CLONE" worktree add -q "$TMP/wt-mergeada" mergeada
git -C "$CLONE" worktree add -q "$TMP/wt-sozinha" sozinha

# gh falso: só `mergeada` tem PR mergeado, com head == tip.
mkdir -p "$TMP/bin"
{
  echo '#!/usr/bin/env bash'
  echo 'case "$*" in'
  echo '  *"repo view"*) exit 0 ;;'
  echo "  *\"pr list\"*\"--head mergeada\"*) echo \"91 $SHA_MERGEADA\"; exit 0 ;;"
  echo '  *"pr list"*) echo ""; exit 0 ;;'
  echo 'esac'
  echo 'exit 0'
} > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

# GH_TOKEN herdado da máquina desligaria a resolução de conta do script: limpo aqui.
rodar_com() { # <dir-do-gh> [args…]
  local bin="$1"; shift
  env -u GH_TOKEN -u GITHUB_TOKEN PATH="$bin:$PATH" bash "$SCRIPT" --cwd "$CLONE" --status-only "$@" 2>&1
}

echo "== branch cujo PR mergeou (squash apagou a remota) =="
OUT="$(rodar_com "$TMP/bin" --no-pr)"
refute 'mergeada.*NUNCA foi ao GitHub' "não afirma que nunca foi ao GitHub" "$OUT"
refute "mergeada.*push -u origin mergeada" "não manda pushar de volta" "$OUT"
check  'mergeada.*PR #91' "nomeia o PR que provou" "$OUT"

echo
echo "== branch que de fato nunca subiu: o conselho de push continua =="
check 'sozinha.*(NUNCA foi ao GitHub|nenhum PR mergeado)' "sozinha segue acusada" "$OUT"
check 'push -u origin sozinha' "e o comando de push é o dela" "$OUT"

echo
echo "== gh sem acesso ao repo: não afirma o que não pode provar =="
# Recortar o PATH para um diretório vazio esconderia o gh e o *git* junto — o script
# morreria antes de imprimir aviso nenhum, e o refute passaria por vacuidade. O cenário
# que importa é o realista: gh instalado, mas sem enxergar o repositório (conta errada
# no keyring, token sem escopo). É o mesmo estado de "não tenho como perguntar".
mkdir -p "$TMP/bin-cego"
{
  echo '#!/usr/bin/env bash'
  echo 'case "$*" in'
  echo '  *"repo view"*) echo "GraphQL: Could not resolve to a Repository" >&2; exit 1 ;;'
  echo 'esac'
  echo 'exit 1'
} > "$TMP/bin-cego/gh"
chmod +x "$TMP/bin-cego/gh"
OUT_CEGO="$(rodar_com "$TMP/bin-cego" --no-pr)"
refute 'mergeada.*NUNCA foi ao GitHub' "gh cego: não afirma 'nunca foi'" "$OUT_CEGO"
check  'mergeada.*[Ss]em gh' "gh cego: diz que não deu para saber" "$OUT_CEGO"
check  'mergeada.*[Cc]onfira o PR' "gh cego: manda conferir antes de pushar" "$OUT_CEGO"

echo
echo "== conta ativa não enxerga o repo, outra do keyring enxerga: prova pela certa =="
# Específico do kit: a resolução de conta (duas contas no keyring) roda antes da
# varredura de branches, senão a consulta de PR sairia pela conta cega e o aviso cairia
# no "sem gh" num repo onde a prova estava a um token de distância.
mkdir -p "$TMP/bin-contas"
cat > "$TMP/bin-contas/gh" <<EOF
#!/usr/bin/env bash
tok="\${GH_TOKEN:-tok-pessoal}"
echo "\$*" >> "$TMP/gh-chamadas.log"
case "\$*" in
  "auth status"*)
    printf '%s\n' "github.com" \\
      "  ✓ Logged in to github.com account pessoal (keyring)" "  - Active account: true" \\
      "  ✓ Logged in to github.com account cliente (keyring)" "  - Active account: false"
    exit 0 ;;
  "auth token -u pessoal") echo tok-pessoal; exit 0 ;;
  "auth token -u cliente") echo tok-cliente; exit 0 ;;
esac
[ "\$tok" = tok-cliente ] || { echo "GraphQL: Could not resolve to a Repository" >&2; exit 1; }
case "\$*" in
  *"repo view"*) exit 0 ;;
  *"pr list"*"--head mergeada"*) echo "91 $SHA_MERGEADA"; exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/bin-contas/gh"
OUT_CONTAS="$(rodar_com "$TMP/bin-contas")"
check  'conta gh: cliente' "usou a conta que enxerga" "$OUT_CONTAS"
check  'mergeada.*PR #91' "provou o merge pela conta certa" "$OUT_CONTAS"
refute 'mergeada.*[Ss]em gh' "não cai no 'sem gh'" "$OUT_CONTAS"

echo
echo "== --no-pr: a mesma prova, com a conta resolvida só quando o aviso precisa =="
# --no-pr pula a seção de PRs, não a prova do aviso: sem resolver a conta aqui, a
# consulta ia pela ativa (cega) e o aviso dizia 'sem gh' com a prova a um token.
OUT_NOPR="$(rodar_com "$TMP/bin-contas" --no-pr)"
check  'mergeada.*PR #91' "--no-pr: provou o merge pela conta certa" "$OUT_NOPR"
refute 'mergeada.*[Ss]em gh' "--no-pr: não cai no 'sem gh'" "$OUT_NOPR"
refute 'PRs abertos' "--no-pr: a seção de PRs continua de fora" "$OUT_NOPR"
# Nenhuma conta enxerga: nada é exportado, e sem a guarda cada branch que cai no aviso
# (mergeada e sozinha) refaria o giro pelo keyring inteiro.
mkdir -p "$TMP/bin-ninguem"
sed 's/= tok-cliente ]/= ninguem ]/' "$TMP/bin-contas/gh" > "$TMP/bin-ninguem/gh"
chmod +x "$TMP/bin-ninguem/gh"
: > "$TMP/gh-chamadas.log"
OUT_NINGUEM="$(rodar_com "$TMP/bin-ninguem" --no-pr)"
n_status="$(grep -c '^auth status' "$TMP/gh-chamadas.log" 2>/dev/null || true)"
check '^1$' "--no-pr: sem conta que enxergue, o keyring é varrido uma vez só (foram ${n_status:-0})" "${n_status:-0}"
check 'mergeada.*[Ss]em gh' "--no-pr: e aí sim diz que não deu para saber" "$OUT_NINGUEM"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
