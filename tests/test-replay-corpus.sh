#!/usr/bin/env bash
# O scripts/replay-corpus.sh compara a decisão do pre-bash do base com a do head e só passa
# divergência declarada no PR?
#
# Sem rede e sem o corpus real: o base e o head são cópias de plugin/ deste repo, e a
# divergência é plantada trocando o check-careful da cópia head por um que bloqueia tudo.
# O corpus público (tests/corpus/comandos.jsonl) é conferido no formato, não replayado
# inteiro aqui: o passo do CI que roda o replay cuida disso quando o PR toca hook.
#
# Uso: bash tests/test-replay-corpus.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
S="$RAIZ/scripts/replay-corpus.sh"
C="$RAIZ/tests/corpus/comandos.jsonl"
T="$(mktemp -d "${TMPDIR:-/tmp}/replay-corpus-teste.XXXXXX")"; trap 'rm -rf "$T"' EXIT
falhas=0
check() { if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"; else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi; }
[ -f "$S" ] || { echo "  FALHA $S não existe"; exit 1; }

cp -R "$RAIZ/plugin" "$T/base"
cp -R "$RAIZ/plugin" "$T/head"
MARCA="$T/executou"
python3 - "$T/corpus.jsonl" "$MARCA" <<'PY'
import json, sys
cmds = ["echo ok", "git status", "git push --force origin main", f"touch {sys.argv[2]}"]
open(sys.argv[1], "w").write("".join(json.dumps({"command": c}) + "\n" for c in cmds))
PY

echo "== base e head iguais =="
out="$(bash "$S" --base-dir "$T/base" --head-dir "$T/head" --corpus "$T/corpus.jsonl" 2>&1)"; rc=$?
check "sai 0 (rc=$rc)" "$([ "$rc" = 0 ] && echo ok || { printf '%s\n' "$out" >&2; echo fail; })"
check "diz 0 divergências" "$(printf '%s' "$out" | grep -q '0 divergências' && echo ok || echo fail)"
check "conta os 4 comandos" "$(printf '%s' "$out" | grep -q 'replay: 4 comandos' && echo ok || echo fail)"
check "nenhum comando do corpus foi executado" "$([ ! -e "$MARCA" ] && echo ok || echo fail)"

echo "== divergência plantada no head =="
printf '#!/usr/bin/env bash\ncat >/dev/null\necho "plantado" >&2\nexit 2\n' > "$T/head/hooks/check-careful.sh"
out="$(bash "$S" --base-dir "$T/base" --head-dir "$T/head" --corpus "$T/corpus.jsonl" --fires "$T/fires.tsv" 2>&1)"; rc=$?
check "sai 1 (rc=$rc)" "$([ "$rc" = 1 ] && echo ok || { printf '%s\n' "$out" >&2; echo fail; })"
check "lista 'passa → bloqueia' para o echo ok" "$(printf '%s' "$out" | grep -qF 'passa → bloqueia  echo ok' && echo ok || echo fail)"
check "pede a seção ## Divergências do replay" "$(printf '%s' "$out" | grep -qF '## Divergências do replay' && echo ok || echo fail)"
check "--fires grava base, head e comando" "$(grep -qxF "$(printf 'passa\tbloqueia\techo ok')" "$T/fires.tsv" 2>/dev/null && echo ok || echo fail)"

echo "== corpo do PR =="
printf 'Resumo.\n\n## Para o CHANGELOG\n- x\n' > "$T/corpo-sem.md"
printf 'Resumo.\n\n## Divergências do replay\nO check-careful passa a bloquear tudo, de propósito.\n' > "$T/corpo-com.md"
bash "$S" --base-dir "$T/base" --head-dir "$T/head" --corpus "$T/corpus.jsonl" --corpo-pr "$T/corpo-sem.md" >/dev/null 2>&1; rc=$?
check "corpo sem a seção: continua 1 (rc=$rc)" "$([ "$rc" = 1 ] && echo ok || echo fail)"
out="$(bash "$S" --base-dir "$T/base" --head-dir "$T/head" --corpus "$T/corpus.jsonl" --corpo-pr "$T/corpo-com.md" 2>&1)"; rc=$?
check "corpo com a seção: sai 0 com aviso (rc=$rc)" "$([ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'declara as divergências' && echo ok || echo fail)"

echo "== sem base: só a contagem do head =="
out="$(bash "$S" --head-dir "$T/base" --corpus "$T/corpus.jsonl" 2>&1)"; rc=$?
check "sai 0 e conta por decisão (rc=$rc)" "$([ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^replay: 4 comandos · head: ' && echo ok || echo fail)"

echo "== erros de uso =="
bash "$S" --base ref-que-nao-existe-xyz --corpus "$T/corpus.jsonl" >/dev/null 2>&1; rc=$?
check "ref inexistente sai 2 (rc=$rc)" "$([ "$rc" = 2 ] && echo ok || echo fail)"
: > "$T/vazio.jsonl"
bash "$S" --head-dir "$T/base" --corpus "$T/vazio.jsonl" >/dev/null 2>&1; rc=$?
check "corpus vazio sai 2 (rc=$rc)" "$([ "$rc" = 2 ] && echo ok || echo fail)"
bash "$S" --base HEAD --base-dir "$T/base" --corpus "$T/corpus.jsonl" >/dev/null 2>&1; rc=$?
check "--base com --base-dir sai 2 (rc=$rc)" "$([ "$rc" = 2 ] && echo ok || echo fail)"

echo "== corpus público =="
check "existe e cada linha é {\"command\": texto}" "$(python3 - "$C" <<'PY' && echo ok || echo fail
import json, sys
n = 0
for l in open(sys.argv[1], encoding="utf-8"):
    if not l.strip(): continue
    d = json.loads(l); assert isinstance(d.get("command"), str) and d["command"]; n += 1
sys.exit(0 if n >= 100 else 1)
PY
)"
check "sem caminho de máquina nem e-mail real" "$(grep -qE '/Users/|/home/[a-z]|@[a-z0-9-]+\.(com|br|io)' "$C" && echo fail || echo ok)"

echo
[ "$falhas" -eq 0 ] && echo "tudo verde" || { echo "$falhas falha(s)"; exit 1; }
