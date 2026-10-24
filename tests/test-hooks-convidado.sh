#!/usr/bin/env bash
# Prova de que o plugin/hooks/hooks.json NÃO tem mais a guarda de convidado (F10 do
# docs/plano-nucleo-plugin.md do kit do time).
#
# Até a F9, com o kit do time e este plugin ligados na mesma máquina, quem cedia era o plugin:
# todo comando saía 0 antes de abrir o script quando havia ~/.claude/.team-manifest sem a linha
# `nucleo=plugin`. Desde a F10 o corte é o padrão do update.sh do time: ele tira do settings.json
# os hooks do núcleo e grava `nucleo=plugin`, e o gate de fonte única de lá
# (tests/test-nucleo-lista.sh) reprova o settings.json instalado que ainda chame um hook do
# núcleo. Quem registra é só este plugin, em qualquer máquina, e a guarda virou peso morto que
# um dia calaria tudo por engano.
#
# O que precisa continuar valendo:
#   - nenhum comando registrado olha o .team-manifest nem a escotilha KIT_VAMOO_HOOKS, inclusive
#     hook que entrar depois;
#   - todo comando chama um script do ${CLAUDE_PLUGIN_ROOT};
#   - com o manifesto do time (sem marcador, com nucleo=plugin ou com nucleo=settings) e sem
#     manifesto (a máquina de um mentorado), todo comando chega ao script, e o pre-bash bloqueia
#     o commit na main.
#
# Uso: bash tests/test-hooks-convidado.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOKS_JSON="$RAIZ/plugin/hooks/hooks.json"
[ -f "$HOOKS_JSON" ] || { echo "hooks.json não encontrado: $HOOKS_JSON"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
# Herdados, o codex-espelho escreveria no Codex de quem rodou o teste (o HOME é trocado, esses
# dois não). O KIT_VAMOO_HOOKS sai para provar que nada depende dele.
unset KIT_VAMOO_HOOKS CODEX_HOME CLAUDE_PLUGIN_DATA
TAB="$(printf '\t')"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hooks-convidado.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

# Um evento e um comando por linha, separados por TAB. Quem lê o JSON é o node: jq
# não é pré-requisito de quem instala o kit.
node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  for (const [evento, grupos] of Object.entries(j.hooks || {}))
    for (const g of grupos)
      for (const h of g.hooks || []) console.log(evento + "\t" + (h.command || ""));
' "$HOOKS_JSON" > "$TMP/comandos" || { echo "hooks.json ilegível"; exit 2; }

# "PreToolUse:pre-bash.sh", "SessionEnd:repo-session.sh end" — o nome que aparece na falha.
rotulo() { printf '%s:%s' "$1" "$(printf '%s' "$2" | sed 's/.*PLUGIN_ROOT}\///; s/"//g; s/^hooks\///; s/^scripts\///')"; }

REPO="$TMP/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q -b main 2>/dev/null
payload() { # payload <evento>
  E="$1" D="$REPO" node -e '
    const d = process.env.D;
    process.stdout.write(JSON.stringify({
      session_id: "sessao-convidado", cwd: d, hook_event_name: process.env.E,
      permission_mode: "default", tool_name: "Bash", prompt: "oi",
      tool_input: { command: "git commit -q -m x", file_path: d + "/package.json" },
    }));' </dev/null
}

# roda <shell> <comando> <payload> <home> <plugin-root> → imprime o rc; saídas em $TMP/out e $TMP/err
roda() {
  ( cd "$REPO" && HOME="$4" CLAUDE_PLUGIN_ROOT="$5" TMPDIR="$TMP" \
      "$1" -c "$2" <"$3" >"$TMP/out" 2>"$TMP/err" )
  echo $?
}

echo "== nenhum comando do hooks.json tem a guarda de convidado =="
n_lidos="$(wc -l < "$TMP/comandos" | tr -d ' ')"
n_json="$(grep -c '"command":' "$HOOKS_JSON")"   # a chave; "type": "command" não conta
check "o node leu os $n_json comandos do arquivo" "$([ "$n_lidos" -gt 0 ] && [ "$n_lidos" = "$n_json" ] && echo ok || echo fail)"
com_guarda=""; sem_script=""
while IFS="$TAB" read -r evento cmd; do
  case "$cmd" in *team-manifest*|*KIT_VAMOO_HOOKS*) com_guarda="$com_guarda $(rotulo "$evento" "$cmd")" ;; esac
  case "$cmd" in *'${CLAUDE_PLUGIN_ROOT}/'*) ;; *) sem_script="$sem_script $(rotulo "$evento" "$cmd")" ;; esac
