#!/usr/bin/env bash
# Prova de regressão da detecção de conta errada no plugin/skills/git-sync/scripts/git-sync.sh.
#
# Máquina com duas contas no keyring do gh (pessoal + trabalho/cliente) autentica numa só.
# Ao rodar git-sync no repo da outra, o gh responde "Could not resolve to a Repository" —
# lê como repo inexistente, não como conta errada, e o relatório saía cego para PR sem
# dizer o motivo (03/09/2026: `gh pr list` dando 404 numa máquina com a conta de outra
# pessoa ativa). O script agora testa as demais contas de `gh auth status` e usa a que
# enxerga, só neste processo; se nenhuma enxerga, diz isso com todas as letras.
#
# Cobre também os avisos "branch gone" e "dirty na default", e o ATENÇÃO do summary.
#
# Uso: bash tests/test-git-sync-conta.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-conta.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}

# --- fixture: origin + clone com uma branch cujo remoto sumiu -----------------
ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
cd "$CLONE"
git config user.email t@t; git config user.name t; git config commit.gpgsign false
echo base > base.txt; git add base.txt; git commit -qm base
git branch -M main; git remote add origin "$ORIGIN"; git push -qu origin main
git checkout -qb morta
echo m > m.txt; git add m.txt; git commit -qm "morta"
git push -qu origin morta
git checkout -q main
git worktree add -q "$TMP/wt-morta" morta
git push -q origin --delete morta >/dev/null 2>&1
git fetch -q --prune origin

# --- gh falso: só a conta 'cliente' enxerga o repo; a ativa é 'pessoal' -------
# FAKE_GH_ACTIVE: token da conta ativa quando GH_TOKEN não está exportado.
# FAKE_GH_NONE=1: nenhuma conta enxerga o repo.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
tok="${GH_TOKEN:-${FAKE_GH_ACTIVE:-tok-pessoal}}"
sees() { [ -z "${FAKE_GH_NONE:-}" ] && [ "$tok" = "tok-cliente" ]; }
# FAKE_GH_FALHA_1A=<arquivo>: a 1ª consulta do processo falha como instabilidade (a
# conta enxerga, a rede não respondeu); as seguintes seguem a regra normal.
if [ -n "${FAKE_GH_FALHA_1A:-}" ] && [ ! -e "$FAKE_GH_FALHA_1A" ] && [[ "$*" == "repo view"* ]]; then
  : > "$FAKE_GH_FALHA_1A"; echo "Post \"https://api.github.com/graphql\": net/http: TLS handshake timeout" >&2; exit 1
fi
nao_ve() { echo "GraphQL: Could not resolve to a Repository with the name 'cliente/app'. (repository)" >&2; exit 1; }
case "$*" in
  "auth status"*)
    ap=true; ac=false; [ "${FAKE_GH_ACTIVE:-tok-pessoal}" = tok-cliente ] && { ap=false; ac=true; }
    printf '%s\n' "github.com" \
      "  ✓ Logged in to github.com account pessoal (keyring)" "  - Active account: $ap" \
      "  ✓ Logged in to github.com account cliente (keyring)" "  - Active account: $ac"
    exit 0 ;;
  "auth token -u pessoal") echo tok-pessoal; exit 0 ;;
  "auth token -u cliente") echo tok-cliente; exit 0 ;;
  "repo view"*) sees && exit 0; nao_ve ;;
  "pr list"*) sees || nao_ve; echo "7  feat: coisa  feat/coisa"; exit 0 ;;
  "api user"*) sees && { echo cliente; exit 0; }; echo pessoal; exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"

