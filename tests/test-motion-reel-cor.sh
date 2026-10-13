#!/usr/bin/env bash
# Paleta da motion-reel: o template nasce neutro, e o new.sh grava a cor da pessoa.
#
# Até a 0.51.0 o acento do template era o azul #007dff / #4da3ff / #0063cc. Quem
# criava um projeto sem trocar o lib.tsx publicava essa cor. Este teste prova:
#   1. esses três hex não aparecem no texto da skill (template, referências, scripts);
#   2. new.sh --cor grava brand e --cor-escura grava accentFill, sem pintar o resto;
#   3. hex que não é #rrggbb recusa, sem criar o projeto.
#
# O new.sh de verdade roda npm ci e a trilha. Aqui o npm e o python são falsos:
# o que se prova é a cópia do template e a troca no lib.tsx.
#
# Uso: bash tests/test-motion-reel-cor.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SK="$RAIZ/plugin/skills/motion-reel"
NEW="$SK/scripts/new.sh"
[ -f "$NEW" ] || { echo "new.sh não encontrado em $NEW"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

echo "1. o template e o resto da skill não trazem o azul antigo"
achou="$(/usr/bin/grep -rniE '#007dff|#0063cc|#4da3ff' "$SK" \
  --exclude-dir=node_modules --exclude=package-lock.json \
  --include='*.tsx' --include='*.ts' --include='*.js' --include='*.mjs' \
  --include='*.md' --include='*.py' --include='*.sh' --include='*.json' 2>/dev/null || true)"
if [ -z "$achou" ]; then check "sem #007dff, #0063cc e #4da3ff na skill" ok
else check "sem #007dff, #0063cc e #4da3ff na skill" fail; printf '%s\n' "$achou" | sed 's/^/        /' | head -20; fi

# Grafite sobre papel e grafite claro sobre night: o template precisa das três chaves.
lib="$SK/assets/template/src/lib.tsx"
check "brand é grafite escuro" "$(/usr/bin/grep -q 'brand: "#3f3f46"' "$lib" && echo ok || echo fail)"
check "brandOnDark é grafite claro" "$(/usr/bin/grep -q 'brandOnDark: "#d4d4d8"' "$lib" && echo ok || echo fail)"
check "accentFill é preto de preenchimento" "$(/usr/bin/grep -q 'accentFill: "#18181b"' "$lib" && echo ok || echo fail)"

echo "2. new.sh --cor aplica no lib.tsx do projeto novo"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-cor.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/npm" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$BIN/python-falso" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$BIN/npm" "$BIN/python-falso"
export MOTION_PY="$BIN/python-falso"
P="$TMP/pasta marca"
PATH="$BIN:$PATH" bash "$NEW" --cor '#112233' --cor-escura '#0a0a0a' "$P" > "$TMP/2.log" 2>&1; rc=$?
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/2.log"
check "brand recebe --cor" "$(/usr/bin/grep -q 'brand: "#112233"' "$P/src/lib.tsx" && echo ok || echo fail)"
check "accentFill recebe --cor-escura" "$(/usr/bin/grep -q 'accentFill: "#0a0a0a"' "$P/src/lib.tsx" && echo ok || echo fail)"
check "brandOnDark continua o do template" "$(/usr/bin/grep -q 'brandOnDark: "#d4d4d8"' "$P/src/lib.tsx" && echo ok || echo fail)"
check "paper não é pintado com --cor" "$(/usr/bin/grep -q 'paper: "#112233"' "$P/src/lib.tsx" && echo fail || echo ok)"

P2="$TMP/so cor"
PATH="$BIN:$PATH" bash "$NEW" --cor '#abcdef' "$P2" > "$TMP/2b.log" 2>&1; rc=$?
check "só --cor sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "só --cor grava o brand" "$(/usr/bin/grep -q 'brand: "#abcdef"' "$P2/src/lib.tsx" && echo ok || echo fail)"
check "sem --cor-escura o accentFill fica o do template" "$(/usr/bin/grep -q 'accentFill: "#18181b"' "$P2/src/lib.tsx" && echo ok || echo fail)"

echo "3. hex inválido recusa"
for ruim in 'azul' '#12' '#1122333' '#GGGGGG' '112233' '#11223g'; do
  PATH="$BIN:$PATH" bash "$NEW" --cor "$ruim" "$TMP/nao-cria-$ruim" > "$TMP/ruim.log" 2>&1; rc=$?
  if [ "$rc" != 0 ] && /usr/bin/grep -q 'cor inválida' "$TMP/ruim.log" && [ ! -d "$TMP/nao-cria-$ruim" ]; then
    check "recusa $ruim" ok
  else
    check "recusa $ruim (rc=$rc)" fail
    sed 's/^/        /' "$TMP/ruim.log" | head -5
  fi
done
PATH="$BIN:$PATH" bash "$NEW" --cor '#112233' --cor-escura 'azul' "$TMP/escura-ruim" > "$TMP/escura.log" 2>&1; rc=$?
check "--cor-escura inválida recusa (veio $rc)" "$([ "$rc" != 0 ] && /usr/bin/grep -q 'cor inválida' "$TMP/escura.log" && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
