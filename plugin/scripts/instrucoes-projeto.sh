#!/usr/bin/env bash
# instrucoes-projeto.sh — o AGENTS.md da raiz é a fonte das regras do projeto, e o
# CLAUDE.md é a ponte `@AGENTS.md`, mais o que for exclusivo do Claude Code.
#
# O Claude Code só lê o AGENTS.md sozinho em projeto sem CLAUDE.md, e o `@AGENTS.md` nunca
# carrega duas vezes. O Codex e outros agentes só leem o AGENTS.md, e o Codex corta em
# 32 KiB. Symlink não serve: o Edit/Write do Claude recusam escrever através dele, e no
# Windows ele não funciona. Cópia diverge. O modelo de AGENTS.md é o
# templates/AGENTS-projeto.md.exemplo do plugin.
#
#   instrucoes-projeto.sh [--check|--apply] [<repo>]
#
# --check, o padrão, só lê. Classifica a raiz em so-import, import+conteudo, so-agents,
# so-claude, divergentes, symlink ou nenhum, e imprime o tamanho dos dois arquivos e a ação
# proposta. Acusa também a cópia do AGENTS.md colada debaixo do import (copia-duplicada),
# o AGENTS.md acima de 32 KiB, o nome gravado com outra caixa e os pares CLAUDE.md +
# AGENTS.md em subpastas.
#
# --apply grava só o que não pede julgamento, e mostra o diff antes:
#   so-agents  cria o CLAUDE.md com @AGENTS.md
#   symlink    CLAUDE.md -> AGENTS.md vira arquivo com @AGENTS.md, e o AGENTS.md não muda;
#              AGENTS.md -> CLAUDE.md vira arquivo com o conteúdo, e o CLAUDE.md a ponte
#   so-claude  o conteúdo vai para o AGENTS.md, e o CLAUDE.md fica com @AGENTS.md
# Nas outras classes imprime a proposta e não grava nada: o que cita hook, skill, /comando
# ou ferramenta do Claude Code fica no CLAUDE.md, o resto vai para o AGENTS.md, e quem
# decide é quem migra. Não faz commit e não toca nada além do CLAUDE.md e do AGENTS.md da
# raiz.
#
# Sai 0 quando classificou (tendo gravado ou não), 1 se uma gravação falhou, 2 com uso
# errado e 3 quando o repo não existe.
set -uo pipefail

LIMITE_CODEX=32768
MODELO="$(cd "$(dirname "$0")/.." && pwd)/templates/AGENTS-projeto.md.exemplo"
CAB_FICA="proposta: fica no CLAUDE.md, abaixo do @AGENTS.md (parece exclusivo do Claude Code)"

uso() {
  [ -n "${1:-}" ] && echo "$1" >&2
  echo "uso: $(basename "$0") [--check|--apply] [<repo>]" >&2
  exit 2
}

MODO=""
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--apply)
      [ -z "$MODO" ] || [ "$MODO" = "${1#--}" ] || uso "--check e --apply não andam juntos"
      MODO="${1#--}"; shift ;;
    -h|--help)
      awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    -*) uso "opção desconhecida: $1" ;;
    *)  [ -z "$REPO" ] || uso "um repo por vez: $REPO e $1"
        REPO="$1"; shift ;;
  esac
done
MODO="${MODO:-check}"
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[ -d "$REPO" ] || { echo "repo não encontrado: $REPO" >&2; exit 3; }
REPO="$(cd "$REPO" && pwd -P)"

# Nomes como estão gravados no diretório. No disco padrão do Mac, `[ -e AGENTS.md ]`
# responde por um `agents.md`, e gravar AGENTS.md cairia em cima dele. O `find -iname`
# devolve o nome guardado.
variantes() { find "$1" -mindepth 1 -maxdepth 1 -iname "$2" 2>/dev/null | sed 's|.*/||'; }

tamanho() { [ -e "$1" ] && wc -c < "$1" 2>/dev/null | tr -d ' '; }

descreve() { # descreve <arquivo> <existe 0|1>
  local t
  [ "$2" = 1 ] || { echo "ausente"; return; }
  t="$(tamanho "$1")"
  if [ -L "$1" ]; then
    if [ -n "$t" ]; then echo "symlink -> $(readlink "$1") ($t B)"
    else echo "symlink -> $(readlink "$1") (alvo não existe)"; fi
  else
    echo "$t B"
  fi
}