# `env -u`: a máquina de quem mexe no kit costuma ter GH_TOKEN exportado (o próprio
# git-sync manda usar `export GH_TOKEN=$(gh auth token -u …)` em repo de cliente), e o
# script pula TODA a resolução de conta quando o token já vem do ambiente — que é o
# comportamento certo dele e o objeto de um dos casos abaixo. Sem limpar aqui, 7 dos 17
# checks falhavam por causa do ambiente, não do código, e a suíte passava só no CI.
run() { env -u GH_TOKEN -u GITHUB_TOKEN PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$CLONE" --status-only "$@" 2>&1; }
run_com_token() { # <token> [args…] — prova a precedência do GH_TOKEN da pessoa
  local tok="$1"; shift
  env -u GITHUB_TOKEN GH_TOKEN="$tok" PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$CLONE" --status-only "$@" 2>&1
}

echo "== conta ativa não enxerga o repo: usa a outra e avisa =="
OUT="$(FAKE_GH_ACTIVE=tok-pessoal run)"
check 'conta gh: cliente — a ativa não enxerga este repositório' "avisa qual conta foi usada"      "$OUT"
check '#?7  feat: coisa'                                          "lista o PR pela conta certa"     "$OUT"
refute 'gh pr list falhou'                                        "não reporta falha"               "$OUT"
refute 'tok-'                                                     "token não vaza na saída"         "$OUT"
# 24/09/2026: trocar a conta ativa da máquina é decisão de quem usa, não dica do relatório —
# a outra conta entra só por processo, e é isso que a nota ensina para o `gh` na mão.
refute 'gh auth switch'                                           "não sugere trocar a conta ativa" "$OUT"
check 'GH_TOKEN=\$\(gh auth token -u cliente\)'                   "ensina o token por processo"     "$OUT"

echo "== conta ativa enxerga o repo: caminho rápido, sem nota =="
OUT="$(FAKE_GH_ACTIVE=tok-cliente run)"
refute 'conta gh:'                                                "sem nota de conta"               "$OUT"
check '#?7  feat: coisa'                                          "lista o PR"                      "$OUT"

echo "== ativa enxerga, mas a 1ª consulta falhou por instabilidade: não manda trocar de conta =="
# 23/09/2026: a nota disse "a ativa não enxerga; gh auth switch -u ruannmiranda1" com
# ruannmiranda1 JÁ ativa. O retry pelas contas começa em ordem alfabética, a própria ativa
# passou, e a nota atribuiu a uma conta errada o que era rede.
OUT="$(FAKE_GH_ACTIVE=tok-cliente FAKE_GH_FALHA_1A="$TMP/falhou-1a" run)"; rm -f "$TMP/falhou-1a"
refute 'a ativa não enxerga'                                      "não culpa a conta ativa"         "$OUT"
refute 'gh auth switch'                                           "não sugere trocar de conta"      "$OUT"
check 'instabilidade'                                             "diz que foi instabilidade"       "$OUT"
check '#?7  feat: coisa'                                          "lista o PR pela ativa"           "$OUT"

echo "== nenhuma conta enxerga: diz isso, não 'repo inexistente' =="
OUT="$(FAKE_GH_NONE=1 run)"
check 'nenhuma conta do gh enxerga'                               "explica que é conta, não repo"   "$OUT"
check "gh auth login"                                             "aponta o próximo passo"          "$OUT"
check 'gh pr list falhou'                                         "ainda reporta a falha do pr list" "$OUT"

echo "== GH_TOKEN exportado pelo usuário tem precedência =="
# GH_TOKEN vai DENTRO do env do script (o run limpa o herdado antes), então o que se
# testa é o token que a pessoa passou, não o que a máquina tinha.
OUT="$(FAKE_GH_ACTIVE=tok-pessoal run_com_token tok-cliente)"
refute 'conta gh:'                                                "não procura conta com GH_TOKEN"  "$OUT"
check '#?7  feat: coisa'                                          "usa o token do usuário"          "$OUT"

echo "== --no-pr --cleanup-dry-run ainda avisa a conta =="
OUT="$(FAKE_GH_ACTIVE=tok-pessoal run --no-pr --cleanup-dry-run)"
check '### cleanup candidates'                                    "seção de cleanup presente"       "$OUT"
check 'conta gh: cliente'                                         "nota aparece no cleanup"         "$OUT"

echo "== avisos: branch gone e dirty na default =="
echo sujo >> "$CLONE/base.txt"
OUT="$(FAKE_GH_ACTIVE=tok-cliente run --no-pr)"
check 'morta \(.*wt-morta\): upstream sumiu do remoto \(branch gone\)' "branch gone vira aviso"      "$OUT"
check 'main \(.*clone\): alterações não commitadas direto na branch compartilhada' "dirty na default vira aviso" "$OUT"
check 'ATENÇÃO: [0-9]+ aviso\(s\)'                                "summary grita"                   "$OUT"
check 'avisos=[1-9]'                                              "summary conta os avisos"         "$OUT"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
