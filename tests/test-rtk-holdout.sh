#!/usr/bin/env bash
# Prova de regressão do grupo de controle do RTK: o sorteio no plugin/hooks/rtk-claude.sh
# e a conta do plugin/scripts/rtk-holdout.sh (porte do kit do time, F4 do #241).
#
# O que precisa continuar verdade:
#   - desligado por padrão. Sem RTK_HOLDOUT_PCT o hook se comporta byte a byte como
#     antes e não cria ledger nenhum — o caminho quente é o de todo dia;
#   - só comando ELEGÍVEL entra no ledger. Pipe, git em worktree e comando que o rtk
#     não reescreveria ficam de fora dos DOIS braços: contá-los diluiria a economia
#     medida para perto de zero com comandos que o rtk nunca tocou;
#   - o ledger guarda hash, nunca o comando. `export TOKEN=...` também passa por aqui;
#   - o sorteio é sorteio: com 50% os dois braços aparecem, sem viés grosseiro;
#   - a estimativa estratificada por família não é a média simples. É a diferença
#     entre medir e achar que mediu: amostra desbalanceada move a média simples.
#
# Uso: bash tests/test-rtk-holdout.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOK="$RAIZ/plugin/hooks/rtk-claude.sh"
REPORT="$RAIZ/plugin/scripts/rtk-holdout.sh"
[ -f "$HOOK" ]   || { echo "hook não encontrado: $HOOK"; exit 2; }
[ -f "$REPORT" ] || { echo "script não encontrado: $REPORT"; exit 2; }
command -v jq   >/dev/null || { echo "jq não está no PATH"; exit 2; }
command -v node >/dev/null || { echo "node não está no PATH"; exit 2; }
# Mesmo par de fallback do hook: o macOS tem shasum, o Ubuntu do CI tem os dois.
if   command -v shasum    >/dev/null 2>&1; then SOMA=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then SOMA=(sha256sum)
else echo "sem shasum nem sha256sum no PATH"; exit 2; fi
h() { printf '%s' "$1" | "${SOMA[@]}" | cut -c1-16; }

falhas=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$3', veio '$2')"; fi; }

# `rtk` de mentira: `hook check` só reescreve o que estiver na lista de elegíveis
# (como o rtk de verdade, que manda "No rewrite for: ..." pro stderr e nada pro
# stdout); `hook claude` reescreve tudo, então quem sair sem updatedInput saiu pelo
# sorteio ou por uma guarda.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/rtk" <<'MOCK'
#!/bin/bash
if [ "$1" = "hook" ] && [ "$2" = "check" ]; then
  case "$3" in
    git\ *|grep\ *|ls\ *|cat\ *) echo "rtk $3" ;;
    *) echo "No rewrite for: $3" >&2 ;;
  esac
  exit 0
fi
if [ "$1" = "hook" ] && [ "$2" = "claude" ]; then
  cat >/dev/null
  echo '{"hookSpecificOutput":{"updatedInput":{"command":"rtk <reescrito>"}}}'
  exit 0
fi
exit 0
MOCK
chmod +x "$TMP/bin/rtk"

CWD_NEUTRO=/Users/alguem/WORKSPACES/PROJETO
CWD_WORKTREE=/Users/alguem/WORKSPACES/PROJETO/.claude/worktrees/feat-x

roda() { # <dir-do-ledger> <cwd> <comando> → "rw" ou "quiet"
  local out
  out=$(jq -nc --arg c "$3" --arg d "$2" '{cwd:$d,session_id:"SESSAO1",tool_input:{command:$c}}' \
        | RTK_HOLDOUT_DIR="$1" PATH="$TMP/bin:$PATH" bash "$HOOK" 2>/dev/null)
  case "$out" in *updatedInput*) echo rw ;; *) echo quiet ;; esac
}

echo "== desligado por padrão =="
D="$TMP/off"; unset RTK_HOLDOUT_PCT
check "comando elegível segue reescrito"      "$(roda "$D" "$CWD_NEUTRO" 'git status')" rw
check "sem RTK_HOLDOUT_PCT não nasce ledger"  "$([ -e "$D/ledger.tsv" ] && echo existe || echo nao)" nao
D="$TMP/zero"
check "PCT=0 explícito também não sorteia"    "$(RTK_HOLDOUT_PCT=0 roda "$D" "$CWD_NEUTRO" 'git status')" rw
check "PCT=0 não nasce ledger"                "$([ -e "$D/ledger.tsv" ] && echo existe || echo nao)" nao
D="$TMP/lixo"
check "PCT não numérico vale 0"               "$(RTK_HOLDOUT_PCT=abc roda "$D" "$CWD_NEUTRO" 'git status')" rw
check "PCT não numérico não nasce ledger"     "$([ -e "$D/ledger.tsv" ] && echo existe || echo nao)" nao

