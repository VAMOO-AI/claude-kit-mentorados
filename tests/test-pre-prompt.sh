#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/pre-prompt.sh, o dispatcher do UserPromptSubmit.
#
# Até a 0.28.3 eram quatro entries no settings.json (session-size-guard, repo-session,
# branch-guard, memoria-worktree-link), cada um um processo `sh` mais um `bash <hook>` por
# prompt. O dispatcher lê o payload uma vez e tem que devolver o que os quatro devolviam:
# os avisos concatenados na ordem, o exit ≠ 0 do primeiro que falha, e nada quando ninguém
# fala. Cada caso passa pelo DISPATCHER, com os hooks reais ao lado dele.
#
# Hoje são seis: o precompact-devolve.sh abre a fila (lê o payload, é dele que sai o
# session_id do snapshot) e o worktree-seed-env.sh fecha (recebe /dev/null, como o link de
# memória — hook que não lê stdin não pode segurar o pipe do payload).
#
# Linha que começa com `@usuario ` (o aviso do session-size) é para a pessoa: sai num JSON,
# no systemMessage, e o resto vai para o modelo no additionalContext do mesmo JSON. Sem
# linha assim, a saída continua texto puro. Sem node, ou com a cadeia saindo ≠ 0, sai o
# texto sem o prefixo.
#
# Uso: bash tests/test-pre-prompt.sh [caminho-do-dispatcher]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/pre-prompt.sh}"
[ -f "$HOOK" ] || { echo "dispatcher não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
HOOKS_DIR="$(cd "$(dirname "$HOOK")" && pwd)"
SCRIPTS_DIR="$(cd "$HOOKS_DIR/../scripts" && pwd)"
BASH_BIN="$(command -v bash)"
# Hook do plugin resolve o hookjson.js em ../scripts: pasta de hooks avulsa precisa do
# helper ao lado, senão o hook sai 0 fail-open e o teste aprovaria um dispatcher mudo.
árvore() { mkdir -p "$1/hooks" "$1/scripts"; cp "$SCRIPTS_DIR/hookjson.js" "$1/scripts/"; printf '%s' "$1/hooks"; }
# PATH só com o que o dispatcher e os hooks falsos usam — sem node.
sem_node() { mkdir -p "$1"; for c in cat sed; do ln -s "$(command -v "$c")" "$1/$c"; done; printf '%s' "$1"; }

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
TP="$TMP/transcript.jsonl"; : > "$TP"
linhas() { : > "$TP"; local i=0; while [ "$i" -lt "$1" ]; do echo '{"x":1}' >> "$TP"; i=$((i+1)); done; }

# roda <sid> <cwd> [pasta-de-hooks] [PATH] → rc; stdout em $TMP/out, stderr em $TMP/err
roda() {
  S="$1" D="$2" T="$TP" node -e 'process.stdout.write(JSON.stringify({session_id:process.env.S,cwd:process.env.D,transcript_path:process.env.T,prompt:"oi"}))' \
    | ( cd "$2" && PATH="${4:-$PATH}" PRE_PROMPT_HOOKS_DIR="${3:-}" "$BASH_BIN" "$HOOK" ) >"$TMP/out" 2>"$TMP/err"
  echo $?
}
# json <campo.com.pontos> → o valor no JSON de $TMP/out; <ausente> se o campo não existe;
# <não é JSON> se a saída não é UM objeto JSON (o Claude Code só lê JSON assim).
json() {
  node -e '
    let o;
    try { o = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch (e) { process.stdout.write("<não é JSON>"); process.exit(0); }
    for (const k of process.argv[1].split(".")) o = o == null ? undefined : o[k];
    process.stdout.write(o === undefined ? "<ausente>" : String(o));
  ' "$1" < "$TMP/out"
}
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
espera_rc() { [ "$1" = "$2" ] && ok "$3" || falha "$3 (esperado rc=$1, veio rc=$2)"; }
contem()     { grep -qF -- "$2" "$1" && ok "$3" || falha "$3 (não achei '$2' em: $(cat "$1"))"; }
nao_contem() { grep -qF -- "$2" "$1" && falha "$3 (achei '$2')" || ok "$3"; }
igual()   { [ "$1" = "$2" ] && ok "$3" || falha "$3 (esperado '$1', veio '$2')"; }
tem()     { case "$2" in *"$1"*) ok "$3" ;; *) falha "$3 (não achei '$1' em: $2)" ;; esac; }
nao_tem() { case "$2" in *"$1"*) falha "$3 (achei '$1' em: $2)" ;; *) ok "$3" ;; esac; }
texto_puro() { case "$(head -c1 "$TMP/out")" in "{") falha "$1 (saiu JSON: $(cat "$TMP/out"))" ;; *) ok "$1" ;; esac; }

