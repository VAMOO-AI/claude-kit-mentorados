#!/usr/bin/env bash
# pre-bash.sh — dispatcher do PreToolUse(Bash|PowerShell): lê o payload UMA vez e o entrega, em ordem,
# aos cinco hooks de Bash que até a 0.25.0 eram cinco entries no hooks.json.
#
# Por que existe: cada entry custa um processo de shell mais um `bash <hook>` antes de o
# hook olhar o payload — e cada hook do plugin ainda abre um `node` para ler o JSON. Cinco
# por chamada de Bash, em toda chamada. Aqui o harness faz um spawn só, cada hook roda em
# subshell (`source`, sem um novo bash), e hook cuja palavra-gatilho não aparece no payload
# nem é aberto — o node dele também não roda.
#
# Gatilho: o hook declara no cabeçalho `# gatilho: palavra outra` — as substrings sem as
# quais ele nunca bloquearia (o block-main-commit só age se houver `commit` no comando).
# Se nenhuma está no payload, o hook é pulado; sem a linha, roda sempre. É condição
# NECESSÁRIA, nunca suficiente: falso positivo só custa rodar o hook, que decide sozinho.
#
# Semântica da cadeia antiga, preservada:
#   - o primeiro hook que sai 2 encerra a cadeia com exit 2, o stdout e o stderr dele
#     (bloqueio; o stderr vira a mensagem para o agente);
#   - hook que sai com outro código ≠ 0 tem bug, e o bug não desliga os guards seguintes:
#     com entries separados o harness rodava todos, e exit 1 não bloqueia ("non-blocking
#     error" na doc de hooks). O stdout dele vai para o stderr, a linha
#     "[pre-bash] <hook> saiu <rc> (bug do hook; cadeia segue)" sai no stderr e no
#     systemMessage, e a cadeia continua. Até a 0.53 qualquer rc ≠ 0 encerrava, e o
#     comando rodava sem os guards de depois;
#   - hook que sai 0 e emite algo no stdout tem o stdout repassado e a cadeia continua
#     (é o `ask` do check-careful, o único que fala aqui);
#   - hook que não está instalado é pulado.
#
# Os hooks moram na mesma pasta que este arquivo; PRE_BASH_HOOKS_DIR aponta para outra —
# é o que a suíte usa. Fail-open: sem payload sai 0. Sem `set -o pipefail` de propósito:
# hook que sai antes de ler o stdin mata o printf com SIGPIPE, e o 141 dele não pode virar
# o código da cadeia.
case "$0" in */*) HOOKS_DIR="${0%/*}" ;; *) HOOKS_DIR="." ;; esac
HOOKS_DIR="${PRE_BASH_HOOKS_DIR:-$HOOKS_DIR}"
payload=$(cat)
[ -z "$payload" ] && exit 0

# 0 quando o hook deve rodar: sem linha `# gatilho:` nas 40 primeiras linhas, ou com alguma
# das palavras presente no payload. Só builtins — nenhum processo.
tem_gatilho() {
  local linha p n=0
  while IFS= read -r linha && [ "$n" -lt 40 ]; do
    n=$((n+1))
    # Checkout no Windows com core.autocrlf=true deixa \r no fim da linha: "commit\r"
    # nunca casaria e o hook seria pulado calado (o .gitattributes já força LF; isto
    # cobre quem clonou antes dele ou editou o hook no Windows).
    linha="${linha%$'\r'}"
    case "$linha" in
      '# gatilho:'*)
        for p in ${linha#\# gatilho:}; do
          case "$payload" in *"$p"*) return 0 ;; esac
        done
        return 1 ;;
    esac
  done < "$1"
  return 0
}

# PowerShell (0.48.0): o hooks.json casa `Bash|PowerShell`, porque regra e hook de Bash não
# veem o comando que o Claude roda pelo PowerShell (code.claude.com/docs/en/tools-reference#powershell-tool).
# git e gh se escrevem igual nas duas shells, então commit em main, push --force, checkout no
# clone compartilhado e merge com branch-filha valem lá também. O block-cd-leitura-relativa
# fica de fora: ele modela `cd` + leitura relativa do bash, e PowerShell lê com Get-Content.
powershell=0
[[ $payload =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"PowerShell\" ]] && powershell=1

# Leitura única (invariante 4 do núcleo único, #241): os campos que os guards usam saem de um
# node só, na primeira vez que um gatilho casa, e ficam em variáveis do dispatcher. O guard,
# que roda em subshell, pede os dele ao kit_campos no formato do hookjson.js (um por linha,
# o último cru). Fora do dispatcher (Codex, suíte, hook chamado à mão) o guard lê sozinho.
# Sem node ou sem o hookjson.js nada é lido aqui, e cada guard faz o fail-open dele.
KIT_CAMPOS_LIDOS=""
kit_ler() {
  [ -n "$KIT_CAMPOS_LIDOS" ] && return 0
  KIT_CAMPOS_LIDOS=0
  local hj r
  hj="$(cd "$HOOKS_DIR/../scripts" 2>/dev/null && pwd)/hookjson.js"
  [ -f "$hj" ] || hj="$HOME/.claude/scripts/hookjson.js"
  command -v node >/dev/null 2>&1 && [ -f "$hj" ] || return 0
  r="$(printf '%s' "$payload" | node "$hj" permission_mode cwd session_id tool_input.workdir tool_input.command)"
  KC_MODO="${r%%$'\n'*}"; r="${r#*$'\n'}"
  KC_CWD="${r%%$'\n'*}";  r="${r#*$'\n'}"
  KC_SID="${r%%$'\n'*}";  r="${r#*$'\n'}"
  KC_WD="${r%%$'\n'*}";   KC_CMD="${r#*$'\n'}"
  KIT_CAMPOS_LIDOS=1
}
kit_campos() { # <campo>... → o que `node hookjson.js <campo>...` imprimiria
  local v n=$#
  while [ $# -gt 0 ]; do
    case "$1" in
      permission_mode)    v="$KC_MODO" ;;
      cwd)                v="$KC_CWD" ;;
      session_id)         v="$KC_SID" ;;
      tool_input.workdir) v="$KC_WD" ;;
      tool_input.command) v="$KC_CMD" ;;
      *)                  v="" ;;
    esac
    shift
    if [ $# -gt 0 ]; then v="${v//$'\r\n'/ }"; printf '%s\n' "${v//$'\n'/ }"; else printf '%s' "$v"; fi
  done
  [ "$n" -gt 0 ]
}

saidas=""
avisos=""
# O rtk-claude é o último, sempre (invariante 1 do núcleo único): reescreve o comando para o
# rtk, e só depois de todos os guards decidirem sobre o original. Inerte sem rtk no PATH. Não
# roda no PowerShell, nem quando um guard já falou: com o `ask` na mesa, a pessoa aprova o
# comando que ela vê, e o dispatcher não precisa fundir dois JSONs.
for h in block-main-commit.sh check-careful.sh block-cd-leitura-relativa.sh \
         block-parallel-clone-switch.sh block-delete-branch-with-children.sh rtk-claude.sh; do
  f="$HOOKS_DIR/$h"
  [ -f "$f" ] || continue
  [ "$powershell" = 1 ] && [ "$h" = block-cd-leitura-relativa.sh ] && continue
  if [ "$h" = rtk-claude.sh ]; then
    [ "$powershell" = 1 ] || [ -n "$saidas" ] && continue
    command -v rtk >/dev/null 2>&1 || continue
  fi
  tem_gatilho "$f" || continue
  kit_ler
  out=$(printf '%s' "$payload" | ( . "$f" ))
  rc=$?
  if [ "$rc" -eq 2 ]; then
    [ -n "$saidas" ] && printf '%s\n' "$saidas"
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 2
  fi
  if [ "$rc" -ne 0 ]; then
    [ -n "$out" ] && printf '%s\n' "$out" >&2
    aviso="[pre-bash] $h saiu $rc (bug do hook; cadeia segue)"
    printf '%s\n' "$aviso" >&2
    avisos="${avisos:+$avisos\\n}$aviso"
    continue
  fi
  [ -n "$out" ] && saidas="${saidas:+$saidas
}$out"
done
# O aviso de bug vai para a pessoa no systemMessage. Sem node para montar JSON: o texto
# do aviso é só nome de hook, número e pontuação fixa, então dá para escrever à mão. Se o
# check-careful falou (um objeto JSON), o systemMessage entra no MESMO objeto — dois
# objetos no stdout o Claude Code não lê.
if [ -n "${avisos:-}" ]; then
  case "$saidas" in
    "") saidas="{\"systemMessage\":\"$avisos\"}" ;;
    "{"*) saidas="{\"systemMessage\":\"$avisos\",${saidas#\{}" ;;
  esac
fi
[ -n "$saidas" ] && printf '%s\n' "$saidas"
exit 0