done < "$TMP/comandos"
check "nenhum comando olha o .team-manifest nem o KIT_VAMOO_HOOKS" "$([ -z "$com_guarda" ] && echo ok || echo fail)"
[ -n "$com_guarda" ] && printf '        → com a guarda:%s\n' "$com_guarda"
check "todo comando chama um script do CLAUDE_PLUGIN_ROOT" "$([ -z "$sem_script" ] && echo ok || echo fail)"
[ -n "$sem_script" ] && printf '        → sem script:%s\n' "$sem_script"

# As máquinas: mentorado (sem manifesto) e as três do time.
casa() { # casa <nome> [conteúdo do manifesto]
  local h="$TMP/home-$1"; mkdir -p "$h/.claude"
  [ $# -gt 1 ] && printf '%s\n' "$2" > "$h/.claude/.team-manifest"
  printf '%s' "$h"
}
CASAS="mentorado:$(casa mentorado)
time-sem-marcador:$(casa time-sem-marcador 'skill/vamoo-verificacao')
time-cortado:$(casa time-cortado "$(printf 'team 0.0.0 x\nnucleo=plugin')")
time-na-volta:$(casa time-na-volta "$(printf 'team 0.0.0 x\nnucleo=settings')")"

echo "== todo comando chega ao script em toda máquina =="
# Troca cada script por um eco: prova TODO hook registrado, não só o pre-bash, sem depender do
# que cada script faz com o payload.
STUB="$TMP/stub-root"
while IFS="$TAB" read -r evento cmd; do
  rel="$(printf '%s' "$cmd" | sed -n 's/.*\${CLAUDE_PLUGIN_ROOT}\/\([^" ]*\).*/\1/p')"
  [ -n "$rel" ] || continue
  mkdir -p "$STUB/$(dirname "$rel")"; printf '#!/bin/sh\necho PASSOU\n' > "$STUB/$rel"; chmod +x "$STUB/$rel"
done < "$TMP/comandos"
PAYLOAD_BASH="$TMP/payload-bash.json"; payload PreToolUse > "$PAYLOAD_BASH"
printf '%s\n' "$CASAS" | while IFS=: read -r nome h; do
  cederam=""
  while IFS="$TAB" read -r evento cmd; do
    for sh_ in sh bash; do
      roda "$sh_" "$cmd" "$PAYLOAD_BASH" "$h" "$STUB" >/dev/null
      grep -qx PASSOU "$TMP/out" || cederam="$cederam $sh_:$(rotulo "$evento" "$cmd")"
    done
  done < "$TMP/comandos"
  check "$nome: todo comando chega ao script" "$([ -z "$cederam" ] && echo ok || echo fail)"
  [ -n "$cederam" ] && printf '        → pararam antes:%s\n' "$cederam"
done > "$TMP/casas.log"
cat "$TMP/casas.log"
falhas=$((falhas + $(grep -c '  FALHA' "$TMP/casas.log")))

echo "== o pre-bash de verdade bloqueia o commit na main em toda máquina =="
pre_bash=""
while IFS="$TAB" read -r evento cmd; do
  case "$evento:$cmd" in PreToolUse:*pre-bash.sh*) pre_bash="$cmd"; break ;; esac
done < "$TMP/comandos"
check "o pre-bash está registrado no PreToolUse" "$([ -n "$pre_bash" ] && echo ok || echo fail)"
printf '%s\n' "$CASAS" | while IFS=: read -r nome h; do
  for sh_ in sh bash; do
    rc="$(roda "$sh_" "$pre_bash" "$PAYLOAD_BASH" "$h" "$RAIZ/plugin")"
    check "$nome, $sh_: commit na main sai 2 com a mensagem" \
      "$([ "$rc" = 2 ] && grep -q "cairia na branch 'main'" "$TMP/err" && echo ok || echo fail)"
  done
done > "$TMP/pre-bash.log"
cat "$TMP/pre-bash.log"
falhas=$((falhas + $(grep -c '  FALHA' "$TMP/pre-bash.log")))

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