echo "== primeiro prompt: silêncio, e o repo-session registrou a sessão =="
rc=$(roda s1 "$REPO")
espera_rc 0 "$rc" "sai 0"
[ -s "$TMP/out" ] && falha "stdout deveria estar vazio: $(cat "$TMP/out")" || ok "stdout vazio (nenhum hook tinha o que dizer)"
H=$(printf '%s' "$(git -C "$REPO" rev-parse --show-toplevel)" | shasum | awk '{print $1}')
[ -f "$HOME/.claude/.cache/repo-sessions/$H/s1" ] && ok "repo-session marcou s1 no repo" || falha "repo-session não marcou a sessão"

echo
echo "== transcript de 700 linhas: o session-size vai para a pessoa, o branch-guard para o modelo =="
linhas 700
git -C "$REPO" switch -q -c feat/outra
rc=$(roda s1 "$REPO")
espera_rc 0 "$rc" "sai 0"
aviso=$(json systemMessage)
tem "~600 linhas" "$aviso" "systemMessage traz o aviso do session-size"
case "$aviso" in "@usuario"*|"<"*) falha "systemMessage com o prefixo, ou ausente: $aviso" ;; *) ok "systemMessage sem o prefixo @usuario" ;; esac
igual "UserPromptSubmit" "$(json hookSpecificOutput.hookEventName)" "hookEventName é UserPromptSubmit"
modelo=$(json hookSpecificOutput.additionalContext)
tem "branch-guard" "$modelo" "o aviso do branch-guard (main → feat/outra) continua chegando ao modelo"
nao_tem "session-size" "$modelo" "o session-size não entra no additionalContext"
rc=$(roda s1 "$REPO")
[ -s "$TMP/out" ] && falha "repetiu aviso: $(cat "$TMP/out")" || ok "prompt seguinte: nada a repetir"
rc=$(roda s2 "$REPO")
tem "~600 linhas" "$(json systemMessage)" "sessão nova com 700 linhas: aviso para a pessoa"
igual "<ausente>" "$(json hookSpecificOutput)" "…e sem additionalContext quando só a pessoa tem aviso"

echo
echo "== aviso para a pessoa com outros hooks falando: separa, na ordem =="
PESSOA="$(árvore "$TMP/pessoa")"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo "@usuario pra-pessoa"' 'exit 0' > "$PESSOA/session-size-guard.sh"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo segundo' 'exit 0' > "$PESSOA/branch-guard.sh"
printf '%s\n' '#!/bin/bash' 'echo terceiro' 'exit 0' > "$PESSOA/memoria-worktree-link.sh"
rc=$(roda s5 "$REPO" "$PESSOA")
espera_rc 0 "$rc" "sai 0"
igual "pra-pessoa" "$(json systemMessage)" "systemMessage é só a linha @usuario, sem o prefixo"
igual "$(printf 'segundo\nterceiro')" "$(json hookSpecificOutput.additionalContext)" "additionalContext tem o resto, na ordem dos hooks"

echo
echo "== seis hooks: o devolve abre a fila com o payload, o seed-env fecha com /dev/null =="
SEIS="$(árvore "$TMP/seis")"
printf '%s\n' '#!/bin/bash' 'case "$(cat)" in *\"session_id\":\"s4\"*) echo devolve-leu-o-payload ;; *) echo devolve-sem-payload ;; esac' 'exit 0' > "$SEIS/precompact-devolve.sh"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo meio' 'exit 0' > "$SEIS/branch-guard.sh"
printf '%s\n' '#!/bin/bash' 'echo "seed-leu:[$(cat)]"' 'exit 0' > "$SEIS/worktree-seed-env.sh"
rc=$(roda s4 "$REPO" "$SEIS")
espera_rc 0 "$rc" "sai 0"
igual "$(printf 'devolve-leu-o-payload\nmeio\nseed-leu:[]')" "$(cat "$TMP/out")" "devolve primeiro com o payload, seed-env por último com stdin vazio"

