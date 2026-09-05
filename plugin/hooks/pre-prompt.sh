#!/usr/bin/env bash
# pre-prompt.sh — dispatcher do UserPromptSubmit: lê o payload UMA vez e o entrega, em
# ordem, aos hooks que até a 0.25.0 eram quatro entries no hooks.json.
#
# Mesma razão do pre-bash.sh: cada entry custa um processo de shell mais um `bash <hook>`
# antes de o hook olhar o payload — quatro por prompt, em toda sessão.
#
# Semântica preservada: o stdout de cada hook é texto que vira contexto do prompt — os
# quatro são concatenados na ordem em que rodavam; o primeiro hook que sai com código ≠ 0
# encerra a cadeia com o mesmo código, stdout e stderr; hook ausente é pulado. Hook que não
# lê stdin (o link de memória do worktree) recebe /dev/null — um prompt maior que o buffer
# do pipe travaria o `printf`.
#
# PRE_PROMPT_HOOKS_DIR aponta para outra pasta (é o que a suíte usa). Fail-open.
case "$0" in */*) HOOKS_DIR="${0%/*}" ;; *) HOOKS_DIR="." ;; esac
HOOKS_DIR="${PRE_PROMPT_HOOKS_DIR:-$HOOKS_DIR}"
payload=$(cat)
[ -z "$payload" ] && exit 0

saida=""
for h in session-size-guard.sh repo-session.sh branch-guard.sh memoria-worktree-link.sh; do
  f="$HOOKS_DIR/$h"
  [ -f "$f" ] || continue
  case "$h" in
    repo-session.sh)          out=$(printf '%s' "$payload" | ( . "$f" touch )); rc=$? ;;
    memoria-worktree-link.sh) out=$( ( . "$f" ) </dev/null ); rc=$? ;;
    *)                        out=$(printf '%s' "$payload" | ( . "$f" )); rc=$? ;;
  esac
  if [ "$rc" -ne 0 ]; then
    [ -n "$saida" ] && printf '%s\n' "$saida"
    [ -n "$out" ] && printf '%s\n' "$out"
    exit "$rc"
  fi
  [ -n "$out" ] && saida="${saida:+$saida
}$out"
done
[ -n "$saida" ] && printf '%s\n' "$saida"
exit 0