# CLAUDE.md feito só de `@AGENTS.md`, fora espaço, CR e linha vazia.
so_import() {
  awk '
    { t = $0; sub(/\r$/, "", t); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
    t == "" { next }
    t == "@AGENTS.md" || t == "@./AGENTS.md" { n++; next }
    { outro = 1 }
    END { exit !(n > 0 && !outro) }' "$1"
}

# Alguma linha que é só `@AGENTS.md`? Levada para o AGENTS.md, importaria o próprio arquivo.
linha_import() {
  awk '
    { t = $0; sub(/\r$/, "", t); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
    t == "@AGENTS.md" || t == "@./AGENTS.md" { achou = 1; exit }
    END { exit !achou }' "$1"
}

sem_import() { # sem_import <origem> <destino>
  awk '
    { t = $0; sub(/\r$/, "", t); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
    t == "@AGENTS.md" || t == "@./AGENTS.md" { next }
    { print }' "$1" > "$2"
}

vazio() { awk '{ sub(/\r$/, "") } NF { achou = 1; exit } END { exit achou }' "$1"; }

# O Claude Code importa `@AGENTS.md` também no meio de uma frase, mas não dentro de
# crase nem de bloco de código.
tem_import() {
  awk '
    { sub(/\r$/, "") }
    /^[ \t]*(```|~~~)/ { cerca = !cerca; next }
    cerca { next }
    { l = " " $0 " "; gsub(/`[^`]*`/, "", l); if (l ~ /[ \t]@(\.\/)?AGENTS\.md[ \t]/) achou = 1 }
    END { exit !achou }' "$1"
}

# estado <dir>: preenche as E_* com o par CLAUDE.md/AGENTS.md daquele diretório.
estado() {
  local d="$1" v
  E_C="$d/CLAUDE.md"; E_A="$d/AGENTS.md"
  E_C_EX=0; E_A_EX=0; E_C_LINK=0; E_A_LINK=0; E_CAIXA=""; E_SUB=""
  for v in $(variantes "$d" CLAUDE.md); do
    if [ "$v" = CLAUDE.md ]; then E_C_EX=1; else E_CAIXA="$E_CAIXA $v"; fi
  done
  for v in $(variantes "$d" AGENTS.md); do
    if [ "$v" = AGENTS.md ]; then E_A_EX=1; else E_CAIXA="$E_CAIXA $v"; fi
  done
  E_CAIXA="${E_CAIXA# }"
  if [ "$E_C_EX" = 1 ]; then
    if [ -L "$E_C" ]; then E_C_LINK=1; elif [ ! -f "$E_C" ]; then E_C_EX=0; fi
  fi
  if [ "$E_A_EX" = 1 ]; then
    if [ -L "$E_A" ]; then E_A_LINK=1; elif [ ! -f "$E_A" ]; then E_A_EX=0; fi
  fi

  if [ "$E_C_LINK" = 1 ] || [ "$E_A_LINK" = 1 ]; then
    E_CLASSE=symlink
    if [ "$E_C_LINK" = 1 ] && [ "$E_A_LINK" = 0 ] && [ "$E_A_EX" = 1 ] && [ "$E_C" -ef "$E_A" ]; then
      E_SUB=claude-aponta-agents
    elif [ "$E_A_LINK" = 1 ] && [ "$E_C_LINK" = 0 ] && [ "$E_C_EX" = 1 ] && [ "$E_A" -ef "$E_C" ]; then
      E_SUB=agents-aponta-claude
    else
      E_SUB=manual
    fi
  elif [ "$E_C_EX" = 0 ] && [ "$E_A_EX" = 0 ]; then E_CLASSE=nenhum
  elif [ "$E_C_EX" = 0 ]; then E_CLASSE=so-agents
  elif [ "$E_A_EX" = 0 ]; then E_CLASSE=so-claude
  elif so_import "$E_C"; then E_CLASSE=so-import
  elif tem_import "$E_C"; then E_CLASSE=import+conteudo
  else E_CLASSE=divergentes
  fi
}

# Linhas do CLAUDE.md, uma a uma. `conta` devolve quantas repetem o AGENTS.md; os outros
# modos imprimem a proposta: sai (já está no AGENTS.md), fica (parece só do Claude Code) e
# vai (o resto). A heurística é de texto, e a saída diz que é proposta.
read -r -d '' AWK_LINHAS <<'AWK'
function limpa(s) { sub(/\r$/, "", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function eh_import(t) { return t == "@AGENTS.md" || t == "@./AGENTS.md" }
# Texto de verdade: título, cerca de código, régua e linha curta coincidem sem ser cópia.
function significativa(t) {
  return length(t) >= 10 && t !~ /^#/ && t !~ /^(```|~~~)/ && t ~ /[A-Za-z0-9]/
}
# Para dizer "já está no AGENTS.md" vale qualquer linha igual, régua e separador de tabela
# inclusive; só a cerca fica de fora, que partiria um bloco de código ao meio.
function comparavel(t) { return t != "" && t !~ /^(```|~~~)/ }
function tag_claude(s,    l, r, cmd, nx) {
  l = tolower(s)
  gsub(/webhooks?/, "", l)
  if (index(l, "hook")) return "hook"
  if (index(l, "skill")) return "skill"
  if (index(l, "claude code")) return "Claude Code"
  if (index(l, "subagent")) return "subagente"
  if ((" " l " ") ~ /[^a-z0-9]mcp[^a-z0-9]/) return "MCP"
  if (index(l, ".claude/")) return ".claude/"
  if (index(l, "settings.json")) return "settings.json"
  if (index(l, "claude.md")) return "CLAUDE.md"
  if (l ~ /pretooluse|posttooluse|userpromptsubmit|sessionstart|precompact/) return "evento de hook"
  if (l ~ /plan mode|modo plano|statusline|slash command/) return "Claude Code"
  r = " " s
  while (match(r, /[ \t("'`]\/[a-z][a-z0-9:_-]*/)) {
    cmd = substr(r, RSTART + 1, RLENGTH - 1)
    nx = substr(r, RSTART + RLENGTH, 1)
    r = substr(r, RSTART + RLENGTH)
    if (nx == "/") continue
    if (cmd ~ /^\/(tmp|dev|etc|usr|opt|var|bin|sbin|lib|home|private|proc|sys|mnt|root|api|app|src)$/) continue
    return cmd
  }
  r = " " s " "
  if (match(r, /[^A-Za-z0-9_](EnterWorktree|ExitWorktree|TodoWrite|NotebookEdit|WebFetch|WebSearch|ToolSearch|AskUserQuestion|ExitPlanMode|SendMessage)[^A-Za-z0-9_]/))
    return substr(r, RSTART + 1, RLENGTH - 2)
  if (match(s, /`(Read|Edit|Write|Bash|Grep|Glob|Agent|Task|Skill|Monitor)`/))
    return substr(s, RSTART + 1, RLENGTH - 2)
  return ""
}
BEGIN {
  ag = ENVIRON["INSTR_AGENTS"]; modo = ENVIRON["INSTR_MODO"]; cab_fica = ENVIRON["INSTR_CAB_FICA"]
  if (ag != "") {
    while ((getline linha < ag) > 0) { t = limpa(linha); if (comparavel(t)) no_agents[t] = 1 }
    close(ag)
  }
}
{ sub(/\r$/, ""); t = limpa($0) }
/^[ \t]*(```|~~~)/ { cerca = !cerca }
t == "" || eh_import(t) { next }
modo == "conta" { if (significativa(t) && (t in no_agents)) n++; next }
{
  l = " " t " "; gsub(/`[^`]*`/, "", l)
  # Frase com o import no meio: levar para o AGENTS.md tiraria a ponte do CLAUDE.md.
  if (!cerca && l ~ /[ \t]@(\.\/)?AGENTS\.md[ \t]/) fica[++nf] = sprintf("  L%d  [import] %s", NR, $0)
  else if (comparavel(t) && (t in no_agents)) sai[++ns] = sprintf("  L%d  %s", NR, $0)
  else if ((g = tag_claude(t)) != "") fica[++nf] = sprintf("  L%d  [%s] %s", NR, g, $0)
  else vai[++nv] = sprintf("  L%d  %s", NR, $0)
}
END {
  if (modo == "conta") { print n + 0; exit }
  if (ns && modo != "so-fica") {
    print "proposta: sai do CLAUDE.md (já está no AGENTS.md, que o @AGENTS.md carrega)"
    for (i = 1; i <= ns; i++) print sai[i]
  }
  if (nf) { print cab_fica; for (i = 1; i <= nf; i++) print fica[i] }
  if (nv && modo != "so-fica") {
    print "proposta: vai para o AGENTS.md"
    for (i = 1; i <= nv; i++) print vai[i]
  }
}
AWK

linhas() { # linhas <claude> <agents ou vazio> <modo> [cabeçalho do fica]
  INSTR_AGENTS="$2" INSTR_MODO="$3" INSTR_CAB_FICA="${4:-$CAB_FICA}" awk "$AWK_LINHAS" "$1"
}

links() { # descreve os links da raiz em uma linha
  local s=""
  [ "$E_C_LINK" = 1 ] && s="CLAUDE.md -> $(readlink "$E_C")"
  [ "$E_A_LINK" = 1 ] && s="${s:+$s, }AGENTS.md -> $(readlink "$E_A")"
  echo "$s"
}

# Pares CLAUDE.md + AGENTS.md em subpastas. Num repo git vale o que o git vê (rastreado ou
# não ignorado), para que vendor e build fiquem de fora; fora do git, o find sem
# node_modules, .git e worktrees, que repetiriam o par da raiz.
aninhados() {
  local lista via pares n
  if [ "$(git -C "$REPO" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
    via=git
    lista="$(git -C "$REPO" -c core.quotePath=false ls-files -co --exclude-standard -- '*/CLAUDE.md' '*/AGENTS.md' 2>/dev/null)"
  else
    via=find
    lista="$(cd "$REPO" && find . \( -name node_modules -o -name .git -o -name .claude-worktrees \
      -o -name .worktrees -o -path ./.claude/worktrees \) -prune \
      -o \( -name CLAUDE.md -o -name AGENTS.md \) -print 2>/dev/null | sed 's|^\./||')"
  fi
  pares="$(printf '%s\n' "$lista" | grep -v -e '^\.claude/worktrees/' -e '^\.claude-worktrees/' -e '^\.worktrees/' \
    | awk '/\/CLAUDE\.md$/ { c[substr($0, 1, length($0) - 10)] = 1 }
           /\/AGENTS\.md$/ { a[substr($0, 1, length($0) - 10)] = 1 }
           END { for (d in c) if (d in a) print d }' | LC_ALL=C sort)"
  n=0
  [ -n "$pares" ] && n="$(printf '%s\n' "$pares" | wc -l | tr -d ' ')"
  echo "aninhados: $n (via $via)"
  [ "$n" -gt 0 ] || return 0
  printf '%s\n' "$pares" | while IFS= read -r d; do
    estado "$REPO/$d"
    echo "aninhado: $d — $E_CLASSE (CLAUDE.md: $(descreve "$E_C" "$E_C_EX"); AGENTS.md: $(descreve "$E_A" "$E_A_EX"))"
  done
}

# ── relatório ────────────────────────────────────────────────────────────────
estado "$REPO"
echo "instrucoes-projeto: $REPO"
echo "CLAUDE.md: $(descreve "$E_C" "$E_C_EX")"
echo "AGENTS.md: $(descreve "$E_A" "$E_A_EX")"
echo "classe: $E_CLASSE"

DUP=0
if [ "$E_CLASSE" = import+conteudo ]; then
  DUP="$(linhas "$E_C" "$E_A" conta)"
  [ "$DUP" -ge 3 ] && echo "copia-duplicada: $DUP linhas do AGENTS.md repetidas no CLAUDE.md, que já as carrega pelo @AGENTS.md"
fi

if [ "$E_A_EX" = 1 ]; then
  t="$(tamanho "$E_A")"
  [ -n "$t" ] && [ "$t" -gt "$LIMITE_CODEX" ] \
    && echo "limite-codex: AGENTS.md tem $t B, acima de $LIMITE_CODEX B (32 KiB): o Codex corta o que passar"
elif [ "$E_CLASSE" = so-claude ]; then
  t="$(tamanho "$E_C")"
  [ -n "$t" ] && [ "$t" -gt "$LIMITE_CODEX" ] \
    && echo "limite-codex: CLAUDE.md tem $t B; no AGENTS.md passa de $LIMITE_CODEX B (32 KiB), e o Codex corta o que passar"
fi

for v in $E_CAIXA; do
  case "$(printf '%s' "$v" | tr '[:lower:]' '[:upper:]')" in
    CLAUDE.MD) certo=CLAUDE.md ;;
    *)         certo=AGENTS.md ;;
  esac
  echo "caixa: $v não é $certo — no Linux ninguém o acha por esse nome, e no Mac gravar $certo cai em cima dele; renomeie com git mv"
done

( aninhados )

case "$E_CLASSE" in
  so-import)
    echo "ação: nada a fazer" ;;
  so-agents)
    echo "ação: --apply cria o CLAUDE.md com @AGENTS.md" ;;
  so-claude)
    if so_import "$E_C"; then
      echo "ação: o CLAUDE.md só importa um AGENTS.md que não existe; crie o AGENTS.md (modelo em $MODELO); o --apply não grava aqui"
    else
      nota=""
      linha_import "$E_C" && nota=", sem a linha @AGENTS.md (no AGENTS.md ela importaria o próprio arquivo)"
      echo "ação: --apply move o conteúdo do CLAUDE.md para o AGENTS.md$nota e deixa o CLAUDE.md com @AGENTS.md"
      linhas "$E_C" "" so-fica "proposta: depois do --apply, isto parece exclusivo do Claude Code e pode voltar para baixo do @AGENTS.md"
    fi ;;
  import+conteudo)
    if [ "$DUP" -ge 3 ]; then
      echo "ação: tire do CLAUDE.md o que repete o AGENTS.md e confira o resto (proposta abaixo); o --apply não grava aqui"
    else
      echo "ação: confira se o que está além do import é mesmo só do Claude Code (proposta abaixo); o --apply não grava aqui"
    fi
    linhas "$E_C" "$E_A" tudo ;;
  divergentes)
    if cmp -s "$E_C" "$E_A"; then
      echo "ação: o CLAUDE.md é cópia idêntica do AGENTS.md; troque o conteúdo dele por @AGENTS.md, nada se perde; o --apply não grava aqui"
    elif vazio "$E_C"; then
      echo "ação: o CLAUDE.md está vazio, e com ele o Claude Code não lê o AGENTS.md; grave @AGENTS.md nele, nada se perde; o --apply não grava aqui"
    elif vazio "$E_A"; then
      echo "ação: o AGENTS.md está vazio; apague-o e rode o --apply, que move o conteúdo do CLAUDE.md para ele (vira so-claude); do jeito que está, o --apply não grava"
    else
      echo "ação: sem @AGENTS.md e com conteúdo nos dois; junte no AGENTS.md o que vale para todo agente e deixe no CLAUDE.md o import e o que for só do Claude Code (proposta e diff abaixo); o --apply não grava aqui"
    fi
    linhas "$E_C" "$E_A" tudo
    if cmp -s "$E_A" "$E_C"; then
      echo "diff AGENTS.md → CLAUDE.md: nenhum, são iguais"
    else
      echo "diff AGENTS.md → CLAUDE.md:"
      diff -u --label AGENTS.md --label CLAUDE.md "$E_A" "$E_C"
    fi ;;
  symlink)
    case "$E_SUB" in
      claude-aponta-agents)
        echo "ação: --apply troca o symlink por um arquivo com @AGENTS.md; o AGENTS.md não muda" ;;
      agents-aponta-claude)
        if so_import "$E_C"; then
          echo "ação: AGENTS.md -> CLAUDE.md, e o CLAUDE.md só importa o AGENTS.md: não há regra em lugar nenhum; escreva o AGENTS.md de verdade; o --apply não grava aqui"
        else
          echo "ação: --apply grava o conteúdo do CLAUDE.md num AGENTS.md de verdade, no lugar do symlink, e deixa o CLAUDE.md com @AGENTS.md"
        fi ;;
      *)
        echo "ação: symlink que não liga os dois arquivos da raiz ($(links)); leve o conteúdo para um AGENTS.md de verdade e deixe o CLAUDE.md com @AGENTS.md; o --apply não grava aqui" ;;
    esac ;;
  nenhum)
    echo "ação: crie o AGENTS.md (modelo em $MODELO) e o CLAUDE.md com @AGENTS.md; o --apply não grava aqui" ;;
