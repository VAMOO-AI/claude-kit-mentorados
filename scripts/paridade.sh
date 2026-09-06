#!/usr/bin/env bash
# paridade.sh — o que este kit e o claude-config-team têm em comum ainda cobre o mesmo?
#
# Os dois kits compartilham hooks, scripts, skills e testes, e TODOS divergem no arquivo:
# aqui os hooks leem o payload por node (`hookjson.js`), lá por `jq`; as skills não têm o
# prefixo `vamoo-`; a instalação é plugin de um lado e `update.sh` do outro. Em 04/09/2026
# a divergência era 13/13 hooks, 16/16 skills e 13/13 testes — sem ninguém conseguir dizer
# o que era adaptação deliberada e o que era porte atrasado.
#
# Comparar bytes seria inútil (a divergência é o desenho). O que dá para comparar é
# COBERTURA: a lista de casos de cada suíte. Um caso é a descrição entre aspas de um
# `check`/`ok` — se um lado testa "heredoc não conta" e o outro não, é porte faltando,
# não estilo. `docs/paridade.md` registra a decisão item a item; este script mostra o
# estado de hoje.
#
# Uso:
# A lista de casos "sem par aqui" é ponto de partida, não dívida confirmada: as duas
# suítes descrevem o mesmo caso com palavras diferentes, e parte da cobertura do time é de
# fluxo que este kit não tem (db-query.sh, cofre de tokens). Quem lê decide, e registra a
# decisão em docs/paridade.md — o script não adivinha intenção.
#
# Uso:
#   bash scripts/paridade.sh              # relatório (até 5 casos por suíte)
#   bash scripts/paridade.sh --detalhe    # lista todos os casos
#   bash scripts/paridade.sh --check      # sai 1 se alguma suíte do time não existe aqui
#   TEAM_REPO=<caminho> bash scripts/paridade.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="${TEAM_REPO:-$HOME/WORKSPACES/claude-config-team}"
CHECK=0; DETALHE=0
for a in "$@"; do case "$a" in --check) CHECK=1 ;; --detalhe) DETALHE=1 ;; esac; done

if [ ! -d "$TEAM" ]; then
  echo "kit do time não encontrado em $TEAM — clone-o ou aponte TEAM_REPO." >&2
  exit 2
fi

