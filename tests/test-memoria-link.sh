#!/usr/bin/env bash
# Prova de regressão do plugin/scripts/memoria-link.sh.
#
# O caminho do projeto vinha só do `cwd` gravado no transcript — e o Claude Code poda os
# `.jsonl` antigos. Projeto sem transcript perdia o caminho e o loop dava `continue` SEM
# UMA LINHA de aviso: no kit do time, 131 fatos em 3 projetos ficaram presos na máquina
# enquanto a varredura dizia que estava tudo em dia. Agora o slug é resolvido contra os
# diretórios reais (resposta única, senão é ambiguidade) e memória sem destino é
# reportada, não esquecida.
#
# Cobre também: contagem que exclui README/MEMORY.md (andaime, não fato), README do
# formato escrito só quando alguém pediu (`--adotar`/`--repo`) e nunca na varredura
# automática, e link quebrado tratado como problema — não como "sem memória local".
#
# Uso: bash tests/test-memoria-link.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/memoria-link.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/memlink.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# /var → /private/var no macOS: o script compara caminhos reais (git rev-parse), então o
# fixture nasce já resolvido, senão o slug do repo não bate com o do diretório de memória.
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home"          # o script deriva tudo do HOME
PROJ="$HOME/.claude/projects"
mkdir -p "$PROJ" "$HOME/WORKSPACES"

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep -qE -- "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
existe() { # <existe|nao> <caminho> <descrição>
  local ok=1
  case "$1" in existe) [ -e "$2" ] || ok=0 ;; nao) [ ! -e "$2" ] || ok=0 ;; esac
  if [ "$ok" = 1 ]; then printf '  ok    %s\n' "$3"
  else printf '  FALHA %s\n' "$3"; falhas=$((falhas+1)); fi
}
slug() { printf '%s' "$1" | LC_ALL=C tr -c 'a-zA-Z0-9' '-' | sed 's/-$//'; }
fato() { printf -- '---\nname: %s\ndescription: x\nmetadata:\n  type: project\n---\n\nfato\n' "$2" > "$1/$2.md"; }
run() { bash "$SCRIPT" "$@" 2>&1; }

# A: sem transcript, slug resolve para um diretório único → tem que aparecer
A="$HOME/WORKSPACES/proj-a"; mkdir -p "$A"; git -C "$A" init -q
mkdir -p "$PROJ/$(slug "$A")/memory"
fato "$PROJ/$(slug "$A")/memory" um; fato "$PROJ/$(slug "$A")/memory" dois
echo idx > "$PROJ/$(slug "$A")/memory/MEMORY.md"; echo r > "$PROJ/$(slug "$A")/memory/README.md"
# B: sem transcript e slug que não corresponde a diretório nenhum → aviso, não silêncio
mkdir -p "$PROJ/-nada-a-ver-xyz/memory"; fato "$PROJ/-nada-a-ver-xyz/memory" preso
# C: já tem .context/memoria (sem README) e memória local para migrar
C="$HOME/WORKSPACES/proj-c"; mkdir -p "$C/.context/memoria"; git -C "$C" init -q
mkdir -p "$PROJ/$(slug "$C")/memory"; fato "$PROJ/$(slug "$C")/memory" c1
# D: com transcript, .context/memoria sem README → varredura liga mas NÃO escreve README
D="$HOME/WORKSPACES/proj-d"; mkdir -p "$D/.context/memoria"; git -C "$D" init -q
mkdir -p "$PROJ/$(slug "$D")"; printf '{"cwd":"%s"}\n' "$D" > "$PROJ/$(slug "$D")/s.jsonl"
# E: 'memory' é symlink para pasta que não existe (worktree/projeto apagado)
E="$HOME/WORKSPACES/proj-e"; mkdir -p "$E"; git -C "$E" init -q
mkdir -p "$PROJ/$(slug "$E")"; ln -s "$TMP/nao-existe/memoria" "$PROJ/$(slug "$E")/memory"

echo "== varredura --adotar --dry-run: ninguém some calado =="
OUT="$(run --adotar --dry-run)"
check 'adotaria .*proj-a \(2 fato\(s\)\)'                 "proj-a sem transcript é achado pelo slug; README/MEMORY não contam" "$OUT"
check '-nada-a-ver-xyz: 1 fato\(s\) presos na máquina' "memória cujo slug não resolve é reportada"                          "$OUT"
check 'memoria-link.sh --repo <caminho-do-repo>'          "…com o comando para ligar à mão"                                    "$OUT"
check 'ligaria .*proj-d'                                  "projeto com transcript segue sendo ligado"                          "$OUT"
check "proj-e: 'memory' aponta para .* link quebrado"     "link quebrado é problema, não 'sem memória local'"                  "$OUT"

echo "== --repo escreve o README do formato onde falta =="
OUT="$(run --repo "$C")"
check 'README.md do formato criado'                       "avisa que escreveu o README"                                        "$OUT"
existe existe "$C/.context/memoria/README.md"             "README.md existe em proj-c"
grep -q '^# Memória do projeto' "$C/.context/memoria/README.md" && printf '  ok    README tem o formato do fato\n' || { printf '  FALHA README sem o cabeçalho esperado\n'; falhas=$((falhas+1)); }
check 'commite: git add .context/memoria'                 "diz como publicar (sem script que o kit não tem)"                   "$OUT"
existe existe "$C/.context/memoria/c1.md"                 "fato da máquina migrou para o repositório"

echo "== varredura automática: liga, conta, mas não escreve README em repo alheio =="
OUT="$(run)"
existe nao "$D/.context/memoria/README.md"                "proj-d NÃO ganhou README na varredura"
check '1 projeto\(s\) com memória e sem README'           "…mas a varredura conta e aponta o --adotar"                         "$OUT"
check 'link quebrado removido'                            "link quebrado de proj-e foi limpo"                                  "$OUT"
[ -L "$PROJ/$(slug "$D")/memory" ] && printf '  ok    proj-d ligado (symlink)\n' || { printf '  FALHA proj-d não foi ligado\n'; falhas=$((falhas+1)); }

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
