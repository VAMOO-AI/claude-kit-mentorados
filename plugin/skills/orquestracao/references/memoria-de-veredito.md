# orquestracao — memória de veredito

Lido antes de silenciar um achado ou reabrir um finding (auditoria, revisor de PR, fan-out que produz achado).

## Memória de veredito (falso-positivo não se resolve no código)

Silenciar o achado onde ele aparece (`nosemgrep`, `eslint-disable`, exceção no scanner)
espalha a decisão pelo código, some no diff e não diz quem decidiu nem quando. O veredito vai
num arquivo, no formato do `secscan`:

```markdown
<!-- .context/docs/security/vereditos.md -->
| Fingerprint | Veredito | Por quê | Quem | Quando |
|---|---|---|---|---|
| `src/import.ts:88 sql-injection` | falso-positivo | parâmetro vem de enum fechado, não de input | dev responsável | 2026-08-22 |
| `scripts/build-*.cjs service_role` | risco aceito | ver EX-01 em `.context/docs/baseline.md` | dev responsável | 2026-08-22 |
```

Antes de reabrir um finding, consulte a tabela; depois de julgar um novo, escreva nela. Vale
para auditoria, revisor de PR e todo fan-out que produz achado: sem isso, cada rodada paga o
mesmo julgamento e chega a conclusões diferentes conforme o agente. Código ao redor mudou →
o fingerprint deixa de valer e o achado volta. Registre o motivo, não só o "não é problema".
