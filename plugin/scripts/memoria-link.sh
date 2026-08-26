#!/usr/bin/env bash
# Liga a memória do Claude Code à memória versionada do projeto.
#
# O Claude escreve o que aprende em ~/.claude/projects/<slug>/memory — um lugar
# na SUA máquina, que ninguém mais vê. Quando o projeto tem `.context/memoria/`,
# esse diretório vira um symlink pra lá, e tudo que for registrado a partir daí
# nasce dentro do repositório: entra no commit, vai pro GitHub, e continua lá na
# próxima máquina.
#
#   memoria-link.sh                  # varre todos os projetos e liga os que dá
#   memoria-link.sh --repo <path>    # só um projeto
#   memoria-link.sh --adotar         # cria .context/memoria/ onde ainda não tem
#   memoria-link.sh --dry-run        # mostra o que faria, não toca em nada
#
set -euo pipefail

PROJ_DIR="$HOME/.claude/projects"
ALVO=""
DRY=0
ADOTAR=0
LIGADOS=0
JA=0
AVISOS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    ALVO="$2"; shift 2 ;;
    --adotar)  ADOTAR=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

diz() { printf '%s\n' "$*"; }

# O nome do diretório de projeto é o caminho com '/' E espaço virando '-'.
# Sem trocar o espaço, todo projeto com nome composto ("MINHA PASTA/app") gera
# um slug que não existe, e o script passa direto achando que não há o que ligar.
#
# E não é só barra e espaço: TODO caractere fora de [a-zA-Z0-9] vira '-'. Medido
# em 26/08/2026 contra 125 diretórios de projeto — a regra bate em todos. Trocar
# só '/' e espaço acerta o clone e erra TODO worktree, porque o caminho dele tem
# `.claude` e o ponto ficava intacto.
slug_de() { printf '%s' "$1" | LC_ALL=C tr -c 'a-zA-Z0-9' '-' | sed 's/-$//'; }

