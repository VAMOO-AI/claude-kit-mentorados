#!/usr/bin/env bash
# pre-prompt.sh — dispatcher do UserPromptSubmit: lê o payload UMA vez e o entrega, em
# ordem, aos hooks que até a 0.25.0 eram entries separados no hooks.json. Hoje são três: o
# aviso de node ausente (primeiro: sem node os outros guards saem calados), o
# session-size-guard e o repo-session. No kit do time entra um quarto, logo depois do
# primeiro: o warn-sem-jq, enquanto guards de lá lerem por jq. Depois da 0.64 saíram o branch-guard, o
# memoria-worktree-link, o worktree-seed-env e a devolução do compact (que virou o
# compact-estado.sh, no SessionStart(compact)).
#
# Mesma razão do pre-bash.sh: cada entry custa um processo de shell mais um `bash <hook>`
# antes de o hook olhar o payload — um por hook, a cada prompt, em toda sessão.
#
# Semântica preservada: o stdout de cada hook é texto que vira contexto do prompt — são
# concatenados na ordem da lista; o primeiro hook que sai 2 encerra a cadeia com exit 2,
# stdout e stderr (bloqueia o prompt); hook ausente é pulado. Hook que sai com outro código
# ≠ 0 tem bug e não desliga os seguintes: com entries separados o harness rodava todos, e
# exit 1 não bloqueia. O stdout dele vai para o stderr, a linha "[pre-prompt] <hook> saiu
# <rc> (bug do hook; cadeia segue)" sai no stderr e, para a pessoa, como "@usuario ", e a
# cadeia segue.
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
  # Bash puro: a máquina sem node é justamente a que pode não ter o sed no PATH.
  local l
  while IFS= read -r l || [ -n "$l" ]; do printf '%s\n' "${l#@usuario }"; done <<< "$saida"
}

saida=""
# O warn-sem-jq é do kit do time, onde guards ainda leem por jq até a F4 do núcleo único
# (#241): instalado, roda logo depois do warn-sem-node; aqui ele não existe e é pulado como
# hook ausente. Os dois avisos de binário vêm antes do session-size-guard, que pode bloquear.
for h in warn-sem-node.sh warn-sem-jq.sh session-size-guard.sh repo-session.sh; do
  f="$HOOKS_DIR/$h"
  [ -f "$f" ] || continue
  case "$h" in
    repo-session.sh)          out=$(printf '%s' "$payload" | ( . "$f" touch )); rc=$? ;;
    *)                        out=$(printf '%s' "$payload" | ( . "$f" )); rc=$? ;;
  esac
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    [ -n "$out" ] && printf '%s\n' "$out" >&2
    aviso="[pre-prompt] $h saiu $rc (bug do hook; cadeia segue)"
    printf '%s\n' "$aviso" >&2
    saida="${saida:+$saida$nl}@usuario $aviso"
    continue
  fi
  [ -n "$out" ] && saida="${saida:+$saida$nl}$out"
  if [ "$rc" -eq 2 ]; then
    emite 2
    exit 2
  fi
done
emite 0
exit 0