esac

[ "$MODO" = apply ] || exit 0

# ── --apply ──────────────────────────────────────────────────────────────────
echo
if [ -n "$E_CAIXA" ]; then
  echo "nada gravado: há nome com outra caixa na raiz ($E_CAIXA); renomeie antes"
  exit 0
fi
case "$E_CLASSE:$E_SUB" in
  so-agents:|symlink:claude-aponta-agents) ;;
  so-claude:|symlink:agents-aponta-claude)
    if so_import "$E_C"; then
      echo "nada gravado: o CLAUDE.md só importa o AGENTS.md, e não há regra para mover"; exit 0
    fi ;;
  so-import:) echo "nada gravado: o CLAUDE.md já é a ponte @AGENTS.md"; exit 0 ;;
  nenhum:)    echo "nada gravado: não há AGENTS.md para importar"; exit 0 ;;
  *)          echo "nada gravado: $E_CLASSE pede julgamento, e a proposta está acima"; exit 0 ;;
esac

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/instrucoes.XXXXXX")" || { echo "mktemp falhou" >&2; exit 1; }
trap 'rm -rf "$TMPD"' EXIT
PONTE="$TMPD/ponte"
printf '@AGENTS.md\n' > "$PONTE"
# O que vai para o AGENTS.md: o CLAUDE.md byte a byte, ou sem as linhas `@AGENTS.md`.
FONTE="$E_C"
# so-agents não tem CLAUDE.md: o awk do linha_import reclamaria do arquivo que falta
if [ -f "$E_C" ] && linha_import "$E_C"; then FONTE="$TMPD/fonte"; sem_import "$E_C" "$FONTE"; fi

