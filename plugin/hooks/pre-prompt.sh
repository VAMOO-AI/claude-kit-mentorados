#!/usr/bin/env bash
# pre-prompt.sh — dispatcher do UserPromptSubmit: lê o payload UMA vez e o entrega, em
# ordem, aos hooks que até a 0.25.0 eram quatro entries no hooks.json. Hoje são seis: os
# quatro de antes, a devolução do estado gravado antes do compact (primeiro da fila) e o
# seed de env do worktree novo (último).
#
# Mesma razão do pre-bash.sh: cada entry custa um processo de shell mais um `bash <hook>`
# antes de o hook olhar o payload — um por hook, a cada prompt, em toda sessão.
#
# Semântica preservada: o stdout de cada hook é texto que vira contexto do prompt — são
# concatenados na ordem da lista; o primeiro hook que sai com código ≠ 0 encerra a cadeia
# com o mesmo código, stdout e stderr; hook ausente é pulado. Hook que não lê stdin (o link
# de memória e o seed de env do worktree) recebe /dev/null — um prompt maior que o buffer
# do pipe travaria o `printf`. O precompact-devolve.sh lê: é do payload que sai o
# session_id do snapshot.
#
# A exceção é a linha que começa com `@usuario `: é aviso para a pessoa, não contexto (hoje
# só o session-size-guard usa). Com uma dessas, a saída vira um JSON só — elas no
# systemMessage, que aparece na tela e o modelo não lê; o resto no additionalContext, que o
# modelo lê como lia o texto. Sem node, ou quando a cadeia sai ≠ 0, tudo segue texto, só
# sem o prefixo: JSON válido com exit 1 faria o Claude Code ignorar o código de saída.
#
# PRE_PROMPT_HOOKS_DIR aponta para outra pasta (é o que a suíte usa). Fail-open.
case "$0" in */*) HOOKS_DIR="${0%/*}" ;; *) HOOKS_DIR="." ;; esac
HOOKS_DIR="${PRE_PROMPT_HOOKS_DIR:-$HOOKS_DIR}"
payload=$(cat)
[ -z "$payload" ] && exit 0

nl='
'
emite() { # <código com que a cadeia vai sair>
  [ -n "$saida" ] || return 0
  case "$saida" in
    "@usuario "*|*"$nl@usuario "*) ;;
    *) printf '%s\n' "$saida"; return 0 ;;
  esac
  if [ "$1" -eq 0 ] && command -v node >/dev/null 2>&1 && json=$(SAIDA="$saida" node -e '
    const P = "@usuario ";
    const linhas = process.env.SAIDA.split("\n");
    const resposta = { systemMessage: linhas.filter((l) => l.startsWith(P)).map((l) => l.slice(P.length)).join("\n") };
    const modelo = linhas.filter((l) => !l.startsWith(P)).join("\n");
    if (modelo.trim()) resposta.hookSpecificOutput = { hookEventName: "UserPromptSubmit", additionalContext: modelo };
    process.stdout.write(JSON.stringify(resposta));
  ' 2>/dev/null) && [ -n "$json" ]; then
    printf '%s\n' "$json"
    return 0
  fi
  printf '%s\n' "$saida" | LC_ALL=C sed 's/^@usuario //'
}

saida=""
for h in precompact-devolve.sh session-size-guard.sh repo-session.sh branch-guard.sh memoria-worktree-link.sh worktree-seed-env.sh; do
  f="$HOOKS_DIR/$h"
  [ -f "$f" ] || continue
  case "$h" in
    repo-session.sh)          out=$(printf '%s' "$payload" | ( . "$f" touch )); rc=$? ;;
    memoria-worktree-link.sh|worktree-seed-env.sh) out=$( ( . "$f" ) </dev/null ); rc=$? ;;
    *)                        out=$(printf '%s' "$payload" | ( . "$f" )); rc=$? ;;
  esac
  [ -n "$out" ] && saida="${saida:+$saida$nl}$out"
  if [ "$rc" -ne 0 ]; then
    emite "$rc"
    exit "$rc"
  fi
done
emite 0
exit 0
