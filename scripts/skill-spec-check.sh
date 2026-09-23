#!/usr/bin/env bash
# A SKILL.md do kit é válida fora do Claude Code?
#
# Os dois gates de skill deste repo (tests/test-skill-descriptions.sh e
# tests/test-skill-sem-injecao.sh) cobrem o que nos custou dinheiro: teto de
# description e execução de shell no load. Nenhum dos dois lê o frontmatter como
# YAML — e o Claude Code é tolerante o bastante para carregar frontmatter que o
# parser YAML estrito rejeita.
#
# Achado de 10/09/2026 no kit do time, medido com o skill-validator: TRÊS skills
# (find-skills, harness-check, skills-projeto) tinham `description:` sem aspas com
# ": " no meio ("Triggers: ...", "Ordem fixa: ...", "procedência: ..."). YAML lê o
# segundo ":" como novo mapeamento e falha. Carregavam no Claude Code, quebrariam em
# harness que valida a spec. Aqui as três já estavam em bloco `>-` — o gate é para
# não regredir, e pesa mais: este é o kit que o mentorado instala, inclusive quem usa
# Codex ou Cursor.
#
# Ferramenta de CI, não vai para o aluno: fica em scripts/ na raiz, fora do plugin/.
#
# A ferramenta é externa (agent-ecosystem/skill-validator, MIT, Go). Por isso a
# versão fica PINADA aqui e no workflow: validador que muda de régua sozinho vira
# CI vermelho por motivo que ninguém pediu.
#
# Uso:
#   bash scripts/skill-spec-check.sh [pasta-de-skills ...]         # sem argumento: plugin/skills
#   SKILL_SPEC_STRICT=1 bash scripts/skill-spec-check.sh plugin/skills   # CI: binário ausente reprova
#
# Exit: 0 limpo ou só warnings · 1 erro de spec (ou binário ausente em modo estrito)
set -uo pipefail

SKILL_VALIDATOR_VERSION="v1.6.1"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
STRICT="${SKILL_SPEC_STRICT:-0}"

ALVOS=("$@")
[ "${#ALVOS[@]}" -gt 0 ] || ALVOS=("$RAIZ/plugin/skills")

instalar() {
  echo "  instale com: go install github.com/agent-ecosystem/skill-validator/cmd/skill-validator@$SKILL_VALIDATOR_VERSION"
  echo "  (o binário cai em \$(go env GOPATH)/bin)"
}

bin=""
if command -v skill-validator > /dev/null 2>&1; then
  bin="$(command -v skill-validator)"
elif command -v go > /dev/null 2>&1 && [ -x "$(go env GOPATH 2> /dev/null)/bin/skill-validator" ]; then
  bin="$(go env GOPATH)/bin/skill-validator"
elif [ -x "$HOME/go/bin/skill-validator" ]; then
  bin="$HOME/go/bin/skill-validator"
fi

if [ -z "$bin" ]; then
  if [ "$STRICT" = "1" ]; then
    echo "FALHA: skill-validator não está no PATH e SKILL_SPEC_STRICT=1"
    instalar
    exit 1
  fi
  echo "não executado: skill-validator não está no PATH — nenhuma skill foi validada contra a spec"
  instalar
  exit 0
fi

# --emit-annotations só faz sentido dentro do Actions; fora dele é ruído no terminal.
FLAGS=(check -o compact)
[ -n "${GITHUB_ACTIONS:-}" ] && FLAGS=(check -o compact --emit-annotations)

falhas=0
for alvo in "${ALVOS[@]}"; do
  if [ ! -d "$alvo" ]; then
    echo "FALHA: pasta de skills não encontrada: $alvo"
    falhas=$((falhas + 1))
    continue
  fi

  echo "== $alvo =="
  "$bin" "${FLAGS[@]}" "$alvo"
  rc=$?

  # A régua de saída do skill-validator: 0 limpo, 2 só warnings, 1 erro de spec.
  # Warning aqui é conselho editorial (tamanho de corpo, densidade) e quem manda
  # nisso é o test-skill-descriptions.sh, não uma ferramenta de fora — por isso
  # o 2 passa. Erro é frontmatter que não parseia: esse reprova.
  case "$rc" in
    0) echo "  ok    spec válida, sem apontamento" ;;
    2) echo "  ok    spec válida (só warnings — a régua de tamanho é nossa)" ;;
    1)
      echo "  FALHA erro de spec acima (frontmatter que não parseia como YAML)"
      falhas=$((falhas + 1))
      ;;
    *)
      echo "  FALHA skill-validator saiu com código inesperado ($rc)"
      falhas=$((falhas + 1))
      ;;
  esac
done

echo
if [ "$falhas" -eq 0 ]; then
  echo "tudo verde ($bin $SKILL_VALIDATOR_VERSION)"
else
  echo "$falhas pasta(s) com erro de spec"
  exit 1
fi
