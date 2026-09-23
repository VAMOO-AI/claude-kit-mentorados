#!/usr/bin/env bash
# Prova do --voltar-main do plugin/skills/git-sync/scripts/git-sync.sh.
#
# A funcionalidade veio da linhagem de 10/09 que rodava fora do repo (issue
# claude-config-team#175), onde era comportamento PADRÃO. Voltou como flag: trocar a
# branch do checkout de alguém no fim de um comando que a pessoa chamou para LER estado é
# ação que ninguém pediu, e com duas sessões no mesmo clone a última a rodar decidiria em
# que branch a outra está.
#
# O que este teste garante:
#   - sem a flag, nada muda (é isso que separa opt-in de comportamento novo);
#   - com a flag, volta para a default e faz ff-only;
#   - --status-only nunca troca HEAD, mesmo com a flag;
#   - cada guarda ABORTA e explica: dirty tracked, operação git em andamento, detached;
#   - trabalho local à frente é preservado e vira aviso, nunca reset.
#
# Uso: bash tests/test-git-sync-voltar-main.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-voltar.XXXXXX")"
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
igual() { # <esperado> <descrição> <obtido>
  if [ "$1" = "$3" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$2" "$1" "$3"; falhas=$((falhas+1)); fi
}

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
git -C "$CLONE" config user.email t@t
git -C "$CLONE" config user.name t
git -C "$CLONE" config commit.gpgsign false
printf 'base\n' > "$CLONE/base.txt"
git -C "$CLONE" add base.txt
git -C "$CLONE" commit -qm base
git -C "$CLONE" branch -M main
git -C "$CLONE" remote add origin "$ORIGIN"
git -C "$CLONE" push -qu origin main

# gh falso e cego: o teste não depende do gh (nem da conta) de quem roda.
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

branch_atual() { git -C "$CLONE" rev-parse --abbrev-ref HEAD; }
rodar() { env -u GH_TOKEN -u GITHUB_TOKEN PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$CLONE" --no-pr --no-team "$@" 2>&1; }

echo "== sem a flag: o checkout fica onde estava =="
git -C "$CLONE" checkout -q -b feat/a
OUT="$(rodar)"
igual "feat/a" "não troca de branch sem --voltar-main" "$(branch_atual)"
refute 'retorno à branch principal' "nem imprime a seção" "$OUT"
check  'voltar_main=0 retorno=off' "o summary declara que está desligado" "$OUT"

echo
echo "== --status-only com a flag: relata e não toca em HEAD =="
OUT="$(rodar --voltar-main --status-only)"
igual "feat/a" "--status-only preserva o checkout" "$(branch_atual)"
check 'checkout preservado em feat/a' "diz que preservou" "$OUT"

echo
echo "== com a flag: volta para a default =="
OUT="$(rodar --voltar-main)"
igual "main" "voltou para main" "$(branch_atual)"
check 'feat/a → main' "nomeia a troca" "$OUT"
check 'retorno=ready' "o summary declara ready" "$OUT"

echo
echo "== guarda: alteração tracked pendente aborta e explica =="
git -C "$CLONE" checkout -q feat/a
printf 'sujo\n' >> "$CLONE/base.txt"
OUT="$(rodar --voltar-main)"
igual "feat/a" "dirty não perde a branch" "$(branch_atual)"
check 'BLOQUEADO: alterações tracked pendentes' "explica o motivo" "$OUT"
check 'retorno=blocked' "o summary declara blocked" "$OUT"
git -C "$CLONE" checkout -q -- base.txt

echo
echo "== guarda: operação git em andamento aborta =="
# `git -C X rev-parse --git-path` devolve caminho relativo ao cwd, não ao repo — foi
# assim que a guarda da linhagem de 10/09 passou a impressão de funcionar sem nunca
# disparar. Aqui o caminho do marcador é absoluto de propósito.
MERGE_HEAD_PATH="$(git -C "$CLONE" rev-parse --path-format=absolute --git-path MERGE_HEAD)"
: > "$MERGE_HEAD_PATH"
OUT="$(rodar --voltar-main)"
igual "feat/a" "merge em andamento não perde a branch" "$(branch_atual)"
check 'operação Git em andamento \(MERGE_HEAD\)' "nomeia o marcador" "$OUT"
rm -f "$MERGE_HEAD_PATH"

echo
echo "== guarda: detached HEAD é preservado =="
git -C "$CLONE" checkout -q --detach
OUT="$(rodar --voltar-main)"
check 'detached HEAD em .* preservado' "diz que preservou o detached" "$OUT"
igual "HEAD" "segue detached" "$(branch_atual)"
git -C "$CLONE" checkout -q main

echo
echo "== trabalho local à frente da remota é preservado, não resetado =="
git -C "$CLONE" checkout -q -b feat/b
printf 'novo\n' > "$CLONE/novo.txt"
git -C "$CLONE" add novo.txt
git -C "$CLONE" commit -qm "feat: novo"
git -C "$CLONE" checkout -q main
printf 'local\n' > "$CLONE/local.txt"
git -C "$CLONE" add local.txt
git -C "$CLONE" commit -qm "chore: commit local em main"
SHA_ANTES="$(git -C "$CLONE" rev-parse HEAD)"
OUT="$(rodar --voltar-main)"
igual "$SHA_ANTES" "commit local em main não foi resetado" "$(git -C "$CLONE" rev-parse HEAD)"
refute 'reset' "não fala de reset" "$OUT"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
