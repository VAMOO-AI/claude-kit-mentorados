<!-- secscan: lido nas Fases 1 e 2 -->

## Fase 1 — Secrets

```bash
git check-ignore .env .env.local 2>/dev/null   # devem aparecer = estão ignorados
grep -rnE "(NEXT_PUBLIC|VITE)_[A-Z_]*(KEY|SECRET|TOKEN|SERVICE)" --include="*.ts" --include="*.tsx" --include="*.js" . | head
```
Sinalize: `.env`/`.env.local` versionados no git; qualquer coisa sensível atrás de `NEXT_PUBLIC_` ou `VITE_` (os dois vão pro navegador!); `.env.example` faltando.

**Triagem obrigatória antes de reportar número do gitleaks.** Os dois modos da Fase 0.5
somam: o `detect` lê só o histórico commitado e o `dir` lê a árvore de trabalho, inclusive o
que o git ignora. A contagem crua é quase toda ruído: numa auditoria real, "67 leaks" viraram
**zero** achado. Separe em três baldes e reporte só o terceiro como finding, com a contagem
de cada um à vista:

1. **Arquivo não rastreado** (`git check-ignore` / `git ls-files --error-unmatch`): cache de
   ferramenta, `dist/` e o próprio `.env.local`, que é ignorado de propósito. Não vazou para
   lugar nenhum: é higiene local, não incidente.
2. **Rastreado mas público por desenho**: decodifique antes de gritar. JWT com `role=anon`
   do Supabase é chave pública, vai no navegador por contrato:
   `printf %s "<jwt>" | cut -d. -f2 | base64 -d 2>/dev/null` resolve em um comando.
3. **Rastreado e secreto**: `role=service_role`, `sbp_`, `sk-ant-`, senha de Postgres.
   **Este é o finding**, e é CRITICAL. Zero aqui com 60 no balde 1 é um repo saudável.

Achado só do `dir` em arquivo rastreado é segredo prestes a ser commitado (balde 3); em
arquivo ignorado, balde 1.

## Fase 2 — Supabase (o coração)

Olhe o estado real, não chute. Com acesso ao banco (psql, ou o script de SQL que o projeto
já tem; se existir `.context/docs/deploy.md`, ele diz qual), consulte as policies vivas,
**uma query por chamada**:

```sql
select schemaname, tablename from pg_tables where schemaname='public' and rowsecurity is false;
select tablename, policyname, roles, cmd, qual from pg_policies where schemaname='public' order by tablename;
```

Sem acesso ao banco, leia os SQL/migrations estaticamente:

```bash
grep -rniE "enable row level security|create policy|using *\(true\)|security definer|service_role" \
  supabase/migrations src/sql 2>/dev/null | head
```

A migration diz o que alguém quis; o banco diz o que vale. Os dois divergem com frequência
(um `GRANT` posterior desfaz um `REVOKE` antigo, uma função recriada à mão perde o
`search_path`): quando der para consultar o banco, ele é a autoridade e o grep é só o
localizador.
Caça:
- **RLS desligada** numa tabela, ou tabela pública **sem policy** pra `anon`/`authenticated` → qualquer um com a chave `anon` lê/escreve tudo.
- **Materialized view legível por `anon`/`authenticated`** → vazamento que a RLS não cobre, porque **MV não tem RLS**. É o achado que passa despercebido justamente em projeto com RLS impecável: quem confere RLS e vê tudo verde para de olhar.

  ```sql
  SELECT c.relname,
         has_table_privilege('anon',          c.oid, 'SELECT') AS anon,
         has_table_privilege('authenticated', c.oid, 'SELECT') AS authenticated
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'm';
  ```

  Qualquer `true` é finding, e a própria query prova: o privilégio é o fato. A
  prova pela porta do atacante vai no relatório, para o dono do projeto rodar
  contra o projeto dele — a skill não chama endpoint publicado:
  `curl "$SUPABASE_URL/rest/v1/<mv>?select=*" -H "apikey: <anon>"`. Medido numa
  auditoria real em 01/09/2026: 180 de 180 tabelas com RLS, 170 funções
  `SECURITY DEFINER` sem uma falha — e 904 linhas de 16 clientes saindo por uma
  MV, sem nenhum login. Confira o **estado vivo**, não a migration: naquele repo
  o `REVOKE` certo estava versionado havia meses e um `GRANT ALL` posterior o
  desfez em silêncio. View com `security_invoker` que lê de uma MV entrega o dado do
  mesmo jeito: o invoker respeita a permissão, e a permissão é que está aberta.
- **`service_role` no código client** ou atrás de `NEXT_PUBLIC_`/`VITE_` → bypass total do banco no navegador. **CRÍTICO**.
- **Cliente admin (`service_role`) numa rota pública** (ex.: página sem login como
  `/r/[token]`) fazendo `select *` ou joins com `(*)`: passa por cima da RLS e traz coluna
  sensível de brinde (dado pessoal do dono, campo interno). Sinalize sempre; a
  **severidade depende da exposição**: o dado sensível aparece no JSX ou vai para um Client
  Component → HIGH; é buscado e nunca renderizado → LOW (latente: o próximo render vaza o
  dado, porque ele já está no objeto). O fix é o mesmo: colunas explícitas, nunca `*`.
- Policy com `using (true)` / `with check (true)` → RLS efetivamente desligada. A
  contrapartida (constraint de domínio compensando) é da Fase 2.5.
- Função `security definer` sem `set search_path` fixo → escalada de privilégio. O
  `pg_proc` é a autoridade (`select proname, proconfig from pg_proc where prosecdef`); o grep
  nas migrations só localiza.
- Bucket de Storage público guardando dado de usuário.
