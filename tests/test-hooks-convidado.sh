#!/usr/bin/env bash
# Prova da guarda de convidado do plugin/hooks/hooks.json.
#
# Com o kit do time e este plugin ligados na mesma máquina, cada hook rodava duas
# vezes: dois sons por turno, o mesmo texto duas vezes no contexto, corrida no
# dotcontext criando sessões órfãs, e o modelo lendo a mensagem de bloqueio daqui no
# lugar da do time. Quem cede é o plugin, que é o convidado: o update.sh do time grava
# ~/.claude/.team-manifest, e o plugin nunca grava esse arquivo. Com ele presente, todo
# comando do hooks.json sai 0 antes de abrir o script — a não ser com KIT_VAMOO_HOOKS=1,
# a escotilha para testar o plugin numa máquina que tem os dois kits.
#
# Exceção única: o codex-espelho.sh NÃO leva a guarda. O kit do time não registra o espelho
# (o update.sh só refresca os guards de ~/.codex/hooks, e nunca as skills de ~/.codex/skills e
# ~/.agents/skills), então com a guarda ele não rodava em máquina nenhuma do time e os links
# para ~/.claude/skills ficariam pendurados quando as skills saírem de lá (F7). Ele não roda
# em dobro com nada: só copia, só quando a versão do plugin muda, e um guard já igual ao do
# update.sh não é reescrito (a fonte dos dois é o mesmo plugin instalado). Quem reescrever a
# guarda na F9 (`nucleo=plugin`) não deve recolocá-la nele.
#
# Corte da F9 (docs/plano-nucleo-plugin.md do kit do time): quando o update.sh do time tira
# os hooks do núcleo do settings.json dele, grava a linha `nucleo=plugin` no .team-manifest, e
# a partir daí quem roda é este plugin. Por isso a guarda cede só com o manifesto SEM essa
# linha. Nunca pode haver zero guards nem guard em dobro: guard que falha deixa o comando
# passar sem aviso.
#
# O que precisa continuar valendo:
#   - todo comando registrado começa com a guarda, inclusive hook que entrar depois, menos o
#     codex-espelho, que NÃO começa com ela;
#   - com o manifesto sem `nucleo=plugin`, os comandos saem 0, calados, e não escrevem nada
#     no HOME;
#   - com `nucleo=plugin` no manifesto, sem manifesto (a máquina de um mentorado) ou com a
#     escotilha, o hook age.
#
# Uso: bash tests/test-hooks-convidado.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOKS_JSON="$RAIZ/plugin/hooks/hooks.json"
[ -f "$HOOKS_JSON" ] || { echo "hooks.json não encontrado: $HOOKS_JSON"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
# Rodado de uma sessão com a escotilha aberta, o teste herdaria o KIT_VAMOO_HOOKS=1 e
# reprovaria uma guarda que está certa.
unset KIT_VAMOO_HOOKS
# O codex-espelho roda sem a guarda e lê CODEX_HOME e CLAUDE_PLUGIN_DATA do ambiente: herdados,
# o teste escreveria no Codex de quem o rodou (o HOME é trocado, esses dois não).
unset CODEX_HOME CLAUDE_PLUGIN_DATA

# Desde a F9 a guarda cede só quando o manifesto existe E não tem a linha exata `nucleo=plugin`,
# que o update.sh do time grava no corte. O trecho `! grep -qx 'nucleo=plugin'` é o que o
# update.sh do time procura no hooks.json instalado antes de cortar: pelo conteúdo, não só pelo
# número da versão.
GUARDA='[ -f "$HOME/.claude/.team-manifest" ] && [ "${KIT_VAMOO_HOOKS:-}" != 1 ] && ! grep -qx '"'"'nucleo=plugin'"'"' "$HOME/.claude/.team-manifest" 2>/dev/null && exit 0; '
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

# Repositório na main e um payload que dá assunto a todo hook: um `git commit` para o
# pre-bash bloquear e um package.json para o path-rules injetar regra.
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

# roda <shell> <comando> <payload> <home> [KIT_VAMOO_HOOKS] → imprime o rc; saídas em $TMP/out e $TMP/err
# O stdin vem de arquivo, não de pipe: com a guarda o comando sai sem ler o payload, e o
# SIGPIPE de quem escreve no pipe viraria o rc do caso.
roda() {
  ( cd "$REPO" && HOME="$4" CLAUDE_PLUGIN_ROOT="$RAIZ/plugin" TMPDIR="$TMP" \
      KIT_VAMOO_HOOKS="${5:-}" "$1" -c "$2" <"$3" >"$TMP/out" 2>"$TMP/err" )
  echo $?
}
retrato() { find "$1" -print | LC_ALL=C sort; }

echo "== todo comando do hooks.json começa com a guarda =="
n_lidos="$(wc -l < "$TMP/comandos" | tr -d ' ')"
n_json="$(grep -c '"command":' "$HOOKS_JSON")"   # a chave; "type": "command" não conta
check "o node leu os $n_json comandos do arquivo" "$([ "$n_lidos" -gt 0 ] && [ "$n_lidos" = "$n_json" ] && echo ok || echo fail)"
sem_guarda=""; espelho_com_guarda=""; espelho_achado=""
while IFS="$TAB" read -r evento cmd; do
  case "$cmd" in
    *codex-espelho.sh*)
      espelho_achado=1
      case "$cmd" in *team-manifest*) espelho_com_guarda="$(rotulo "$evento" "$cmd")" ;; esac ;;
    "$GUARDA"*) ;;
    *) sem_guarda="$sem_guarda $(rotulo "$evento" "$cmd")" ;;
  esac
