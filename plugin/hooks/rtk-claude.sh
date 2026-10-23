#!/usr/bin/env bash
# PreToolUse(Bash) → RTK no Claude Code: delega para `rtk hook claude`, menos quando
# reescrever quebraria o comando.
#
# Por que existe, se o settings chamava `rtk hook claude` direto: sessão isolada em
# worktree tem um guard do próprio harness que só sabe ler `git` como PRIMEIRO token
# do comando. Reescrever `git add x` para `rtk git add x` esconde o git atrás do
# launcher, e a recusa sai assim:
#
#   runs rtk with a git command among its operands: what runs it, and from which
#   directory or root, cannot be read here … Refusing to run it
#
# O comando NÃO roda. A economia de tokens do RTK custa a operação inteira — em
# 03/09/2026 isso pegou um `git add` de um arquivo só, e a sessão passou a chamar
# `/usr/bin/git` na mão em tudo.
#
# O irmão deste arquivo é o `rtk-codex.sh`, que faz a mesma guarda no dialeto do
# Codex (comando como array). Regra nova aqui pede caso novo em
# tests/test-rtk-claude.sh — e provavelmente o espelho lá.
#
# Saída que vai para OUTRO comando não pode passar pelo filtro do rtk: ele formata
# para o modelo ler, não para um pipe consumir. `rtk diff A B | grep -c '^[<>]'`
# devolveu 0 para 45 linhas de diferença (03/09/2026) e `rg` via rtk deu 0 matches
# para string presente (31/08) — duas auditorias com resultado corrompido. Só
# reescreve comando cujo stdout vai direto para o modelo (ver saida_consumida).
#
# HOLDOUT (grupo de controle), desligado por padrão: com RTK_HOLDOUT_PCT=N, N% dos
# comandos ELEGÍVEIS saem sem reescrita nenhuma e viram grupo de controle. As duas
# populações vão para um ledger, e o scripts/rtk-holdout.sh mede, no transcript, o
# tamanho do que o modelo REALMENTE recebeu em cada braço. É o que o número do
# `rtk gain` não tem: ele compara a saída bruta que o próprio rtk capturou com a
# filtrada, sem contar que o harness truncaria a bruta antes de mostrar ao modelo.
# Ver docs/rtk-holdout.md.
#
# Fail-open em tudo: sem rtk, sem node, sem payload → o comando original segue.
#
# No plugin, o pre-bash.sh o chama por último e só quando nenhum guard falou antes: com o
# `ask` do check-careful na mesa, a pessoa aprova o comando que ela vê, cru, e o pre-bash não
# precisa fundir dois JSONs. Sem rtk instalado (o caso de quase todo mundo) o hook é inerte.
# Os campos do payload vêm do kit_campos do pre-bash (leitura única); chamado à mão, o hook
# lê sozinho pelo scripts/hookjson.js. Porte do kit do time (F3 do núcleo único, #241).
set -uo pipefail

# 0 quando o stdout do comando alimenta OUTRO comando ou um arquivo: `|` (o `||` não
# encadeia saída e fica de fora), `$(`, crase, xargs, ou `>` para arquivo — `2>&1`,
# `>&2` e `/dev/null` não são arquivo. Pipe dentro de aspas conta como pipe: o falso
# positivo custa alguns tokens; o falso negativo custou uma auditoria.
saida_consumida() {
  local c="$1" resto
  resto=${c//"||"/}
  case "$resto" in *'|'*) return 0 ;; esac
  case "$c" in *'$('*|*'`'*|*xargs*) return 0 ;; esac
  case "$c" in *'>'*)
    resto=$(printf '%s' "$c" | sed -E 's/[0-9]*>&[0-9-]+//g; s/&?[0-9]*>>?[[:space:]]*\/dev\/null//g')
    case "$resto" in *'>'*) return 0 ;; esac ;;
  esac
  return 1
}

