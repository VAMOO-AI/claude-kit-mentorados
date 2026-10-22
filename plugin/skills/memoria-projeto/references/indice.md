# Índice em dois níveis (quando o `MEMORY.md` passa de 8 KB)

O `MEMORY.md` entra no contexto de **toda** request. Sem teto ele cresce com o projeto
(57 KB num CRM com 303 memórias) e cada linha custa em cada prompt. O script redistribui
o índice: `MEMORY.md` fica até 8 KB, por prioridade de tipo (feedback > user > reference >
project), e a cauda vai para `MEMORY-completo.md`, no mesmo formato. Idempotente; sem
`--apply` é dry-run.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-indice.sh" .context/memoria
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-indice.sh" .context/memoria --apply
```

- Memória nova entra **sempre** no `MEMORY.md`; o script redistribui na rodada seguinte.
- Antes de concluir que uma memória não existe, `grep` no `MEMORY-completo.md`: só o curto
  veio no contexto.
- Linha do índice que não aponta para arquivo (cabeçalho de seção, prosa) sai com aviso:
  converta em arquivo de memória antes de aplicar, senão perde o conteúdo.