echo
echo "== com 100% tudo elegível vira controle, e sai SEM reescrita =="
D="$TMP/cem"
check "comando elegível não é reescrito"      "$(RTK_HOLDOUT_PCT=100 roda "$D" "$CWD_NEUTRO" 'git status')" quiet
check "ledger ganhou uma linha"               "$(wc -l < "$D/ledger.tsv" | tr -d ' ')" 1
check "braço registrado é controle"           "$(cut -f2 "$D/ledger.tsv")" controle
check "família registrada é o binário"        "$(cut -f3 "$D/ledger.tsv")" git
check "sessão registrada vem do payload"      "$(cut -f5 "$D/ledger.tsv")" SESSAO1
check "hash tem 16 hex"                       "$(cut -f4 "$D/ledger.tsv" | grep -cE '^[0-9a-f]{16}$')" 1
check "hash é o sha256 do comando"            "$(cut -f4 "$D/ledger.tsv")" "$(h 'git status')"

echo
echo "== o ledger não guarda o comando (nem o segredo dentro dele) =="
D="$TMP/segredo"
RTK_HOLDOUT_PCT=100 roda "$D" "$CWD_NEUTRO" 'cat /tmp/SUPERSECRETO-ABC123' >/dev/null
check "linha registrada"                      "$(wc -l < "$D/ledger.tsv" | tr -d ' ')" 1
check "o texto do comando não está no ledger" "$(grep -c 'SUPERSECRETO' "$D/ledger.tsv")" 0

echo
echo "== inelegível fica fora dos dois braços (senão a economia medida dilui) =="
D="$TMP/inelegivel"
check "comando que o rtk não reescreveria segue delegado" \
      "$(RTK_HOLDOUT_PCT=100 roda "$D" "$CWD_NEUTRO" 'mkdir -p /tmp/x')" rw
check "e não entra no ledger"                 "$([ -e "$D/ledger.tsv" ] && echo existe || echo nao)" nao

echo
echo "== as guardas antigas vencem o sorteio =="
D="$TMP/guardas"
check "pipe continua saindo calado"           "$(RTK_HOLDOUT_PCT=100 roda "$D" "$CWD_NEUTRO" 'ls src | wc -l')" quiet
check "pipe não entra no ledger"              "$([ -e "$D/ledger.tsv" ] && echo existe || echo nao)" nao
D="$TMP/guardas2"
check "git em worktree continua calado"       "$(RTK_HOLDOUT_PCT=100 roda "$D" "$CWD_WORKTREE" 'git add x')" quiet
check "git em worktree não entra no ledger"   "$([ -e "$D/ledger.tsv" ] && echo existe || echo nao)" nao

echo
echo "== 50% sorteia mesmo: 100 chamadas, os dois braços, sem viés grosseiro =="
D="$TMP/sorteio"
i=0; while [ "$i" -lt 100 ]; do RTK_HOLDOUT_PCT=50 roda "$D" "$CWD_NEUTRO" "grep -rn foo /x" >/dev/null; i=$((i+1)); done
n_c=$(grep -c $'\tcontrole\t' "$D/ledger.tsv"); n_t=$(grep -c $'\ttratado\t' "$D/ledger.tsv")
check "as 100 chamadas foram registradas"     "$((n_c + n_t))" 100
if [ "$n_c" -ge 25 ] && [ "$n_c" -le 75 ]; then ok "controle entre 25 e 75 de 100 (veio $n_c)"
else falha "controle fora de [25,75]: $n_c — o sorteio não está sorteando"; fi

echo
echo "== pelo dispatcher de verdade: o braço de controle não fala no stdout =="
# Em produção o hook não roda sozinho: o pre-bash.sh faz `( . rtk-claude.sh )` e LÊ o
# stdout como decisão de permissão, fundindo com o dos outros hooks quando é JSON. Um
# `echo` solto no caminho do holdout viraria saída malformada — e o `ask` do
# check-careful sumiria junto. Rodar o hook direto não prova isso.
D="$TMP/dispatcher"
paylo=$(jq -nc --arg d "$CWD_NEUTRO" '{cwd:$d,session_id:"SESSAO1",tool_input:{command:"ls -la /tmp"}}')
out=$(printf '%s' "$paylo" | RTK_HOLDOUT_DIR="$D" RTK_HOLDOUT_PCT=100 \
        PRE_BASH_HOOKS_DIR="$RAIZ/plugin/hooks" PATH="$TMP/bin:$PATH" \
        bash "$RAIZ/plugin/hooks/pre-bash.sh" 2>/dev/null; echo "rc=$?")
