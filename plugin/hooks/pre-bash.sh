#!/usr/bin/env bash
# pre-bash.sh — dispatcher do PreToolUse(Bash): lê o payload UMA vez e o entrega, em ordem,
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
#   - o primeiro hook que sai com código ≠ 0 encerra a cadeia com o MESMO código, o stdout
#     e o stderr dele (exit 2 = bloqueio; o stderr vira a mensagem para o agente);
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

saidas=""
for h in block-main-commit.sh check-careful.sh block-cd-leitura-relativa.sh \
         block-parallel-clone-switch.sh block-delete-branch-with-children.sh; do
  f="$HOOKS_DIR/$h"
  [ -f "$f" ] || continue
  tem_gatilho "$f" || continue
  out=$(printf '%s' "$payload" | ( . "$f" ))
  rc=$?
  if [ "$rc" -ne 0 ]; then
    [ -n "$saidas" ] && printf '%s\n' "$saidas"
    [ -n "$out" ] && printf '%s\n' "$out"
    exit "$rc"
  fi
  [ -n "$out" ] && saidas="${saidas:+$saidas
}$out"
done
[ -n "$saidas" ] && printf '%s\n' "$saidas"
exit 0
