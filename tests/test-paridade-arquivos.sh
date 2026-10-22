#!/usr/bin/env bash
# A comparação de conteúdo do paridade.sh olha o hash dos arquivos de skill e hook
# que existem nos dois lados, diz qual lado é mais novo pela data do commit e
# não trata exceção de propósito (scripts/paridade.ignore) como divergência.
#
# As duas fixtures são repositórios git de mentira: um no layout do kit
# (plugin/skills, plugin/hooks) e outro no layout do time (skills, hooks).
#
# Uso: bash tests/test-paridade-arquivos.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$RAIZ/scripts/paridade.sh"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
[ -f "$RAIZ/scripts/paridade.ignore" ] || { echo "paridade.ignore não encontrado"; exit 2; }

falhas=0
check() { # <regex> <descrição> <texto>
  if printf '%s\n' "$3" | grep -qE "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() {
  if printf '%s\n' "$3" | grep -qE "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/paridade-arq.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

KIT="$TMP/kit"
TIME="$TMP/time"
mkdir -p \
  "$KIT/plugin/skills/alpha" \
  "$KIT/plugin/skills/baseline" \
  "$KIT/plugin/skills/so-kit" \
  "$KIT/plugin/skills/motion-reel/assets/logos" \
  "$KIT/plugin/hooks" \
  "$TIME/skills/alpha" \
  "$TIME/skills/vamoo-baseline" \
  "$TIME/skills/so-time" \
  "$TIME/skills/motion-reel/assets/logos" \
  "$TIME/hooks"

printf 'igual\n' > "$KIT/plugin/skills/alpha/SKILL.md"
printf 'igual\n' > "$TIME/skills/alpha/SKILL.md"
printf 'texto do kit\n' > "$KIT/plugin/skills/alpha/nota.txt"
printf 'texto do time\n' > "$TIME/skills/alpha/nota.txt"
printf 'velho no kit\n' > "$KIT/plugin/skills/alpha/do-time.txt"
printf 'base no time\n' > "$TIME/skills/alpha/do-time.txt"
printf 'só no kit\n' > "$KIT/plugin/skills/alpha/extras.txt"
printf 'base kit\n' > "$KIT/plugin/skills/baseline/SKILL.md"
printf 'base time\n' > "$TIME/skills/vamoo-baseline/SKILL.md"
printf 'órfã\n' > "$KIT/plugin/skills/so-kit/SKILL.md"
printf 'órfã\n' > "$TIME/skills/so-time/SKILL.md"
printf 'KITMARCA\n' > "$KIT/plugin/skills/motion-reel/assets/logos/marca.png"
printf 'TIMEMARCA\n' > "$TIME/skills/motion-reel/assets/logos/marca.png"
printf 'igual\n' > "$KIT/plugin/skills/motion-reel/comum.txt"
printf 'igual\n' > "$TIME/skills/motion-reel/comum.txt"
printf 'hook igual\n' > "$KIT/plugin/hooks/pre-bash.sh"
printf 'hook igual\n' > "$TIME/hooks/pre-bash.sh"
printf 'hook kit\n' > "$KIT/plugin/hooks/branch-guard.sh"
printf 'hook time\n' > "$TIME/hooks/branch-guard.sh"
printf 'só hook kit\n' > "$KIT/plugin/hooks/so-kit.sh"

git_init() {
  git -C "$1" init -q
  git -C "$1" config user.email t@t
  git -C "$1" config user.name t
  git -C "$1" config commit.gpgsign false
}
commit_em() { # data repo mensagem
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$2" add -A
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$2" commit -qm "$3"
}
git_init "$KIT"
git_init "$TIME"
commit_em "2026-10-10T12:00:00Z" "$KIT" "kit"
commit_em "2026-09-01T12:00:00Z" "$TIME" "time base"
printf 'novo no time\n' > "$TIME/skills/alpha/do-time.txt"
commit_em "2026-10-12T12:00:00Z" "$TIME" "time atualiza do-time"

echo "== saída legível =="
OUT="$(bash "$SCRIPT" --arquivos --kit "$KIT" --time "$TIME" 2>&1)"
code=$?
check '^divergiu .*skill/alpha/nota.txt .*mais novo: kit' "nota.txt divergiu e o kit é mais novo" "$OUT"
check '^divergiu .*skill/alpha/do-time.txt .*mais novo: time' "do-time.txt divergiu e o time é mais novo" "$OUT"
check '^divergiu .*skill/baseline/SKILL.md .*mais novo: kit' "vamoo-baseline casa com baseline" "$OUT"
check '^divergiu .*hook/branch-guard.sh .*mais novo: kit' "hook divergente aponta o kit" "$OUT"
check '^divergiu .*skill/alpha/extras.txt' "arquivo só num lado da skill compartilhada aparece" "$OUT"
DIV="$(printf '%s\n' "$OUT" | grep '^divergiu' || true)"
refute 'marca\.png' "marca.png ignorada não entra como divergência" "$DIV"
refute 'so-kit' "skill que só existe aqui não é divergência de conteúdo" "$DIV"
refute 'pre-bash' "arquivo igual não aparece" "$DIV"
if [ "$code" -eq 0 ]; then printf '  ok    exit 0 com divergência (o CI só avisa)\n'
else printf '  FALHA exit 0 com divergência (veio %s)\n' "$code"; falhas=$((falhas+1)); fi

echo "== --json =="
JSON="$(bash "$SCRIPT" --arquivos --json --kit "$KIT" --time "$TIME" 2>/dev/null)"
jcode=$?
if [ "$jcode" -eq 0 ]; then printf '  ok    --json sai 0\n'
else printf '  FALHA --json sai 0 (veio %s)\n' "$jcode"; falhas=$((falhas+1)); fi
export JSON
python3 - <<'PY' || falhas=$((falhas+1))
import json, os, sys
d = json.loads(os.environ["JSON"])
by = {(x["tipo"], x["nome"], x["arquivo"]): x for x in d["divergencias"]}
nota = by[("skill", "alpha", "nota.txt")]
assert nota["mais_novo"] == "kit", nota
assert nota["kit"]["commit"] == "2026-10-10", nota["kit"]
assert nota["time"]["commit"] == "2026-09-01", nota["time"]
assert nota["kit"]["sha256"] != nota["time"]["sha256"]
dot = by[("skill", "alpha", "do-time.txt")]
assert dot["mais_novo"] == "time", dot
assert dot["time"]["commit"] == "2026-10-12", dot
base = by[("skill", "baseline", "SKILL.md")]
assert base.get("nome_time") == "vamoo-baseline", base
ext = by[("skill", "alpha", "extras.txt")]
assert ext["time"] is None and ext["mais_novo"] == "kit", ext
assert d["iguais"] >= 2, d["iguais"]
assert d["ignorados"] >= 1, d["ignorados"]
blob = json.dumps(d["divergencias"])
assert "marca.png" not in blob
assert "so-kit" not in blob
print("  ok    json tem hash, data e o lado mais novo")
PY

echo "== time ausente sai 2 =="
code=0
bash "$SCRIPT" --arquivos --kit "$KIT" --time "$TMP/nao-existe" >/dev/null 2>&1 || code=$?
if [ "$code" -eq 2 ]; then printf '  ok    sem o clone sai 2\n'
else printf '  FALHA sem o clone sai 2 (veio %s)\n' "$code"; falhas=$((falhas+1)); fi

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