# Uma linha por sorteio no ledger, e NADA no stdout: o pre-bash.sh lê o stdout deste
# hook como decisão de permissão e tenta fundir como JSON — um `echo` solto aqui vira
# saída malformada. Guarda hash do comando, não o comando: `export TOKEN=...` também
# passa por aqui.
holdout_registra() { # <braco> <comando>
  local dir soma hash fam sess
  dir="${RTK_HOLDOUT_DIR:-${HOME:-/tmp}/.claude/.cache/rtk-holdout}"
  mkdir -p "$dir" 2>/dev/null || return 0
  if command -v shasum >/dev/null 2>&1; then soma=(shasum -a 256)
  elif command -v sha256sum >/dev/null 2>&1; then soma=(sha256sum)
  else return 0; fi
  hash=$(printf '%s' "$2" | "${soma[@]}" 2>/dev/null | cut -c1-16)
  [ -n "$hash" ] || return 0
  fam=${2%% *}; fam=${fam##*/}
  sess=$sid
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${fam:-?}" "$hash" "${sess:-?}" \
    >> "$dir/ledger.tsv" 2>/dev/null
  return 0
}

# Comando que toca arquivo de segredo NÃO é reescrito (15/10/2026). O `permissions.deny`
# com `Read(//**/.env.local)` & cia. só reconhece a leitura no comando cru: com o harness
# sozinho, `cat`/`grep`/`head` num .env.local falso dentro do cwd foram negados em bypass
# e em acceptEdits. Reescrito, o mesmo comando leu nos dois modos — `cat` vira `rtk read`,
# que o harness não lê como leitura, e `grep` vira `rtk grep` com `permissionDecision:
# allow`, que nem chega a perguntar. Medição em docs/medicao-guards-2026-10-15.md.
#
# A lista sai do próprio deny (20/10/2026): as regras `Read()` dos settings que o harness
# carrega, o do usuário, o gerenciado e os do projeto (pelo CLAUDE_PROJECT_DIR que o harness
# passa ao hook). Até ali ela era um espelho mantido à mão, e o `~/.codex/auth.json`, o
# token da Vercel e as cópias `.bak` do cofre ficaram fora dos dois. Casar demais só custa
# o filtro do rtk; casar de menos devolve ao harness um comando que ele não lê como leitura.
#
# Cada regra vira até duas agulhas, o nome do fim e a pasta logo acima, em qualquer ordem:
# `~/.aws/credentials` pega `cd ~/.aws && cat credentials`, e `~/.claude/state/**` exige
# `.claude` e `state`, senão todo comando em ~/.claude perderia o filtro. A fronteira de
# nome não deixa `.env` casar `.env.example` nem `process.env`. Sem distinção de caixa: no
# APFS `cat .ENV.LOCAL` abre o .env.local.

# glob_ere <segmento>: glob do gitignore → ERE. O núcleo vai em $ERE; $EL e $ER dizem se a
# ponta esquerda e a direita precisam de fronteira de nome (não precisam quando o glob já
# começa ou acaba em curinga). `*`, `?`, `[…]` e `{…}` viram "qualquer coisa sem espaço nem
# barra". Sem subshell: roda uma vez por regra, a cada comando.
glob_ere() {
  local s="$1" c i=0 n=${#1}
  ERE=""; EL=1; ER=1
  while [ "$i" -lt "$n" ]; do
    c=${s:$i:1}
    case "$c" in
      '*') ERE="$ERE[^[:space:]/]*" ;;
      '?') ERE="$ERE[^[:space:]/]" ;;
      '[') while [ "$i" -lt "$n" ] && [ "${s:$i:1}" != ']' ]; do i=$((i+1)); done
           ERE="$ERE[^[:space:]/]" ;;
      '{') while [ "$i" -lt "$n" ] && [ "${s:$i:1}" != '}' ]; do i=$((i+1)); done
           ERE="$ERE[^[:space:]/]*" ;;
      '\') i=$((i+1)); ERE="$ERE[${s:$i:1}]" ;;   # escape do gitignore: o seguinte é literal
      ' ') ERE="$ERE[[:space:]]+" ;;
      '.'|'+'|'^'|'$'|'('|')'|'|'|']'|'}') ERE="$ERE\\$c" ;;
      *) ERE="$ERE$c" ;;
    esac
    i=$((i+1))
  done
  case "$s" in '*'*|'?'*|'['*|'{'*) EL=0 ;; esac
  case "$s" in *'*'|*'?'|*']'|*'}') ER=0 ;; esac
}

