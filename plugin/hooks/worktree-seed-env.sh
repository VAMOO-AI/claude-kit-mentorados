#!/usr/bin/env bash
# Semeia o worktree novo com os `.env*` que o git ignora.
#
# O worktree nasce com o que está COMMITADO. O `.env.local` não está — e ninguém avisa: o
# `npm run dev` sobe, o app não acha a URL do Supabase, e a tela de login devolve "Failed
# to fetch". Nada ali diz "faltou env". No time isso custou dois diagnósticos no mesmo dia.
#
# Roda no UserPromptSubmit (via pre-prompt.sh), pelo mesmo motivo do
# memoria-worktree-link.sh: o worktree nasce NO MEIO da sessão, pelo EnterWorktree, e esse
# caminho não dispara SessionStart. O evento `WorktreeCreate` NÃO serve: é hook provedor,
# não aviso — configurado, o Claude Code para de criar o worktree e espera que o script o
# crie e imprima o caminho. Um hook que só copia env travaria worktree em todo repo.
#
# O que copia: `.env` e `.env.*` da raiz do clone principal que o git ignora nos DOIS lados
# (clone e branch do worktree) e que não estão no índice. Nunca sobrescreve, nunca imprime
# conteúdo. `.npmrc` e `.bunfig.toml` ignorados NÃO são copiados, só citados pelo nome: ali
# costuma morar token de registry, que vale para o pacote inteiro e não só para o app — o
# kit não multiplica essa credencial por conta própria.
#
# Só age num worktree deste repo, sob o `.claude/worktrees/` do clone principal — resolvido
# pelo `git rev-parse --git-common-dir`, não por recorte do caminho. Worktree criado à mão
# em outro lugar (`git worktree add ../x`) não recebe credencial por hook.
#
# Caminho quente: um teste de arquivo (o carimbo mora no git-dir do worktree e some com
# ele no `git worktree remove`). Falha-aberta; falha de cópia avisa e NÃO carimba, para
# tentar de novo no prompt seguinte.
set -u

case "$PWD" in
  */.claude/worktrees/*) ;;
  *) exit 0 ;;
esac

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$RAIZ" ] || exit 0

GITDIR="$(git -C "$RAIZ" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
COMUM="$(git -C "$RAIZ" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
[ -n "$GITDIR" ] && [ -n "$COMUM" ] || exit 0
# Worktree de verdade tem git-dir próprio; no clone principal os dois são o mesmo.
[ "$GITDIR" != "$COMUM" ] || exit 0

CARIMBO="$GITDIR/claude-seed-env"
[ -e "$CARIMBO" ] && exit 0

PRINCIPAL="${COMUM%/.git}"
[ "$PRINCIPAL" != "$COMUM" ] || exit 0
[ -d "$PRINCIPAL" ] || exit 0

case "$RAIZ" in
  "$PRINCIPAL"/.claude/worktrees/*) ;;
  *) exit 0 ;;
esac

# O arquivo é credencial do clone, não do repositório: fora do índice e ignorado lá.
fora_do_git_no_clone() {
  git -C "$PRINCIPAL" ls-files --error-unmatch -- "$1" >/dev/null 2>&1 && return 1
  git -C "$PRINCIPAL" check-ignore -q -- "$1" 2>/dev/null
}
# E ignorado também na branch do worktree. Só o lado do clone não basta: se a branch não
# ignora o arquivo, a cópia aparece como "untracked" e o próximo `git add .` publica o
# segredo.
ignorado_no_worktree() { git -C "$RAIZ" check-ignore -q -- "$1" 2>/dev/null; }

copiados=""; falhou=""; pulados=""; registry=""
for origem in "$PRINCIPAL"/.env "$PRINCIPAL"/.env.*; do
  [ -f "$origem" ] || continue
  nome="${origem##*/}"
  # Nunca sobrescrever: o worktree pode ter um env diferente de propósito.
  [ -e "$RAIZ/$nome" ] && continue
  fora_do_git_no_clone "$nome" || continue
  if ! ignorado_no_worktree "$nome"; then
    pulados="${pulados:+$pulados, }$nome"
    continue
  fi
  if cp -p "$origem" "$RAIZ/$nome" 2>/dev/null; then
    copiados="${copiados:+$copiados, }$nome"
  else
    falhou="${falhou:+$falhou, }$nome"
  fi
done
for nome in .npmrc .bunfig.toml; do
  [ -f "$PRINCIPAL/$nome" ] && [ ! -e "$RAIZ/$nome" ] && fora_do_git_no_clone "$nome" \
    && ignorado_no_worktree "$nome" && registry="${registry:+$registry, }$nome"
done

[ -n "$copiados" ] && echo "🔑 worktree novo: $copiados copiado(s) do clone principal (ignorados pelo git, conteúdo não lido)."
[ -n "$pulados" ] && echo "⚠️  não copiei $pulados: a branch deste worktree não ignora esse arquivo, e a cópia entraria no próximo commit. Ajuste o .gitignore da branch antes de copiar à mão."
[ -n "$registry" ] && echo "ℹ️  o clone principal tem $registry fora do git; não copiei (pode ter token de registry). Se o install falhar por autenticação, copie à mão."
if [ -n "$falhou" ]; then
  echo "⚠️  não consegui copiar do clone principal: $falhou — copie à mão antes de rodar o projeto."
  exit 0
fi

# node_modules fica de fora de propósito: instalar no worktree leva um minuto e é o certo;
# symlink entre worktrees quebra binário de .bin com caminho absoluto e faz dois worktrees
# disputarem o mesmo cache de browser do Playwright.
if [ -f "$RAIZ/package.json" ] && [ ! -e "$RAIZ/node_modules" ]; then
  echo "📦 sem node_modules aqui — rode o install do projeto (npm ci / bun install) antes de dev, teste ou npx. Não faça symlink do node_modules do clone principal."
fi

: > "$CARIMBO" 2>/dev/null
exit 0
