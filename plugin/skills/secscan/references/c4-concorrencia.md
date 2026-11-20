<!-- secscan: lido na Fase 2.5, ao avaliar C4 (corrida e idempotência) -->

## C4 — Concorrência: o valor certo, gravado duas vezes

> Ponto de partida: skill `offensive-race-condition` de `SnailSploit/Claude-Red` (MIT), seções
> de isolamento de banco e de serverless. Comandos e critérios reescritos para Supabase, Next e
> n8n.

A Fase 2.5 cobra que o servidor recalcule dinheiro, permissão e identidade. Esta página cobra o
passo seguinte: o servidor calcula certo, mas duas requisições simultâneas leem o mesmo estado e
as duas passam. Cupom de uso único usado cinco vezes, crédito debitado uma vez e gasto duas,
vaga ocupada por dois, convite aceito em duplicado, webhook de pagamento processado duas vezes.
Schema nenhum pega isso: cada requisição, sozinha, é válida.

### Ler, decidir e gravar em passos separados

```bash
# Recurso contável: saldo, crédito, estoque, vaga, uso, cota, cupom, convite
grep -rniE '(saldo|balance|cr[eé]dito|credit|estoque|stock|quota|cota|vagas?|seats?|uses?_count|usos|redeem|resgat|cupom|coupon|convite|invite)' \
  supabase/migrations supabase/functions src app --include='*.sql' --include='*.ts' --include='*.tsx' 2>/dev/null | head -60
# O que o banco já serializa
grep -rniE 'for update|on conflict|unique *\(|create unique index|check *\(' supabase/migrations/*.sql 2>/dev/null
```

Grep localiza; leitura decide. O achado existe quando o mesmo fluxo faz **select, compara no
código e depois update ou insert** em chamadas separadas ao banco (supabase-js, `fetch` para o
PostgREST, nó Postgres do n8n), sobre um recurso que não pode passar do limite. Duas chamadas no
mesmo segundo entram juntas na janela entre a leitura e a escrita.

Não é achado quando decidir e gravar é **uma operação só**, que o banco serializa:

- `update … set saldo = saldo - $1 where id = $2 and saldo >= $1 returning …`, e o código confere
  se voltou linha (zero linhas é a recusa);
- constraint `unique` (ou índice único parcial) que torna a segunda gravação impossível:
  `unique (cupom_id, user_id)`, `unique (evento_id, assento)`; o erro `23505` é a recusa;
- função no banco que faz `select … for update` antes de decidir, ou `check (saldo >= 0)` na
  tabela segurando o pior caso;
- `insert … on conflict do nothing` com a chave natural do evento.

Função `security definer` que confere e grava sem `for update` tem a mesma janela: o
`READ COMMITTED` padrão do Postgres não a fecha.

### Webhook e automação: o mesmo evento chega duas vezes

Provedor de pagamento, WhatsApp e o próprio n8n reentregam evento (timeout, retry, dois
workers). Handler que cobra, credita, manda mensagem ou cria registro a cada entrega precisa de
**idempotência pela chave do provedor**: o id do evento ou da mensagem gravado numa coluna
`unique` antes do efeito, ou numa tabela de eventos processados.

```bash
grep -rniE 'webhook|event\.id|event_id|message_?id|idempot' src app supabase/functions 2>/dev/null | head -40
```

Dedup por `select` antes do `insert` repete a janela de cima: a chave tem que ser `unique` no
banco. Fluxo do n8n: o nó que grava usa `on conflict`, ou o fluxo consulta num nó e grava em
outro? O segundo é o achado.

### Severidade e prova

`HIGH` quando o recurso é dinheiro, crédito, cupom ou vaga paga; `MEDIUM` em contador sem valor
monetário (limite de convites, cota grátis). O finding cita o recurso, a leitura e a escrita
(`arquivo:linha` das duas) e o que falta (constraint, condição no `where`, `for update`). Leitura
de código prova que a janela **existe**; que ela é explorável, só duas requisições simultâneas
no ambiente de teste provam, e isso fica fora deste scan. O finding sai `heuristic`, com o plano
de validação em uma linha.