# Fronteira de nome: o que não pode vir colado num nome de arquivo.
SEP='[^[:alnum:]_.-]'

# agulha <padrão de dentro do Read()>: a ERE da regra, em $AGULHA. Com pasta e nome, as
# duas ordens, e o separador entre elas pode ser um só (`.aws/credentials`) ou dois com
# qualquer coisa no meio (`.aws && cat credentials`). Regra que não tem nome nenhum, só
# curinga (`Read(//**)`), nega tudo, e aí nada é reescrito.
agulha() {
  local p="$1" s ult="" pen="" segs n1 l1 r1 n2 l2 r2
  p=${p#'//**/'}; p=${p#'//'}; p=${p#'~/'}; p=${p#'**/'}; p=${p#'./'}; p=${p#'/'}
  IFS=/ read -r -a segs <<< "$p"
  for s in ${segs[@]+"${segs[@]}"}; do
    case "$s" in *[!*?]*) pen=$ult; ult=$s ;; esac
  done
  if [ -z "$ult" ]; then AGULHA="."; return 0; fi
  glob_ere "$ult"; n2=$ERE; l2=$EL; r2=$ER
  if [ -z "$pen" ]; then
    AGULHA="${n2}"
    [ "$l2" = 1 ] && AGULHA="(^|$SEP)$AGULHA"
    [ "$r2" = 1 ] && AGULHA="$AGULHA($SEP|\$)"
    return 0
  fi
  glob_ere "$pen"; n1=$ERE; l1=$EL; r1=$ER
  par "$n1" "$l1" "$r1" "$n2" "$l2" "$r2"; AGULHA="($PAR"
  par "$n2" "$l2" "$r2" "$n1" "$l1" "$r1"; AGULHA="$AGULHA|$PAR)"
}

# par <núcleo A> <EL A> <ER A> <núcleo B> <EL B> <ER B>: A antes de B, com as fronteiras,
# em $PAR.
par() {
  local meio
  PAR=""
  [ "$2" = 1 ] && PAR="(^|$SEP)"
  if [ "$3" = 1 ] && [ "$5" = 1 ]; then meio="($SEP|$SEP.*$SEP)"
  elif [ "$3" = 1 ]; then meio="$SEP.*"
  elif [ "$5" = 1 ]; then meio=".*$SEP"
  else meio=".*"; fi
  PAR="$PAR$1$meio$4"
  [ "$6" = 1 ] && PAR="$PAR($SEP|\$)"
  return 0
}