mostra() { diff -u --label "$1" --label "$3" "$2" "$4"; return 0; }  # mostra <rótulo> <antigo> <rótulo> <novo>
# Nunca através de symlink: `cp` e `>` escrevem no alvo, e o alvo aqui é a fonte das regras.
grava() { # grava <destino> <conteúdo>
  if [ -L "$1" ]; then rm -f "$1" || return 1; fi
  cp "$2" "$1" && cmp -s "$2" "$1" || return 1
  echo "gravado: ${1##*/}"
}
falhou() { echo "falhou ao gravar $1; o que não foi listado como gravado ficou como estava" >&2; exit 1; }

case "$E_CLASSE:$E_SUB" in
  so-agents:)
    mostra "CLAUDE.md (não existe)" /dev/null CLAUDE.md "$PONTE"
    grava "$E_C" "$PONTE" || falhou CLAUDE.md ;;
  symlink:claude-aponta-agents)
    mostra "CLAUDE.md (symlink -> $(readlink "$E_C"))" /dev/null CLAUDE.md "$PONTE"
    grava "$E_C" "$PONTE" || falhou CLAUDE.md ;;
  symlink:agents-aponta-claude)
    if cmp -s "$E_C" "$FONTE"; then
      echo "AGENTS.md (symlink -> $(readlink "$E_A")) vira arquivo com o mesmo conteúdo ($(tamanho "$E_C") B)"
    else
      mostra "AGENTS.md (symlink -> $(readlink "$E_A"))" "$E_C" AGENTS.md "$FONTE"
    fi
    mostra CLAUDE.md "$E_C" CLAUDE.md "$PONTE"
    grava "$E_A" "$FONTE" || falhou AGENTS.md
    grava "$E_C" "$PONTE" || falhou CLAUDE.md ;;
  so-claude:)
    mostra "AGENTS.md (não existe)" /dev/null AGENTS.md "$FONTE"
    mostra CLAUDE.md "$E_C" CLAUDE.md "$PONTE"
    grava "$E_A" "$FONTE" || falhou AGENTS.md
    grava "$E_C" "$PONTE" || falhou CLAUDE.md ;;
esac
estado "$REPO"
echo "classe agora: $E_CLASSE"
