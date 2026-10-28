<!-- secscan: lido na Fase 2.5 (C4), junto de c4-validacao.md -->

## Fase 2.5 — Validação de entrada (C4)

Ausência de schema **é** o achado; não precisa de um sink depois dela. As ferramentas que
olham só o diff costumam recusar esta classe ("missing input validation" sem impacto
provado), por isso ela tem fase própria.

**Passo 0: descubra o validador antes de exigir um.** Não cobre zod de um repo Python:

```bash
grep -hoiE '(zod|valibot|yup|ajv|joi|superstruct|class-validator|pydantic|marshmallow|jsonschema|cerberus|go-playground/validator)' \
  package.json pyproject.toml requirements.txt go.mod composer.json Gemfile 2>/dev/null | sort -u
```

Zero hits **não é o finding**: só muda a comparação para guarda escrita à mão (`typeof`,
`if (!body.x)`, `isinstance`). O finding é o boundary sem nenhum dos dois. Ausência de
validação é `heuristic` por construção (você detecta uma chamada que *não existe*); vira
`CONFIRMED` pelo critério único das regras de ferro, e aqui um teste do projeto que
exercita o boundary conta.

Os boundaries a caçar (server action e form, fila, webhook de automação, valor que decide
dinheiro/permissão/identidade, policy permissiva sem constraint, identidade sem
normalização, limite de entrada, mass assignment, confusão de tipo) estão em
[references/c4-validacao.md](c4-validacao.md), com o veredito de cada um: leia
ao avaliar C4.

Levantamento: estes três imprimem o **gap**, não o inventário.

```bash
# 1. GAP: function que lê entrada crua MENOS a que tem schema. O receptor do body muda de
# nome (`req`, `request`, `_req`): fixar em `req.json()` subconta. E `.json()` solto casa
# `response.json()`, que é leitura de RESPOSTA. Varra a pasta inteira, não só `*/index.ts`.
comm -23 \
  <(grep -rlnE "\b(req|request|_req|rq)\.(json|formData|text|arrayBuffer)\(|new URL\((req|request|_req|rq)\.url\)" supabase/functions --include="*.ts" 2>/dev/null | grep -v '/_shared/' | sort) \
  <(grep -rlnE "zod|valibot|safeParse|z\.object" supabase/functions --include="*.ts" 2>/dev/null | grep -v '/_shared/' | sort)

# 2. teto de tamanho na entrada + mass assignment + coerção sem guarda
grep -rlnE "content-length|MAX_BYTES|file\.size|\.length *> *[0-9]{3}" supabase/functions/*/index.ts 2>/dev/null
grep -rnE "\.(insert|update|upsert)\((body|payload|data|input|params)\b|\.(insert|update|upsert)\(\{ *\.\.\.|Number\((body|payload|params|url\.searchParams)" \
  src supabase/functions --include="*.ts" --include="*.tsx" 2>/dev/null
```

```sql
-- 3. função que o papel anônimo executa com parâmetro que decide dinheiro/permissão/identidade
select p.oid::regprocedure, pg_get_function_arguments(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'EXECUTE')
   and pg_get_function_arguments(p.oid) ~* '(total|price|amount|valor|desconto|status|role|user_id|owner|content)';
```

Sem acesso ao banco, o item 3 vira estático: o `GRANT EXECUTE ... TO anon` nas migrations e a
leitura da assinatura de cada função.