check "controle não escreve nada no stdout"  "${out%rc=*}" ""
check "e a cadeia sai 0"                     "${out##*rc=}" 0
check "mas o sorteio foi registrado"         "$(cut -f2 "$D/ledger.tsv" 2>/dev/null)" controle
D="$TMP/dispatcher2"
out=$(printf '%s' "$paylo" | RTK_HOLDOUT_DIR="$D" PRE_BASH_HOOKS_DIR="$RAIZ/plugin/hooks" \
        PATH="$TMP/bin:$PATH" bash "$RAIZ/plugin/hooks/pre-bash.sh" 2>/dev/null)
case "$out" in *updatedInput*) ok "com o holdout desligado a reescrita sai pelo dispatcher" ;;
  *) falha "dispatcher devia repassar o updatedInput do rtk: $out" ;; esac

echo
echo "== a conta do relatório =="
# Ledger + transcript sintéticos. Amostra DESBALANCEADA de propósito: a média simples
# e a estratificada por família dão números diferentes, e é isso que o teste fixa.
#   grep: 4 controle × 4000 chars, 2 tratado × 1000  → economia 75%
#   git:  1 controle × 2000 chars, 3 tratado × 1000  → economia 50%
#   média simples ......... 1 - 1000/3600 = 72,2%
#   estratificada ......... 22000/32000   = 68,8%
P="$TMP/relatorio"; mkdir -p "$P/projects/proj"
LED="$P/ledger.tsv"; JSONL="$P/projects/proj/SESSAO1.jsonl"
: > "$LED"; : > "$JSONL"
n=0
par() { # <braco> <familia> <comando> <chars>
  n=$((n+1))
  printf '2026-09-06T10:00:00Z\t%s\t%s\t%s\tSESSAO1\n' "$1" "$2" "$(h "$3")" >> "$LED"
  node -e '
    const [cmd, chars, id] = process.argv.slice(1);
    const p = (o) => JSON.stringify(o);
    console.log(p({sessionId:"SESSAO1",message:{content:[{type:"tool_use",id,name:"Bash",input:{command:cmd}}]}}));
    console.log(p({sessionId:"SESSAO1",message:{content:[{type:"tool_result",tool_use_id:id,content:"x".repeat(+chars)}]}}));
  ' "$3" "$4" "t$n" >> "$JSONL"
}
i=1; while [ "$i" -le 4 ]; do par controle grep "grep -rn c$i /x" 4000; i=$((i+1)); done
i=1; while [ "$i" -le 2 ]; do par tratado  grep "grep -rn t$i /x" 1000; i=$((i+1)); done
par controle git "git log -5" 2000
i=1; while [ "$i" -le 3 ]; do par tratado git "git diff t$i" 1000; i=$((i+1)); done
# ambíguo: mesmo comando sorteado nos dois braços na mesma sessão
par controle ls "ls /ambiguo" 500
printf '2026-09-06T10:00:00Z\ttratado\tls\t%s\tSESSAO1\n' "$(h 'ls /ambiguo')" >> "$LED"
# sorteado mas sem par no transcript (o comando não chegou a rodar)
printf '2026-09-06T10:00:00Z\ttratado\tcat\t%s\tSESSAO1\n' "$(h 'cat /nunca-rodou')" >> "$LED"

J=$(bash "$REPORT" --ledger "$LED" --transcripts "$P/projects" --min 1 --formato json 2>/dev/null)
v() { printf '%s' "$J" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);let x=j;for(const k of process.argv[1].split("."))x=x[k];console.log(Number.isInteger(x)?String(x):(typeof x==="number"?x.toFixed(4):x))})' "$1"; }
check "pareados no controle"                  "$(v pareados.controle)" 5
check "pareados no tratado"                   "$(v pareados.tratado)"  5
check "ambíguo sai da conta"                  "$(v ambiguos)"          1
check "sorteio sem par no transcript é contado" "$(v sem_par)"         1
check "média simples do controle"             "$(v chars.controle.media)" "3600"
check "média simples do tratado"              "$(v chars.tratado.media)"  "1000"
check "economia pela média simples"           "$(v economia_medida_naive)" "0.7222"
check "economia estratificada por família"    "$(v economia_medida_estratificada)" "0.6875"

echo
echo "== amostra pequena não vira conclusão =="
saida=$(bash "$REPORT" --ledger "$LED" --transcripts "$P/projects" 2>&1; echo "rc=$?")
case "$saida" in *"AMOSTRA INSUFICIENTE"*rc=1*) ok "n abaixo do mínimo sai 1 dizendo que é insuficiente" ;;
  *) falha "amostra pequena devia sair 1 com AMOSTRA INSUFICIENTE: $(printf '%s' "$saida" | tail -2 | tr '\n' ' ')" ;; esac
saida=$(bash "$REPORT" --ledger "$TMP/nao-existe.tsv" 2>&1; echo "rc=$?")
case "$saida" in *"sem ledger"*rc=2*) ok "sem ledger sai 2 explicando como ligar" ;;
  *) falha "sem ledger devia sair 2: $(printf '%s' "$saida" | tail -1)" ;; esac

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
