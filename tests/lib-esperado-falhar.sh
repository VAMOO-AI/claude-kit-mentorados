# Fila de pendentes do núcleo (F1 do plano do núcleo único, #241). Não roda sozinho: as
# suítes de guard fazem `. tests/lib-esperado-falhar.sh` e chamam `ef_check` no lugar do
# printf de ok/FALHA.
#
# Caso portado do kit do time que o hook daqui ainda reprova entra em
# tests/esperado-falhar.txt em vez de ser apagado: fica visível, com contagem, até o hook
# ser corrigido. Formato, uma linha por caso, separado por TAB:
#   <suíte>[ --codex]<TAB><descrição exata do check>
# Caso listado que falha sai como PENDENTE e não reprova. Caso listado que passou reprova
# como ÓRFÃ: o hook foi corrigido e a linha tem de sair, senão a fila mente.
# O formato e a contagem são conferidos por tests/test-esperado-falhar.sh.
EF_ARQ="${ESPERADO_FALHAR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/esperado-falhar.txt}"
# CODEX vem da suíte, definido antes do `.`: o modo --codex tem fila própria.
EF_SUITE="$(basename "$0")"; [ "${CODEX:-0}" = 1 ] && EF_SUITE="$EF_SUITE --codex"
pendentes=0

ef_listado() { # <descrição>
  [ -f "$EF_ARQ" ] || return 1
  grep -qxF -- "$EF_SUITE	$1" "$EF_ARQ"
}

ef_check() { # ef_check <esperado> <veio> <descrição>
  if [ "$1" = "$2" ]; then
    if ef_listado "$3"; then
      printf '  ÓRFÃ  %s (passou: tire a linha de tests/esperado-falhar.txt)\n' "$3"; falhas=$((falhas+1))
    else printf '  ok    %s\n' "$3"; fi
  elif ef_listado "$3"; then
    printf '  PEND. %s (esperado %s, veio %s; em tests/esperado-falhar.txt)\n' "$3" "$1" "$2"; pendentes=$((pendentes+1))
  else
    printf '  FALHA %s (esperado %s, veio %s)\n' "$3" "$1" "$2"; falhas=$((falhas+1))
  fi
}

ef_resumo() {
  [ "$pendentes" -gt 0 ] && printf 'pendentes (tests/esperado-falhar.txt): %s\n' "$pendentes"
  return 0
}
