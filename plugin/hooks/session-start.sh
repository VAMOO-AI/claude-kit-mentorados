#!/usr/bin/env bash
# session-start.sh — dispatcher do SessionStart: lê o payload UMA vez e chama, em ordem, os
# avisos de abertura que até a 0.90 eram entries separados no hooks.json.
#
# Por que existe (decisão D13 de 09/11/2026): o Claude Code só processa o 1º prompt depois
# que os hooks de SessionStart terminam. Quatro entries eram quatro `sh`, quatro `bash` e
# três `node` lendo o mesmo `cwd` do mesmo payload. Aqui o harness faz um spawn só, o `cwd`
# sai de um node e vai para os avisos em KIT_SESSAO_CWD, e cada aviso roda em subshell
# (`source`, sem um novo bash). É o mesmo desenho do pre-bash.sh e do pre-prompt.sh.
#
# Os avisos, nesta ordem:
#   scripts/warn-branch-worktree.sh   branch atrás do upstream
#   scripts/warn-kit-updated.sh       o que mudou no kit desde a última sessão
#   hooks/warn-skills-projeto.sh      skills do projeto acima do teto
#   hooks/warn-doc-ancorado.sh        handoff/baseline ancorado em SHA distante
# O compact-estado.sh fica na entrada própria do hooks.json, com o matcher `compact`.
#
# Semântica preservada: o stdout de cada aviso vira contexto da sessão, concatenado na ordem
# da lista; aviso ausente é pulado; aviso que sai ≠ 0 não desliga os seguintes (SessionStart
# não bloqueia, e com entries separados o harness rodava todos). Sai sempre 0.
#
# Cada aviso continua rodando sozinho (as suítes deles o chamam direto): sem KIT_SESSAO_CWD,
# ele lê o `cwd` do stdin por node, como antes. SESSION_START_ROOT aponta para outra raiz de
# plugin (é o que a suíte usa). Fail-open: sem payload, sem node ou sem hookjson.js, os
# avisos caem no CLAUDE_PROJECT_DIR e no $PWD.
case "$0" in */*) AQUI="${0%/*}" ;; *) AQUI="." ;; esac
RAIZ="${SESSION_START_ROOT:-$AQUI/..}"
payload=$(cat)

KIT_SESSAO_CWD=""
H="$RAIZ/scripts/hookjson.js"
if [ -n "$payload" ] && [ -f "$H" ] && command -v node >/dev/null 2>&1; then
  KIT_SESSAO_CWD="$(printf '%s' "$payload" | node "$H" cwd 2>/dev/null)"
fi
export KIT_SESSAO_CWD

for rel in scripts/warn-branch-worktree.sh scripts/warn-kit-updated.sh \
           hooks/warn-skills-projeto.sh hooks/warn-doc-ancorado.sh; do
  f="$RAIZ/$rel"
  [ -f "$f" ] || continue
  out=$(printf '%s' "$payload" | ( . "$f" ))
  [ -n "$out" ] && printf '%s\n' "$out"
done
exit 0