# O clone dono de um caminho: worktree devolve o repo de onde ele saiu.
# `<repo>/.claude/worktrees/<nome>` → `<repo>`.
clone_dono() {
  case "$1" in
    */.claude/worktrees/*) printf '%s' "${1%%/.claude/worktrees/*}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# O caminho real do projeto vem do `cwd` gravado no transcript — deduzir a partir
# do nome do diretório é ambíguo assim que o repo tem hífen no nome.
caminho_de() {
  local d="$1" jsonl
  jsonl="$(ls -t "$d"/*.jsonl 2>/dev/null | head -1 || true)"
  [ -n "$jsonl" ] || return 1
  grep -o '"cwd":"[^"]*"' "$jsonl" 2>/dev/null | head -1 | sed 's/.*"cwd":"//; s/"$//'
}

# Versionar a memória é DISTRIBUIR a memória. Se tiver credencial escrita ali
# dentro, adotar commita essa credencial no repositório — e daí não tem
# desfazer: quem clonar depois leva junto, e o histórico guarda mesmo que você
# apague no commit seguinte. Por isso o gate roda ANTES de criar a pasta.
# O padrão de connection string exige senha que não comece com '<', '$' ou '*':
# `<SENHA>`, `$DB_PASS` e `******` são o conserto, não o problema.
tem_segredo() {
  local dir="$1"
  find "$dir" -name '*.md' -type f -print0 2>/dev/null \
    | xargs -0 grep -lniE "eyJ[A-Za-z0-9_-]{30,}|sk-[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{20,}|xoxb-[A-Za-z0-9-]{20,}|postgres(ql)?://[^ :@]+:[^ @<\$*]{6,}@|AKIA[0-9A-Z]{16}" 2>/dev/null
}

adotar() {
  local repo="$1" mem dir slug achados
  mem="$repo/.context/memoria"
  slug="$(slug_de "$repo")"
  dir="$PROJ_DIR/$slug/memory"

  [ -d "$dir" ] || { diz "•  $repo: sem memória local — nada a adotar."; return 0; }
  [ -L "$dir" ] && { JA=$((JA + 1)); return 0; }

  # Sem repositório não há o que versionar: criar `.context/memoria/` numa pasta
  # solta só espalha arquivo que ninguém vai commitar.
  if [ ! -d "$repo/.git" ]; then
    diz "•  $repo: não é repositório git — memória fica local."
    return 0
  fi

  achados="$(tem_segredo "$dir" || true)"
  if [ -n "$achados" ]; then
    diz "✗  $repo NÃO adotado — tem credencial escrita na memória:"
    printf '     %s\n' $(printf '%s\n' "$achados" | xargs -n1 basename)
    diz "   Troque o valor pelo LUGAR onde ele vive e rode de novo. Exemplo:"
    diz "     - Conexão do banco: \`DATABASE_URL\` no .env.local"
    diz "   Se a credencial é válida e já circulou em arquivo, troque ela antes."
    AVISOS=$((AVISOS + 1))
    return 0
  fi

  if [ "$DRY" -eq 1 ]; then
    diz "→  adotaria $repo ($(ls "$dir"/*.md 2>/dev/null | wc -l | tr -d ' ') fatos)"
    LIGADOS=$((LIGADOS + 1))
    return 0
  fi

  mkdir -p "$mem"
  [ -f "$mem/README.md" ] || cat > "$mem/README.md" <<'DOC'
# Memória deste projeto

Um arquivo por fato. O Claude escreve aqui sozinho; você revisa e commita.

Vale a pena registrar o **porquê**, não o **quê** — "a migration removeu o
gate" é git log; "usar o carimbo como gate travava 19 dos 23 negócios porque
ele é o lote de importação, não a precificação" é memória.

Três regras que decidem se isto serve pra alguma coisa:

1. **Separe verificado de acreditado**, com essas palavras. Inferência tratada
   como fato vira premissa falsa pra todo mundo que ler depois.
2. **Data absoluta.** "Semana passada" não sobrevive a três sessões.
3. **Fato que se provou errado se apaga.** Memória errada é pior que memória
   faltando — ela é lida com confiança e ninguém re-checa.

Nunca escreva credencial aqui. Isto vai pro repositório: escreva o LUGAR onde o
valor vive (`DATABASE_URL` no `.env.local`), nunca o valor.
DOC
  ligar "$repo"
  diz "   agora commite: git add .context/memoria && git commit -m 'docs(memoria): adota memória do projeto'"
}

ligar() {
  local repo="$1" mem dir slug backup base n
  mem="$repo/.context/memoria"
  [ -d "$mem" ] || return 0

  slug="$(slug_de "$repo")"
  dir="$PROJ_DIR/$slug/memory"

  if [ -L "$dir" ]; then
    if [ "$(readlink "$dir")" = "$mem" ]; then
      JA=$((JA + 1))
      return 0
    fi
    diz "!  $repo: 'memory' já é link pra $(readlink "$dir") — não mexi."
    AVISOS=$((AVISOS + 1))
    return 0
  fi

  if [ "$DRY" -eq 1 ]; then
    diz "→  ligaria $repo"
    LIGADOS=$((LIGADOS + 1))
    return 0
  fi

  mkdir -p "$(dirname "$dir")"

  if [ -d "$dir" ]; then
    backup="$dir.antes-do-link-$(date +%Y%m%d-%H%M%S)"
    mv "$dir" "$backup"
    ln -s "$mem" "$dir"
    # Memória que só existia na máquina não pode sumir na troca: o que o repo
    # ainda não tem é copiado; o que existe dos dois lados com conteúdo
    # diferente é REPORTADO, nunca sobrescrito.
    n=0
    for f in "$backup"/*.md; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      if [ ! -e "$mem/$base" ]; then
        cp "$f" "$mem/$base"
        n=$((n + 1))
      elif ! diff -q "$f" "$mem/$base" >/dev/null 2>&1; then
        diz "!  $base difere do versionado — a versão da máquina ficou em $backup"
        AVISOS=$((AVISOS + 1))
      fi
    done
    diz "✓  $repo ligado — $n fato(s) da máquina trazido(s) pro repositório"
    [ "$n" -gt 0 ] && diz "   commite: git add .context/memoria && git commit -m 'docs(memoria): traz memória local'"
  else
    ln -s "$mem" "$dir"
    diz "✓  $repo ligado"
  fi
  LIGADOS=$((LIGADOS + 1))
}

# Worktree tem diretório de projeto PRÓPRIO (o slug sai do cwd), e o link do clone
# não serve pra ele: numa sessão isolada em worktree, escrever no `.context/memoria`
# do clone é escrever fora da árvore da branch, e o Claude recusa — com razão. Sem
# link próprio a memória não tem pra onde ir e a sessão desiste de registrar.
# Ligado, o fato nasce dentro do worktree e viaja no PR, igual a código.
ligar_worktrees() {
  local repo="$1" wt
  for wt in "$repo"/.claude/worktrees/*/; do
    [ -d "$wt" ] || continue
    wt="${wt%/}"
    [ -d "$wt/.context/memoria" ] || continue
    ligar "$wt"
  done
}