done < "$TMP/comandos"
check "nenhum comando sem a guarda (fora o codex-espelho)" "$([ -z "$sem_guarda" ] && echo ok || echo fail)"
[ -n "$sem_guarda" ] && printf '        → sem a guarda:%s\n' "$sem_guarda"
check "o codex-espelho está registrado e roda sem a guarda" "$([ -n "$espelho_achado" ] && [ -z "$espelho_com_guarda" ] && echo ok || echo fail)"
[ -n "$espelho_com_guarda" ] && printf '        → com a guarda: %s\n' "$espelho_com_guarda"

echo "== máquina com o kit do time: todo comando sai 0, calado, sem tocar no HOME =="
HOME_TIME="$TMP/home-time"; mkdir -p "$HOME_TIME/.claude"
echo "skill/vamoo-verificacao" > "$HOME_TIME/.claude/.team-manifest"
antes="$(retrato "$HOME_TIME")"
# sh também: no CI (ubuntu) ele é o dash, o mais estrito dos dois.
for sh_ in sh bash; do
  sairam=""; falaram=""
  while IFS="$TAB" read -r evento cmd; do
    p="$TMP/payload-$evento.json"; [ -f "$p" ] || payload "$evento" > "$p"
    rc="$(roda "$sh_" "$cmd" "$p" "$HOME_TIME")"
    [ "$rc" = 0 ] || sairam="$sairam $(rotulo "$evento" "$cmd")=rc$rc"
    if [ -s "$TMP/out" ] || [ -s "$TMP/err" ]; then falaram="$falaram $(rotulo "$evento" "$cmd")"; fi
  done < "$TMP/comandos"
  check "$sh_: todos saem com rc 0" "$([ -z "$sairam" ] && echo ok || echo fail)"
  [ -n "$sairam" ] && printf '        →%s\n' "$sairam"
  check "$sh_: nenhum escreve no stdout nem no stderr" "$([ -z "$falaram" ] && echo ok || echo fail)"
  [ -n "$falaram" ] && printf '        → falaram:%s\n' "$falaram"
done
check "o HOME continua só com o marcador" "$([ "$(retrato "$HOME_TIME")" = "$antes" ] && echo ok || echo fail)"

pre_bash=""
while IFS="$TAB" read -r evento cmd; do
  case "$evento:$cmd" in PreToolUse:*pre-bash.sh*) pre_bash="$cmd"; break ;; esac
done < "$TMP/comandos"
PAYLOAD_BASH="$TMP/payload-bash.json"; payload PreToolUse > "$PAYLOAD_BASH"

echo "== KIT_VAMOO_HOOKS=1 religa os hooks mesmo com o marcador =="
check "o pre-bash está registrado no PreToolUse" "$([ -n "$pre_bash" ] && echo ok || echo fail)"
HOME_ESC="$TMP/home-escotilha"; mkdir -p "$HOME_ESC/.claude"
echo "skill/vamoo-verificacao" > "$HOME_ESC/.claude/.team-manifest"
for sh_ in sh bash; do
  rc="$(roda "$sh_" "$pre_bash" "$PAYLOAD_BASH" "$HOME_ESC" 1)"
  check "$sh_: commit na main sai 2" "$([ "$rc" = 2 ] && echo ok || echo fail)"
  check "$sh_: a mensagem de bloqueio chega no stderr" "$(grep -q "cairia na branch 'main'" "$TMP/err" && echo ok || echo fail)"
