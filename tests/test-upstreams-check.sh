#!/usr/bin/env bash
# O scripts/upstreams-check.sh separa "nada novo" de "não medido" e só abre issue quando há
# novidade? O `gh` daqui é de mentira: responde fixtures e aplica o `--jq` de verdade com o
# jq do sistema, então o filtro que o script manda para a API é o que está em teste.
#
# Uso: bash tests/test-upstreams-check.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$RAIZ/scripts/upstreams-check.sh"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente"; exit 2; }

falhas=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/upstreams.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
tem()     { case "$2" in *"$1"*) ok "$3" ;; *) falha "$3 (não achei '$1')" ;; esac; }
nao_tem() { case "$2" in *"$1"*) falha "$3 (achei '$1')" ;; *) ok "$3" ;; esac; }

FIX="$TMP/fix"; mkdir -p "$FIX" "$TMP/bin"
# `gh` de mentira. api <caminho> --jq <expr>: aplica <expr> à fixture do caminho (sem ela,
# sai 1 como a API fora do ar). issue list/create/edit: anota a chamada em calls.log.
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$FIX/calls.log"
if [ "$1" = api ]; then
  caminho="$2"; shift 2; expr="."
  while [ $# -gt 0 ]; do [ "$1" = --jq ] && expr="$2"; shift; done
  arq="$FIX/$(printf '%s' "${caminho%%\?*}" | tr '/' '_').json"
  [ -f "$arq" ] || { echo "HTTP 502" >&2; exit 1; }
  jq -r "$expr" "$arq"; exit $?
fi
if [ "$1 $2" = "issue list" ]; then
  shift 2; expr="."
  while [ $# -gt 0 ]; do [ "$1" = --jq ] && expr="$2"; shift; done
  jq -r "$expr" "${FIX}/issues.json"; exit $?
fi
exit 0
MOCK
chmod +x "$TMP/bin/gh"
export FIX PATH="$TMP/bin:$PATH"

cat > "$TMP/manifesto.json" <<'EOF'
{ "upstreams": [
  { "repo": "a/releases", "lido_em": "2026-10-01T00:00:00Z", "lido_versao": "v1.0.0", "tag": "^v", "commits_minimo": 0, "que_trouxemos": "ideia A" },
  { "repo": "b/commits", "lido_em": "2026-10-01T00:00:00Z", "lido_versao": "-", "tag": "^v", "commits_minimo": 3, "que_trouxemos": "ideia B" },
  { "repo": "c/parado", "lido_em": "2026-10-01T00:00:00Z", "lido_versao": "v2.0.0", "tag": "^v", "commits_minimo": 0, "que_trouxemos": "nada" }
] }
EOF
# a/releases: uma release nova que vale, uma antiga, um prerelease, um draft e uma tag fora
# do regex. b/commits: 4 commits (mínimo 3). c/parado: só release antiga.
cat > "$FIX/repos_a_releases_releases.json" <<'EOF'
[ {"tag_name":"v1.2.0","published_at":"2026-10-20T10:00:00Z","prerelease":false,"draft":false,"html_url":"https://x/v1.2.0"},
  {"tag_name":"v1.3.0-rc.1","published_at":"2026-10-21T10:00:00Z","prerelease":true,"draft":false,"html_url":"https://x/rc"},
  {"tag_name":"v1.4.0","published_at":"2026-10-22T10:00:00Z","prerelease":false,"draft":true,"html_url":"https://x/draft"},
  {"tag_name":"bin-v1.2.1","published_at":"2026-10-23T10:00:00Z","prerelease":false,"draft":false,"html_url":"https://x/bin"},
  {"tag_name":"v1.0.0","published_at":"2026-09-01T10:00:00Z","prerelease":false,"draft":false,"html_url":"https://x/v1.0.0"} ]
EOF
echo '[]' > "$FIX/repos_b_commits_releases.json"
echo '[{},{},{},{}]' > "$FIX/repos_b_commits_commits.json"
echo '[{"tag_name":"v2.0.0","published_at":"2026-09-30T23:59:59Z","prerelease":false,"draft":false,"html_url":"https://x/v2"}]' > "$FIX/repos_c_parado_releases.json"
echo '[]' > "$FIX/issues.json"

echo "== novidade: release filtrada e contagem de commits =="
out=$(bash "$SCRIPT" --manifesto "$TMP/manifesto.json" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "sai 0 com tudo medido" || falha "saiu $rc com tudo medido (esperado 0)"
tem "a/releases" "$out" "a/releases aparece"
tem "1 release(s)" "$out" "a/releases conta só a release estável nova com tag ^v"
tem "4 commit(s)" "$out" "b/commits conta os commits desde a leitura"
tem "c/parado                     nada novo desde 2026-10-01" "$out" "c/parado sai 'nada novo'"
tem "2 repo(s) com novidade, 0 não medido(s)" "$out" "resumo bate"
nao_tem "issue" "$(cat "$FIX/calls.log")" "sem --issue, nenhuma chamada de issue"

echo "== --issue sem issue aberta: cria, com o corpo do relatório =="
: > "$FIX/calls.log"
out=$(UPSTREAMS_REPO=dono/kit bash "$SCRIPT" --issue --manifesto "$TMP/manifesto.json" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "sai 0" || falha "saiu $rc (esperado 0)"
tem "issue create -R dono/kit --title upstreams: novidade para ler" "$(cat "$FIX/calls.log")" "abre a issue no repo do kit"

echo "== --issue com issue aberta de mesmo título: edita, não duplica =="
: > "$FIX/calls.log"
echo '[{"number":7,"title":"upstreams: novidade para ler"},{"number":9,"title":"upstreams: novidade para ler (velha)"}]' > "$FIX/issues.json"
out=$(UPSTREAMS_REPO=dono/kit bash "$SCRIPT" --issue --manifesto "$TMP/manifesto.json" 2>&1)
tem "issue edit 7 -R dono/kit --body-file" "$(cat "$FIX/calls.log")" "atualiza a #7"
nao_tem "issue create" "$(cat "$FIX/calls.log")" "não abre outra"

echo "== repo que a API não respondeu: não medido e exit 3, nunca 'nada novo' =="
: > "$FIX/calls.log"; echo '[]' > "$FIX/issues.json"
cat > "$TMP/m-erro.json" <<'EOF'
{ "upstreams": [ { "repo": "z/fora-do-ar", "lido_em": "2026-10-01T00:00:00Z", "tag": "", "commits_minimo": 0 } ] }
EOF
out=$(bash "$SCRIPT" --issue --manifesto "$TMP/m-erro.json" 2>&1); rc=$?
[ "$rc" -eq 3 ] && ok "sai 3" || falha "saiu $rc (esperado 3)"
tem "z/fora-do-ar                 não medido" "$out" "diz não medido"
nao_tem "nada novo" "$out" "não diz nada novo"
nao_tem "issue create" "$(cat "$FIX/calls.log")" "sem novidade medida, não abre issue"

echo "== manifesto ruim é erro de uso =="
echo '{}' > "$TMP/vazio.json"
bash "$SCRIPT" --manifesto "$TMP/vazio.json" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "manifesto sem .upstreams sai 2" || falha "saiu $rc (esperado 2)"

echo "== o manifesto do kit é válido =="
jq -e '.upstreams | length > 0 and all(.[]; (.repo | test("^[^/]+/[^/]+$")) and (.lido_em | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")) and has("que_trouxemos"))' \
  "$RAIZ/scripts/upstreams.json" >/dev/null && ok "todo item tem repo, lido_em ISO em UTC e que_trouxemos" \
  || falha "scripts/upstreams.json tem item sem repo, lido_em ISO em UTC ou que_trouxemos"

echo
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; exit 0; fi
echo "FALHOU ($falhas)"; exit 1