# Worktree apagado deixa o link apontando pro vazio. Link quebrado não é só
# sujeira: o Claude escreve nele achando que gravou, e o arquivo não existe em
# lugar nenhum depois.
limpar_quebrados() {
  local dir
  for dir in "$PROJ_DIR"/*/memory; do
    [ -L "$dir" ] || continue
    [ -e "$dir" ] && continue
    if [ "$DRY" -eq 1 ]; then
      diz "→  removeria link quebrado: $dir → $(readlink "$dir")"
    else
      rm "$dir"
      diz "✓  link quebrado removido: $(basename "$(dirname "$dir")")"
    fi
  done
}

if [ -n "$ALVO" ]; then
  ALVO="$(cd "$ALVO" && git rev-parse --show-toplevel)"
  if [ ! -d "$ALVO/.context/memoria" ]; then
    if [ "$ADOTAR" -eq 1 ]; then
      adotar "$ALVO"
      diz "memória: $LIGADOS ligado(s), $JA já em dia, $AVISOS aviso(s)."
      exit 0
    fi
    diz "$ALVO não tem .context/memoria/ — rode com --adotar pra criar e migrar."
    exit 1
  fi
  ligar "$ALVO"
  ligar_worktrees "$ALVO"
else
  [ -d "$PROJ_DIR" ] || { diz "sem $PROJ_DIR — o Claude Code ainda não rodou aqui."; exit 0; }
  # Um clone por vez: o `cwd` do transcript pode apontar pro clone ou pra um
  # worktree dele, e sem colapsar os dois o mesmo repo seria varrido uma vez por
  # worktree que já existiu. Os worktrees VIVOS são ligados por `ligar_worktrees`,
  # lendo o disco — diretório de projeto de worktree já apagado não interessa.
  VISTOS="|"
  for d in "$PROJ_DIR"/*/; do
    [ -d "$d" ] || continue
    repo="$(caminho_de "$d" || true)"
    [ -n "$repo" ] || continue
    repo="$(clone_dono "$repo")"
    case "$VISTOS" in *"|$repo|"*) continue ;; esac
    VISTOS="$VISTOS$repo|"
    if [ ! -d "$repo/.context/memoria" ]; then
      [ "$ADOTAR" -eq 1 ] || continue
      adotar "$repo"
      ligar_worktrees "$repo"
      continue
    fi
    ligar "$repo"
    ligar_worktrees "$repo"
  done
  limpar_quebrados
fi

diz "memória: $LIGADOS ligado(s), $JA já em dia, $AVISOS aviso(s)."
