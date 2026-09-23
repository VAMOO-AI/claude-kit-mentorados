#!/usr/bin/env bash
# O gate de spec reprova erro, tolera warning e não vira falso-verde quando a
# ferramenta não está instalada.
#
# O que se testa aqui é o NOSSO wrapper (scripts/skill-spec-check.sh), não o
# skill-validator: a régua de saída dele (0 limpo, 2 warnings, 1 erro) é o que a
# gente traduz, e traduzir errado dá os dois desastres — CI vermelho por conselho
# editorial, ou CI verde porque o binário não existia na máquina. Por isso a maior
# parte dos casos roda com um stub que só devolve o código de saída.
#
# Diferença para o kit do time: aqui as skills moram em plugin/skills, não em
# skills/. O wrapper sem argumento tem que apontar para lá — senão o gate valida uma
# pasta que não existe e o default vira armadilha para quem roda à mão.
#
# O último bloco é ponta a ponta e só roda quando o skill-validator real está
# instalado (é o caso do CI): fixture com frontmatter quebrado tem que reprovar.
#
# Uso: bash tests/test-skill-spec.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="$RAIZ/scripts/skill-spec-check.sh"
[ -f "$WRAPPER" ] || { echo "wrapper não encontrado: $WRAPPER"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/skill-spec.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/stub" "$TMP/skills/exemplo" "$TMP/go"
cat > "$TMP/skills/exemplo/SKILL.md" <<'MD'
---
name: exemplo
description: Skill de fixture, só existe para o wrapper ter uma pasta válida para apontar.
---

# Exemplo
MD

stub() { # stub <codigo-de-saida> — instala um skill-validator falso que sai com esse código
  cat > "$TMP/stub/skill-validator" <<STUB
#!/usr/bin/env bash
echo "stub do skill-validator (saída $1)"
echo "alvo: \${@: -1}"
exit $1
STUB
  chmod +x "$TMP/stub/skill-validator"
}

roda() { # roda <PATH> <strict> <alvo> — devolve o código de saída do wrapper
  PATH="$1" GOPATH="$TMP/go" HOME="$TMP" SKILL_SPEC_STRICT="$2" \
    bash "$WRAPPER" "$3" > "$TMP/saida.txt" 2>&1
  echo $?
}

SEM_BIN="/usr/bin:/bin:/usr/sbin:/sbin"
COM_STUB="$TMP/stub:$SEM_BIN"

echo "== a régua de saída do skill-validator =="
stub 0
check "saída 0 (limpo) passa"                    "$([ "$(roda "$COM_STUB" 0 "$TMP/skills")" = 0 ] && echo ok || echo fail)"
stub 2
check "saída 2 (só warnings) passa"              "$([ "$(roda "$COM_STUB" 0 "$TMP/skills")" = 0 ] && echo ok || echo fail)"
stub 1
check "saída 1 (erro de spec) reprova"           "$([ "$(roda "$COM_STUB" 0 "$TMP/skills")" = 1 ] && echo ok || echo fail)"
stub 3
check "saída inesperada reprova em vez de passar" "$([ "$(roda "$COM_STUB" 0 "$TMP/skills")" = 1 ] && echo ok || echo fail)"

echo "== sem argumento, o alvo é plugin/skills (não skills/, como no kit do time) =="
stub 0
PATH="$COM_STUB" GOPATH="$TMP/go" HOME="$TMP" SKILL_SPEC_STRICT=0 bash "$WRAPPER" > "$TMP/saida.txt" 2>&1
rc=$?
check "sem argumento valida plugin/skills" \
  "$([ "$rc" = 0 ] && grep -qxF "alvo: $RAIZ/plugin/skills" "$TMP/saida.txt" && echo ok || echo fail)"

echo "== ferramenta ausente não vira falso-verde =="
rc="$(roda "$SEM_BIN" 1 "$TMP/skills")"
check "sem binário e SKILL_SPEC_STRICT=1 reprova" "$([ "$rc" = 1 ] && echo ok || echo fail)"
check "e a mensagem diz como instalar"            "$(grep -q 'go install github.com/agent-ecosystem/skill-validator' "$TMP/saida.txt" && echo ok || echo fail)"

rc="$(roda "$SEM_BIN" 0 "$TMP/skills")"
check "sem binário e sem strict passa (máquina sem Go)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "e diz 'não executado' em vez de 'tudo verde'"    "$(grep -q 'não executado' "$TMP/saida.txt" && echo ok || echo fail)"

echo "== alvo inválido =="
stub 0
check "pasta inexistente reprova" "$([ "$(roda "$COM_STUB" 0 "$TMP/nao-existe")" = 1 ] && echo ok || echo fail)"

echo "== ponta a ponta (só com o skill-validator real) =="
real=""
command -v skill-validator > /dev/null 2>&1 && real="$(command -v skill-validator)"
[ -z "$real" ] && [ -x "$HOME/go/bin/skill-validator" ] && real="$HOME/go/bin/skill-validator"
if [ -z "$real" ]; then
  echo "  pulado (skill-validator não instalado nesta máquina)"
else
  mkdir -p "$TMP/quebrada/ruim"
  # A quebra é a real de 10/09/2026: ": " no meio de uma description sem aspas.
  cat > "$TMP/quebrada/ruim/SKILL.md" <<'MD'
---
name: ruim
description: Use quando algo acontecer. Triggers: "/ruim", "quebra o YAML".
---

# Ruim
MD
  PATH="$(dirname "$real"):$SEM_BIN" SKILL_SPEC_STRICT=1 \
    bash "$WRAPPER" "$TMP/quebrada" > "$TMP/saida.txt" 2>&1
  rc=$?
  check "frontmatter que não parseia como YAML reprova de verdade" "$([ "$rc" = 1 ] && echo ok || echo fail)"

  PATH="$(dirname "$real"):$SEM_BIN" SKILL_SPEC_STRICT=1 \
    bash "$WRAPPER" "$TMP/skills" > "$TMP/saida.txt" 2>&1
  rc=$?
  check "fixture válida passa de verdade" "$([ "$rc" = 0 ] && echo ok || echo fail)"
fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