done
rc="$(roda bash "$pre_bash" "$PAYLOAD_BASH" "$HOME_ESC" 0)"
check "KIT_VAMOO_HOOKS=0 não abre a escotilha, só o 1" "$([ "$rc" = 0 ] && [ ! -s "$TMP/err" ] && echo ok || echo fail)"

echo "== sem manifesto (máquina de mentorado), o hook age como sempre =="
HOME_MENTORADO="$TMP/home-mentorado"; mkdir -p "$HOME_MENTORADO/.claude"
for sh_ in sh bash; do
  rc="$(roda "$sh_" "$pre_bash" "$PAYLOAD_BASH" "$HOME_MENTORADO")"
  check "$sh_: commit na main sai 2" "$([ "$rc" = 2 ] && echo ok || echo fail)"
  check "$sh_: a mensagem de bloqueio chega no stderr" "$(grep -q "cairia na branch 'main'" "$TMP/err" && echo ok || echo fail)"
done

echo "== corte da F9: com nucleo=plugin no manifesto, o hook age =="
HOME_CORTE="$TMP/home-corte"; mkdir -p "$HOME_CORTE/.claude"
printf 'team 0.0.0 x\nskill/vamoo-verificacao\nnucleo=plugin\n' > "$HOME_CORTE/.claude/.team-manifest"
for sh_ in sh bash; do
  rc="$(roda "$sh_" "$pre_bash" "$PAYLOAD_BASH" "$HOME_CORTE")"
  check "$sh_: commit na main sai 2" "$([ "$rc" = 2 ] && echo ok || echo fail)"
  check "$sh_: a mensagem de bloqueio chega no stderr" "$(grep -q "cairia na branch 'main'" "$TMP/err" && echo ok || echo fail)"
done
# Linha exata: um texto que só contém o marcador (comentário, outro valor) não é o corte.
HOME_QUASE="$TMP/home-quase"; mkdir -p "$HOME_QUASE/.claude"
printf 'team 0.0.0 x\n# nucleo=plugin\nnucleo=plugin-nao\n' > "$HOME_QUASE/.claude/.team-manifest"
rc="$(roda bash "$pre_bash" "$PAYLOAD_BASH" "$HOME_QUASE")"
check "marcador que não é a linha exata não corta: o hook cede" "$([ "$rc" = 0 ] && [ ! -s "$TMP/err" ] && echo ok || echo fail)"

echo "== a guarda de cada comando, isolada: quem cede e quem passa =="
# Troca o script de cada comando por um eco: prova a guarda de TODO hook registrado, não só a
# do pre-bash, sem depender do que cada script faz com o payload.
cortados_cederam=""; time_passou=""; mentorado_cedeu=""
while IFS="$TAB" read -r evento cmd; do
  case "$cmd" in *codex-espelho.sh*) continue ;; esac
  so_guarda="${cmd%%; *}; echo PASSOU"
  for sh_ in sh bash; do
    roda "$sh_" "$so_guarda" "$PAYLOAD_BASH" "$HOME_CORTE" >/dev/null
    grep -qx PASSOU "$TMP/out" || cortados_cederam="$cortados_cederam $sh_:$(rotulo "$evento" "$cmd")"
    roda "$sh_" "$so_guarda" "$PAYLOAD_BASH" "$HOME_MENTORADO" >/dev/null
    grep -qx PASSOU "$TMP/out" || mentorado_cedeu="$mentorado_cedeu $sh_:$(rotulo "$evento" "$cmd")"
    roda "$sh_" "$so_guarda" "$PAYLOAD_BASH" "$HOME_TIME" >/dev/null
    [ -s "$TMP/out" ] && time_passou="$time_passou $sh_:$(rotulo "$evento" "$cmd")"
  done
done < "$TMP/comandos"
check "com nucleo=plugin, todo comando passa da guarda" "$([ -z "$cortados_cederam" ] && echo ok || echo fail)"
[ -n "$cortados_cederam" ] && printf '        → cederam:%s\n' "$cortados_cederam"
check "sem manifesto, todo comando passa da guarda" "$([ -z "$mentorado_cedeu" ] && echo ok || echo fail)"
[ -n "$mentorado_cedeu" ] && printf '        → cederam:%s\n' "$mentorado_cedeu"
check "com manifesto sem nucleo=plugin, todo comando sai na guarda" "$([ -z "$time_passou" ] && echo ok || echo fail)"
[ -n "$time_passou" ] && printf '        → passaram:%s\n' "$time_passou"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