echo
echo "== sem linha @usuario, texto puro como antes, na ordem =="
TEXTO="$(árvore "$TMP/texto")"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo primeiro' 'exit 0' > "$TEXTO/session-size-guard.sh"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo segundo' 'exit 0' > "$TEXTO/branch-guard.sh"
rc=$(roda s6 "$REPO" "$TEXTO")
espera_rc 0 "$rc" "sai 0"
texto_puro "não vira JSON"
igual "$(printf 'primeiro\nsegundo')" "$(cat "$TMP/out")" "os textos chegam concatenados, na ordem"

echo
echo "== sem node (ou com o node quebrado): texto puro, sem o prefixo =="
SEM="$(sem_node "$TMP/sem-node")"
rc=$(roda s7 "$REPO" "$PESSOA" "$SEM")
espera_rc 0 "$rc" "sem node: sai 0"
igual "$(printf 'pra-pessoa\nsegundo\nterceiro')" "$(cat "$TMP/out")" "sem node: tudo em texto, o aviso sem @usuario"
QUEBRADO="$(sem_node "$TMP/node-quebrado")"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$QUEBRADO/node"; chmod +x "$QUEBRADO/node"
rc=$(roda s8 "$REPO" "$PESSOA" "$QUEBRADO")
espera_rc 0 "$rc" "node que falha: sai 0"
igual "$(printf 'pra-pessoa\nsegundo\nterceiro')" "$(cat "$TMP/out")" "node que falha: mesmo texto de quem não tem node"

echo
echo "== hook ausente é pulado; pasta vazia sai 0 calado =="
SO_UM="$(árvore "$TMP/so-um")"; cp "$HOOKS_DIR/branch-guard.sh" "$SO_UM/"
git -C "$REPO" switch -q main
rc=$(roda s1 "$REPO" "$SO_UM")
espera_rc 0 "$rc" "só branch-guard instalado: sai 0"
contem "$TMP/out" "branch-guard" "…e o branch-guard que existe segue avisando"
texto_puro "…em texto puro, como antes"
VAZIO="$(árvore "$TMP/vazio")"
rc=$(roda s1 "$REPO" "$VAZIO")
espera_rc 0 "$rc" "pasta sem hook sai 0"
[ -s "$TMP/out" ] && falha "stdout deveria estar vazio" || ok "stdout vazio"

echo
echo "== cadeia: o primeiro código ≠ 0 encerra, com o stdout e o stderr dele =="
FALSOS="$(árvore "$TMP/falsos")"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo "@usuario aviso-do-primeiro"' 'exit 0' > "$FALSOS/session-size-guard.sh"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo bloqueio' 'echo motivo >&2' 'exit 2' > "$FALSOS/branch-guard.sh"
printf '%s\n' '#!/bin/bash' 'echo NAO-DEVIA-RODAR' 'exit 0' > "$FALSOS/memoria-worktree-link.sh"
rc=$(roda s9 "$REPO" "$FALSOS")
espera_rc 2 "$rc" "exit 2 do hook vira exit 2 da cadeia"
contem "$TMP/out" 'aviso-do-primeiro' "o que os anteriores disseram é repassado"
nao_contem "$TMP/out" '@usuario' "…sem o prefixo @usuario"
texto_puro "…em texto puro, como antes (JSON mudaria o efeito do exit ≠ 0)"
contem "$TMP/out" 'bloqueio' "stdout do hook que saiu ≠ 0 é repassado"
contem "$TMP/err" 'motivo' "stderr do hook que saiu ≠ 0 é repassado"
nao_contem "$TMP/out" 'NAO-DEVIA-RODAR' "o hook seguinte não roda"

echo
echo "== fail-open =="
rc=$(printf '' | bash "$HOOK" >/dev/null 2>&1; echo $?)
espera_rc 0 "$rc" "payload vazio sai 0"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
