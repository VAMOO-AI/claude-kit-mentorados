# 05 · Carga, cache, gargalo e (quando) balanceamento

Aplicativo lento raramente é lento por falta de servidor. É lento porque traz dado
demais, traz do jeito errado, ou traz de novo o que já tinha. Balanceamento é a
última resposta da lista — e este arquivo existe em boa parte para dizer isso.

## Contrato

- [ ] **Nenhuma query de lista sem `limit`/`range`.** O PostgREST corta em 1000 e
      não avisa: você recebe 1000 linhas e um `200`.
- [ ] **Agregação acontece no banco.** Se a tela mostra um total, o total vem
      pronto — não se traz 50 mil linhas para somar no browser.
- [ ] **Todo filtro frequente tem índice**, e nenhum índice existe sem uso.
- [ ] **Cache declarado por camada**, com invalidação escrita. Cache sem regra de
      invalidação é bug agendado.
- [ ] Resposta de API pública tem `Cache-Control` explícito — inclusive
      `no-store` onde for o caso.
- [ ] Orçamento de bundle vigiado no CI (ver pilar 01).
- [ ] **Gargalo é medido antes de ser otimizado.** Número, não impressão.

## Como implementar

**Paginação que não perde linha.** O erro clássico é paginar por `range` sem
ordenação estável: duas linhas com o mesmo `created_at` trocam de lugar entre
páginas e uma some.

```ts
const PAGE = 1000
export async function fetchAll<T>(table: string, select: string): Promise<T[]> {
  const out: T[] = []
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await supabase
      .from(table).select(select)
      .order('created_at', { ascending: true })
      .order('id',         { ascending: true })   // tiebreaker: sem ele, some linha
      .range(from, from + PAGE - 1)
    if (error) throw error
    out.push(...(data as T[]))
    if (!data || data.length < PAGE) return out
  }
}
```

**Mas antes de paginar, pergunte se precisa dos dados.** 58 round-trips para
montar 57 mil linhas na memória do browser é o gargalo, não a solução dele. A
correção real é mover o cálculo:

```sql
-- em vez de trazer erp_faturamento inteiro e somar no cliente
create materialized view public.mv_faturamento_mensal as
select date_trunc('month', emissao) as mes, vendedor_id,
       sum(valor) as total, count(*) as notas
from public.erp_faturamento group by 1, 2;

create unique index on public.mv_faturamento_mensal (mes, vendedor_id);
-- refresh concurrently exige o unique index acima
```

Regra prática: **acima de ~10 mil linhas, agregue no banco.** Abaixo disso,
paginar e calcular no cliente é aceitável e mais simples.

**Cache em três camadas** — declare qual você usa e como invalida:

| Camada | Serve para | Invalidação |
|---|---|---|
| Cliente (memória/IndexedDB) | evitar refetch na navegação | por evento de escrita + TTL |
| HTTP (`Cache-Control`/CDN) | asset e resposta pública | hash no nome do arquivo |
| Banco (matview/coluna calculada) | agregação cara | `refresh` agendado ou por trigger |

```
Cache-Control: public, max-age=31536000, immutable    # asset com hash
Cache-Control: no-store                                # qualquer coisa por usuário
Cache-Control: public, s-maxage=60, stale-while-revalidate=300   # lista pública
```

`no-store` para resposta autenticada não é paranoia: sem ele, um proxy
intermediário pode servir o dado de um usuário para outro.

**Índice — os três que resolvem quase tudo:**

```sql
create index on public.pedidos (vendedor_id, created_at desc);  -- filtro + ordenação
create index on public.pedidos (status) where status = 'aberto'; -- parcial: só o que se busca
create index on public.pedidos using gin (to_tsvector('portuguese', descricao));
```

Índice de FK é o lint `0001` e costuma ser o ganho mais barato do banco inteiro.
Índice nunca usado (`0005`) custa em toda escrita — remova.

## Como provar

```bash
# query de lista sem teto
grep -rn "\.from('.*')\.select(" src/ | grep -v -E '\.range\(|\.limit\(|\.single\(|\.maybeSingle\(' | head -20

# quantos índices existem
grep -rc 'create index' supabase/migrations/*.sql | awk -F: '{s+=$2} END {print s" índices"}'
```

No banco, o que de fato mede:

```sql
-- as 10 queries mais caras (exige pg_stat_statements)
select round(total_exec_time)::int as ms_total, calls,
       round(mean_exec_time)::int as ms_media, left(query, 90) as query
from pg_stat_statements order by total_exec_time desc limit 10;

-- tabela grande sem índice além da PK
select relname, n_live_tup, seq_scan, idx_scan
from pg_stat_user_tables
where n_live_tup > 10000 and (idx_scan = 0 or idx_scan is null)
order by n_live_tup desc;

-- o plano real da query suspeita
explain (analyze, buffers) select ...;
```

`seq_scan` alto com `idx_scan` zero em tabela grande é o achado mais acionável do
pilar. E os lints `0001` (FK sem índice) e `0005` (índice não usado) fazem essa
varredura sozinhos — ver pilar 02.

No front, a medição que importa é o perfil de gravação: abrir o DevTools em
Performance, gravar a interação lenta e olhar onde a main thread trava. Impressão
de lentidão sem gravação não entra no report.

## Balanceamento — quase sempre a resposta errada

Na stack Vercel + Supabase **você já tem balanceamento**: as funções são
distribuídas, o CDN é global, o Postgres fica atrás de um pooler. Colocar um load
balancer na frente disso resolve aproximadamente nada.

Antes de pensar em escalar horizontalmente, esgote nesta ordem — do mais barato
para o mais caro:

1. **Índice faltando.** Minutos de trabalho, ordens de grandeza de ganho.
2. **Agregação no banco** em vez de no cliente.
3. **Cache na camada certa** (a maioria dos "picos" é a mesma query repetida).
4. **Pooler configurado certo.** Serverless abre conexão por invocação: use a
   porta do pooler em modo transaction, não a conexão direta. Esgotamento de
   conexão se parece com lentidão e não é.
5. **Read replica**, quando leitura pesada de BI concorre com escrita
   transacional. Aqui sim há separação de carga real.
6. **Fila** (pgmq, n8n, worker) para trabalho que não precisa ser síncrono. Cargas
   de importação e disparo pertencem a este item, não à requisição do usuário.
7. **Só então** múltiplas instâncias com balanceador — e isso normalmente
   significa que você saiu do serverless, o que é uma decisão de arquitetura, não
   de performance.

Se um item de 1 a 6 não foi medido, a resposta para "precisamos balancear?" é
**não sabemos ainda**.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| Lista mostra exatamente 1000 registros | Teto silencioso do PostgREST. Não é coincidência, é o default |
| Uma linha some entre páginas | `range` sem tiebreaker no `order`. Empate no timestamp reordena |
| App congela ao abrir, depois funciona | Cold load de dezenas de milhares de linhas travando a main thread |
| Dashboard rápido em dev, lento em prod | Dev tem 200 linhas de seed. Meça com volume real ou não meça |
| Número plausível e errado no gráfico | Range fechando no fim do mês em vez do fim do bucket. Bug plausível é invisível |
| "Está lento" some depois do deploy e volta | Cache do cliente frio. O problema não sumiu, foi mascarado |
| Escala vertical resolveu por uma semana | Comprou tempo, não corrigiu a query. Volta com mais dado |
| Refresh de matview trava a leitura | Faltou `concurrently` — que exige índice unique |
