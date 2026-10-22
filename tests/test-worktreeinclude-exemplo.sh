#!/usr/bin/env bash
# O plugin/templates/worktreeinclude.exemplo copia o env ignorado e nada que guarde token
# de registry.
#
# Depois da 0.64 ele substituiu o hook worktree-seed-env.sh. O Claude Code copia para o worktree
# novo o que casa com um padrão do .worktreeinclude E é ignorado pelo git
# (https://code.claude.com/docs/en/worktrees.md). Então o teste confere as duas metades
# com o git de verdade, num repo com o gitignore.exemplo do kit:
#   - .env e .env.local casam com o modelo e são ignorados (seriam copiados);
#   - .env.example casa, mas é versionado (não seria copiado);
#   - .npmrc, bunfig.toml e .bunfig.toml não casam (o hook antigo também não copiava:
#     token de registry não se multiplica por conta do kit).
#
# Uso: bash tests/test-worktreeinclude-exemplo.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
MODELO="$RAIZ/plugin/templates/worktreeinclude.exemplo"
GI="$RAIZ/plugin/templates/gitignore.exemplo"
[ -f "$MODELO" ] || { echo "FALHA worktreeinclude.exemplo não encontrado em $RAIZ/plugin/templates"; exit 1; }
[ -f "$GI" ] || { echo "gitignore.exemplo não encontrado"; exit 2; }

falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q -b main
cp "$GI" "$REPO/.gitignore"
# Um segundo "gitignore" com os padrões do modelo: casar com ele é casar com o modelo.
INC="$TMP/include"; cp "$MODELO" "$INC"
casa_inc() { mkdir -p "$TMP/so-inc"; git -C "$TMP/so-inc" init -q 2>/dev/null; cp "$INC" "$TMP/so-inc/.gitignore"; git -C "$TMP/so-inc" check-ignore -q --no-index -- "$1"; }
ignorado() { git -C "$REPO" check-ignore -q --no-index -- "$1"; }

for f in .env .env.local .env.production; do
  if casa_inc "$f" && ignorado "$f"; then ok "$f casa com o modelo e é ignorado: o Claude Code copia"
  else falha "$f deveria casar com o modelo e ser ignorado"; fi
done
if casa_inc .env.example && ! ignorado .env.example; then ok ".env.example casa, mas é versionado: não é copiado"
else falha ".env.example: esperado casar com o modelo e NÃO ser ignorado pelo gitignore.exemplo"; fi
for f in .npmrc bunfig.toml .bunfig.toml; do
  if casa_inc "$f"; then falha "$f casa com o modelo (token de registry não se copia por conta do kit)"
  else ok "$f fica de fora"; fi
done
grep -q 'code.claude.com/docs/en/worktrees' "$MODELO" && ok "o modelo cita a doc" || falha "o modelo não cita a doc"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