# ere_segredo: a ERE de todas as regras Read() do deny, em $SEGREDO_ERE (vazia sem regra).
# Lê os settings que o harness carrega; o allow fica de fora, porque Read() liberado não é
# segredo. Montar a ERE custa um node e um laço por regra, e o hook roda
# em todo Bash: ela fica num cache que vale enquanto for mais novo que cada settings e que
# este arquivo, e enquanto a lista de settings lidos e o caminho deste hook forem os mesmos
# (settings que some invalida, e o cache de outra cópia do hook não serve). Mtime igual
# conta como velho e refaz.
ere_segredo() {
  local f arqs=() lista="" dir cache chave valido=1 r cab
  for f in "${HOME:-}/.claude/settings.json" \
           "/Library/Application Support/ClaudeCode/managed-settings.json" \
           /etc/claude-code/managed-settings.json \
           ${CLAUDE_PROJECT_DIR:+"$CLAUDE_PROJECT_DIR/.claude/settings.json"} \
           ${CLAUDE_PROJECT_DIR:+"$CLAUDE_PROJECT_DIR/.claude/settings.local.json"}; do
    [ -f "$f" ] && { arqs[${#arqs[@]}]=$f; lista="$lista|$f"; }
  done
  dir="${HOME:-/tmp}/.claude/.cache/rtk-segredo"
  chave="${CLAUDE_PROJECT_DIR:-sem-projeto}"
  cache="$dir/${chave//[^A-Za-z0-9._-]/_}"
  if [ -f "$cache" ]; then
    for f in ${arqs[@]+"${arqs[@]}"} "${BASH_SOURCE[0]}"; do
      [ "$cache" -nt "$f" ] || { valido=0; break; }
    done
    if [ "$valido" = 1 ]; then
      cab=""; SEGREDO_ERE=""
      { IFS= read -r cab; IFS= read -r SEGREDO_ERE; } < "$cache"
      [ "$cab" = "hook=${BASH_SOURCE[0]}$lista" ] && return 0
    fi
  fi
  SEGREDO_ERE=""
  if [ "${#arqs[@]}" -gt 0 ]; then
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      agulha "$r"
      SEGREDO_ERE="${SEGREDO_ERE:+$SEGREDO_ERE|}$AGULHA"
    done <<< "$(node -e '
      const fs = require("fs");
      for (const f of process.argv.slice(1)) {
        let d; try { d = JSON.parse(fs.readFileSync(f, "utf8")); } catch { continue; }
        for (const r of ((d && d.permissions && d.permissions.deny) || []))
          if (typeof r === "string" && r.startsWith("Read(") && r.endsWith(")")) console.log(r.slice(5, -1));
      }' "${arqs[@]}" 2>/dev/null)"
  fi
  mkdir -p "$dir" 2>/dev/null \
    && printf 'hook=%s%s\n%s\n' "${BASH_SOURCE[0]}" "$lista" "$SEGREDO_ERE" > "$cache.$$" 2>/dev/null \
    && mv -f "$cache.$$" "$cache" 2>/dev/null
  return 0
}

toca_segredo() { # <comando>
  local c="$1" rc
  ere_segredo
  [ -n "$SEGREDO_ERE" ] || return 1
  # Espaço escapado e quebra de linha viram espaço: as duas agulhas de uma regra chegam
  # separadas por `\ ` (`Application\ Support`) ou em linhas diferentes.
  c=${c//\\ / }; c=${c//$'\n'/ }
  printf '%s' "$c" | grep -qiE -- "$SEGREDO_ERE"; rc=$?
  # Só o 1 (não casou) libera a reescrita. ERE inválida (2) ou o printf morto por SIGPIPE
  # depois do match contam como segredo: na dúvida, o comando segue cru.
  [ "$rc" -ne 1 ]
}

command -v rtk >/dev/null 2>&1 || exit 0
# Sem node não dá para ler o deny nem o payload. Reescrever às cegas devolveria ao harness
# um `cat .env.local` que ele não reconhece como leitura: o comando segue cru.
command -v node >/dev/null 2>&1 || exit 0

payload=$(cat)
[ -z "$payload" ] && exit 0
if [ "${KIT_CAMPOS_LIDOS:-}" = 1 ]; then
  info="$(kit_campos cwd session_id tool_input.command)"
else
  H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
  [ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
  [ -f "$H" ] || exit 0
  info="$(printf '%s' "$payload" | node "$H" cwd session_id tool_input.command)"
fi
cwd_payload="${info%%$'\n'*}"; info="${info#*$'\n'}"
sid="${info%%$'\n'*}";         cmd="${info#*$'\n'}"
[ -n "$cmd" ] || exit 0
# Sobre o comando, não sobre o payload: o transcript_path sempre tem `.claude/`.
toca_segredo "$cmd" && exit 0

saida_consumida "$cmd" && exit 0

# `git push` (qualquer forma) nunca é reescrito, em NENHUM cwd. Todo padrão de force
# push do deny — Bash(git *push* … main/master …) — começa com `git `; reescrito para
# `rtk git push …` o deny não casa, e o guard de worktree do harness é por-cwd (não
# cobre um cwd fora de worktree): em bypass, fora de worktree, um force push em main
# vazou ao vivo (prova-hm, 20/10/2026). A economia de token num push é desprezível.
# Mesma forma de `git` palavra solta da guarda abaixo, seguida de `push` palavra no
# mesmo subcomando (sem cruzar ; & |): `git -C x push`, `sudo git push`, `&& git push`.
# O prefixo antes do `git` é qualquer coisa sem separador (`([^;&|]*[[:space:]])?`), não só
# `sudo`: o CLI casa o deny depois de atribuição de env e dos wrappers que ele tira
# (`command`, `timeout`, …), então `FOO=1 git push …` e `command git push …` também viram
# `rtk git push …` e escapam do deny (prova-hm, 20/10/2026). Reescrever um push vale ~0 token;
# sobre-aproximar aqui (não reescrever um `echo "git push"`) só custa isso.
if printf '%s' "$cmd" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*([^;&|]*[[:space:]])?git[[:space:]]+([^;&|]*[[:space:]])?push([[:space:]]|$)'; then
  exit 0
fi

# `git` como palavra solta em início de comando ou depois de ; & | && || — a
# substring não conta, senão "digitos"/"legitimos" viram falso positivo (#113).
if printf '%s' "$cmd" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)?git([[:space:]]|$)'; then
  # `.claude/worktrees/` é o layout do harness; `.claude-worktrees/` é o do kit.
  case "${cwd_payload:-$PWD}" in
    */.claude/worktrees/*|*/.claude-worktrees/*) exit 0 ;;
  esac
fi

# Sorteio do grupo de controle. Só com RTK_HOLDOUT_PCT > 0 — fora de campanha isto
# é um teste de string e o caminho normal segue byte a byte igual ao de antes.
#
# Elegível = comando que o rtk REESCREVERIA (`rtk hook check` é o dry-run do próprio
# engine, ~7 ms). Sem esse filtro os dois braços encheriam de `mkdir`/`chmod`, que
# o rtk nunca tocaria, e a economia medida diluiria para perto de zero. O mesmo
# teste vale para os dois braços: quem decide é o rtk, não uma lista nossa.
#
# O `rtk hook check` recebe o comando como ARGUMENTO, e o rtk-codex.sh tem uma lista
# que barra `.env`/`SERVICE_ROLE`/`id_rsa` antes de chegar num ponto desses. Aqui não
# tem, de propósito: o comando já vai como argv para o `bash -c` que vai executá-lo de
# qualquer jeito, e no braço tratado o rtk recebe o mesmo texto pelo stdin. A exposição
# não é nova, e a lista de lá existe por outro motivo (não sobrescrever o `ask` do
# check-careful). O que NÃO pode acontecer é o texto ficar gravado: por isso o ledger
# guarda hash.
holdout_pct="${RTK_HOLDOUT_PCT:-0}"
case "$holdout_pct" in ''|*[!0-9]*) holdout_pct=0 ;; esac
if [ "$holdout_pct" -gt 0 ]; then
  reescrito=$(rtk hook check "$cmd" 2>/dev/null | head -1)
  if [ -n "$reescrito" ] && [ "$reescrito" != "$cmd" ]; then
    # O sorteio NÃO pode sair do $RANDOM cru. Cada comando roda o hook num bash
    # novo, e o bash 3.2 (o /bin/bash do macOS) semeia o RANDOM com time+pid: numa
    # rajada de comandos os pids são quase consecutivos e o primeiro valor da
    # sequência anda junto com eles. Medido: 100 sorteios a 50% deram 31 controles
    # (3,8σ). O /dev/urandom não tem esse vício; o $RANDOM fica de reserva.
    sorteio=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -dc '0-9')
    case "$sorteio" in ''|*[!0-9]*) sorteio=$RANDOM ;; esac
    if [ $((sorteio % 100)) -lt "$holdout_pct" ]; then
      holdout_registra controle "$cmd"
      exit 0
    fi
    holdout_registra tratado "$cmd"
  fi
fi

printf '%s' "$payload" | rtk hook claude