# casos <arquivo>: uma linha por caso testado (a descrição do check/ok), normalizada —
# sem o prefixo `vamoo-` das skills, que só existe no time.
#
# O extrator precisa estar ANCORADO no início da linha. A versão anterior era
# `grep -oE '(check|ok|...)[^"]*"[^"]+"'`, que casava qualquer linha de shell com a
# substring "ok"/"check" seguida de aspas — e o relatório passou a acusar 47 casos
# "sem par" chamados ` ]; then bash \`, `"$c"` e `" de "`. Relatório que mente assim
# ninguém lê, e ele existe justamente para a divergência entre os kits não voltar a 100%.
#
# Onde fica a descrição depende do helper, e as duas famílias existem nos dois repos:
#   check "descrição" ...            check bloqueia "descrição" "comando"
#   check 'regex-esperado' "descrição" "$OUT"        → a 1ª entre ASPAS DUPLAS
#   espera_rc 0 "$rc" "descrição"    contem "$arq" "agulha" "descrição"  → a ÚLTIMA
# Argumento que é valor (`"$rc"`, `"$(...)"`) ou não tem letra nenhuma não é descrição:
# pula para o próximo candidato em vez de derrubar o caso.
casos() {
  [ -f "$1" ] || return 0
  awk '
    function aceita(s) {
      if (s == "") return 0
      if (s ~ /^\$/) return 0        # "$rc", "$OUT": valor, não descrição
      if (s ~ /\$\(/) return 0       # "$(...)": comando
      if (s !~ /[A-Za-z]/) return 0  # "0", "]; then": fragmento de shell
      return 1
    }
    function descricao(linha, qual,   n, p, i, ultimo) {
      n = split(linha, p, "\"")      # conteúdo entre aspas duplas = campos pares
      ultimo = ""
      for (i = 2; i <= n - 1; i += 2) {
        if (!aceita(p[i])) continue
        if (qual == "primeiro") return p[i]
        ultimo = p[i]
      }
      return (qual == "primeiro") ? "" : ultimo
    }
    # A linha que DEFINE o helper não é caso — e ela cita o próprio nome.
    /^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*\(\)/ { next }
    {
      # Começo de comando: início da linha, ou depois de ";" / "&&" / "||" — há suíte
      # que escreve `linhas 700; check "" "700 linhas: faixa 600" "$(run s1)"`. E só
      # contam os argumentos DEPOIS do helper: senão uma linha como
      # `grep -qF "# gatilho: $g" ... && ok "..."` doaria o texto do grep como caso.
      if (match($0, /(^|;|&&|\|\|)[[:space:]]*(check|ok)[[:space:]]+/)) {
        d = descricao(substr($0, RSTART + RLENGTH), "primeiro")
        if (d != "") print d
        next
      }
      if (match($0, /(^|;|&&|\|\|)[[:space:]]*(espera_rc|contem|nao_contem)[[:space:]]+/)) {
        d = descricao(substr($0, RSTART + RLENGTH), "ultimo")
        if (d != "") print d
        next
      }
    }
  ' "$1" 2>/dev/null \
    | sed -E 's/vamoo-//g; s/plugin\///g; s/[[:space:]]+/ /g' \
    | sort -u
}

# par <teste-daqui> <teste-do-time>
declare_pares() {
  cat <<'PARES'
test-block-cd-leitura-relativa.sh|test-block-cd-leitura-relativa.sh
test-block-delete-branch.sh|test-block-delete-branch.sh
test-block-main-commit.sh|test-block-main-commit.sh
test-block-monitor-ci.sh|test-block-monitor-ci.sh
test-block-parallel-clone-switch.sh|test-block-parallel-clone-switch.sh
test-branch-guard.sh|test-branch-guard.sh
test-check-careful.sh|test-check-careful.sh
test-dotcontext-session.sh|test-dotcontext-session.sh
test-git-sync-cleanup.sh|test-git-sync-cleanup.sh
test-git-sync-conta.sh|test-git-sync-conta.sh
test-memoria-indice.sh|test-memoria-indice.sh
test-memoria-link.sh|test-memoria-link.sh
test-merge-settings.sh|test-merge-settings.sh
test-notify-stop-cache.sh|test-notify-stop-cache.sh
test-path-rules.sh|test-path-rules.sh
test-pre-bash.sh|test-pre-bash.sh
test-pre-prompt.sh|test-pre-prompt.sh
test-session-size-guard.sh|test-session-size-guard.sh
test-skill-descriptions.sh|test-skill-descriptions.sh
test-skill-sem-injecao.sh|test-skill-sem-injecao.sh
test-skills-projeto.sh|test-skills-projeto.sh
test-warn-branch-behind.sh|test-warn-branch-behind.sh
test-worktree-gc.sh|test-worktree-gc.sh
PARES
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ausentes=0; divergentes=0; ilegiveis=0
printf '%-38s %5s %5s  %s\n' "suíte" "aqui" "time" "cobertura"
while IFS='|' read -r meu dele; do
  [ -n "$meu" ] || continue
  a="$RAIZ/tests/$meu"; b="$TEAM/tests/$dele"
  if [ ! -f "$a" ] && [ ! -f "$b" ]; then continue; fi
  if [ ! -f "$a" ]; then printf '%-38s %5s %5s  SÓ NO TIME — suíte inteira sem par\n' "$meu" "-" "$(casos "$b" | wc -l | tr -d ' ')"; ausentes=$((ausentes+1)); continue; fi
  if [ ! -f "$b" ]; then printf '%-38s %5s %5s  só aqui\n' "$meu" "$(casos "$a" | wc -l | tr -d ' ')" "-"; continue; fi
  casos "$a" > "$TMP/a"; casos "$b" > "$TMP/b"
  na=$(wc -l < "$TMP/a" | tr -d ' '); nb=$(wc -l < "$TMP/b" | tr -d ' ')
  # Suíte que não usa check/ok (só printf, como a de descriptions) não tem caso para
  # extrair. Isso é diferente de suíte em dia, e no formato antigo saía como "0 0 ok" —
  # indistinguível de uma que regrediu a zero caso.
  if [ "$na" -eq 0 ] && [ "$nb" -eq 0 ]; then
    printf '%-38s %5s %5s  sem casos legíveis (não usa check/ok — nada a comparar)\n' "$meu" 0 0
    ilegiveis=$((ilegiveis+1)); continue
  fi
  faltando=$(comm -13 "$TMP/a" "$TMP/b" | wc -l | tr -d ' ')
  if [ "$faltando" -eq 0 ]; then printf '%-38s %5s %5s  ok\n' "$meu" "$na" "$nb"
  else
    printf '%-38s %5s %5s  %s caso(s) do time sem par textual\n' "$meu" "$na" "$nb" "$faltando"
    if [ "$DETALHE" -eq 1 ]; then comm -13 "$TMP/a" "$TMP/b" | sed 's/^/      · /'
    else comm -13 "$TMP/a" "$TMP/b" | head -5 | sed 's/^/      · /'
         [ "$faltando" -gt 5 ] && printf '      … e mais %s (--detalhe)\n' "$((faltando - 5))"; fi
    divergentes=$((divergentes+1))
  fi
done < <(declare_pares)

echo
[ "$ilegiveis" -gt 0 ] && echo "$ilegiveis suíte(s) sem caso legível — a comparação de cobertura não alcança essas."
if [ "$ausentes" -eq 0 ] && [ "$divergentes" -eq 0 ]; then
  echo "cobertura em dia com o kit do time."
else
  [ "$ausentes"    -gt 0 ] && echo "$ausentes suíte(s) do time não existem aqui — porte, ou registre em docs/paridade.md por que não se aplica."
  [ "$divergentes" -gt 0 ] && echo "$divergentes suíte(s) com caso do time sem par TEXTUAL — leia antes de portar: a mesma prova pode estar escrita com outras palavras, e parte é fluxo que este kit não tem."
  echo "A decisão item a item mora em docs/paridade.md."
  { [ "$CHECK" -eq 1 ] && [ "$ausentes" -gt 0 ]; } && exit 1
fi
exit 0
