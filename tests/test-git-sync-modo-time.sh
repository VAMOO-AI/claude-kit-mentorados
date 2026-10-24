#!/usr/bin/env bash
# Prova da ativação e da janela do modo time no plugin/skills/git-sync/scripts/git-sync.sh.
#
# Três coisas que o kit do time já fazia e o script daqui não:
#   - a auto-detecção conta autores por NOME. Uma pessoa só que commita ora com o e-mail
#     pessoal, ora com o noreply do GitHub não é um time; contada por "nome <e-mail>", ligava
#     o modo time num repo de uma pessoa só e enchia o relatório de seção vazia;
#   - `--since` que não é número sai com exit 2 e diz o que recebeu. Antes, `--since abc`
#     virava a janela "abc days ago", que o git e o date entendem como zero ou erro, e a seção
#     de branches ativas saía vazia sem motivo;
#   - os PRs mergeados da janela vêm filtrados NO SERVIDOR (`--search "merged:>=<data>"`).
#     Sem isso, o `--limit 30` devolve os 30 mais recentes de qualquer época e o filtro de
#     data, feito depois, perde o que passou dos 30 num repo movimentado.
#
# Uso: bash tests/test-git-sync-modo-time.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-time.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
cd "$CLONE" || exit 2
git config user.name "Ana"; git config user.email ana@pessoal.example; git config commit.gpgsign false
echo a > a.txt; git add a.txt; git commit -qm "um"
git branch -M main; git remote add origin "$ORIGIN"; git push -qu origin main
# a mesma pessoa, agora com o noreply do GitHub
echo b > b.txt; git add b.txt
git -c user.email=123+ana@users.noreply.github.com commit -qm "dois"
git push -q origin main

# gh falso: grava cada chamada e devolve lista vazia
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$*" in
  "repo view"*) exit 0 ;;
  "api user"*) echo ana; exit 0 ;;
  "pr list"*) exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"
export GH_LOG="$TMP/gh.log"
rodar() { env -u GH_TOKEN -u GITHUB_TOKEN PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$CLONE" --status-only "$@" 2>&1; }

echo "== uma pessoa com dois e-mails não liga o modo time =="
OUT="$(rodar --no-pr)"
check  'team: +off \(auto\)'       "auto-detecção fica desligada"        "$OUT"
check  '1 autor'                  "conta uma pessoa"                    "$OUT"
refute '### time'                 "a seção do time não aparece"         "$OUT"

echo
echo "== duas pessoas ligam o modo time =="
echo c > c.txt; git add c.txt
git -c user.name=Bia -c user.email=bia@example.com commit -qm "tres"
git push -q origin main
OUT="$(rodar --no-pr)"
check  'team: +ON \(auto\)'        "auto-detecção liga"                  "$OUT"
check  '2 autor'                  "conta duas pessoas"                  "$OUT"

echo
echo "== --since que não é número sai 2 e diz o que recebeu =="
OUT="$(rodar --no-pr --since abc)"; rc=$?
[ "$rc" -eq 2 ] && printf '  ok    %s\n' "exit 2" || { printf '  FALHA %s (saiu %s)\n' "exit 2" "$rc"; falhas=$((falhas+1)); }
check  "since.*abc"               "a mensagem cita o valor recebido"    "$OUT"
refute '### checkouts'            "não chega a montar o relatório"      "$OUT"

echo
echo "== PRs mergeados da janela: filtro no servidor =="
: > "$GH_LOG"
OUT="$(rodar --team --since 7)"
merged="$(grep -- '--state merged' "$GH_LOG" || true)"
check  'pr list'                  "consulta os PRs mergeados"           "$merged"
check  'search merged:>=[0-9]{4}-[0-9]{2}-[0-9]{2}' "filtra pela data no servidor" "$merged"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
