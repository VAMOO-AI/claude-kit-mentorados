# 04 · Rate limit, quota e superfície pública

Autenticação responde "quem é você". Rate limit responde "quantas vezes você pode
fazer isso". Sem o segundo, uma conta legítima comprometida vale tanto quanto uma
brecha — e sai mais caro, porque ninguém desconfia de tráfego autenticado.

O gatilho de "precisa de limite" não é "é público". É **"custa alguma coisa"**:
dinheiro (LLM, SMS, WhatsApp), reputação (e-mail, disparo) ou tempo de CPU do
banco.

## Contrato

- [ ] **Toda superfície pública tem rate limit por identidade** (IP, telefone,
      chave de API — o que existir).
- [ ] **Toda chamada que custa dinheiro tem teto por usuário e por janela.**
- [ ] **Chamada de LLM tem `max_tokens` explícito.** Sempre.
- [ ] **Gasto acumulado de IA tem teto próprio, consultado ANTES da chamada.**
      Rate limit por identidade não alcança worker autônomo — ele não tem
      usuário. Bateu o teto, o sistema pausa e avisa; não degrada em silêncio.
- [ ] **Webhook público valida segredo com comparação em tempo constante**, no
      header — nunca em query string, nunca em body.
- [ ] **Função sem verificação de JWT está em allowlist explícita**, e cada uma
      tem auth própria *provada*.
- [ ] Job agendado autentica com segredo próprio, não com a anon key.
- [ ] Falha de limite retorna `429` com `Retry-After`, e é logada.

## Como implementar

**Rate limit no Supabase — a versão que não precisa de Redis.** Uma tabela, um
índice e uma função; o custo é uma linha por janela.

```sql
create table if not exists public.rate_limit_hits (
  bucket      text        not null,          -- 'ai-chat:<user_id>'
  window_start timestamptz not null,
  hits        int         not null default 0,
  primary key (bucket, window_start)
);

create or replace function public.rate_limit_take(
  p_bucket text, p_limit int, p_window interval default '1 hour')
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_start timestamptz; v_hits int;
begin
  v_start := date_trunc('hour', clock_timestamp());   -- ajuste à janela
  insert into public.rate_limit_hits (bucket, window_start, hits)
       values (p_bucket, v_start, 1)
  on conflict (bucket, window_start)
       do update set hits = public.rate_limit_hits.hits + 1
    returning hits into v_hits;
  return v_hits <= p_limit;
end $$;
```

`clock_timestamp()`, não `now()`: dentro de uma transação `now()` é constante, e
uma função de limite que enxerga o tempo congelado conta errado no lote.

Na edge function:

```ts
const { data: ok } = await admin.rpc('rate_limit_take', {
  p_bucket: `ai-chat:${user.id}`, p_limit: 50, p_window: '1 hour',
})
if (!ok) return new Response(
  JSON.stringify({ error: 'rate_limited' }),
  { status: 429, headers: { 'Retry-After': '3600', 'Content-Type': 'application/json' } })
```

**Teto de LLM — três limites, não um:**

```ts
// 3) teto de gasto acumulado — consultado ANTES de chamar, não depois
const gasto = await gastoDoPeriodo()             // soma de custo_usd em ai_calls
if (gasto >= Number(env.AI_MONTHLY_BUDGET_USD)) {
  await pausarSistema('ai_budget_exceeded')      // pausa geral + alerta
  throw new OrcamentoEstouradoError(gasto)
}

const res = await openai.chat.completions.create({
  model, messages,
  max_tokens: 1500,          // 1) teto por chamada — impede resposta infinita
})
// 2) teto por usuário/janela via rate_limit_take acima — impede mil chamadas
```

`max_tokens` sozinho não protege: mil chamadas de 1500 tokens custam o mesmo que
uma de 1.5M. Os três limites são ortogonais e todos são necessários.

Os dois primeiros são **por identidade** — e é exatamente isso que falta num
worker que classifica, resume ou prospecta sozinho: não há usuário a limitar, o
único limite dele é dinheiro. Quem não consulta o gasto antes da chamada
descobre o loop pela fatura. E o corte tem que **pausar**: cair para um modelo
mais barato em silêncio troca uma conta alta por uma queda de qualidade que
ninguém liga à causa.

**Segredo de webhook — comparação em tempo constante:**

```ts
function secretMatches(provided: string | null, expected: string): boolean {
  if (!provided || provided.length !== expected.length) return false
  let diff = 0
  for (let i = 0; i < expected.length; i++) diff |= provided.charCodeAt(i) ^ expected.charCodeAt(i)
  return diff === 0
}

const ok = secretMatches(req.headers.get('x-app-secret'), Deno.env.get('APP_SECRET')!)
if (!ok) return new Response('unauthorized', { status: 401 })
```

Header, sempre. Query string vaza em log de proxy, em Referer e no histórico.

**Allowlist de `verify_jwt = false` — no CI, não no dashboard:**

```bash
PUBLIC_FUNCTIONS="webhook-provedor status-callback oauth-callback"
for fn in supabase/functions/*/; do
  name=$(basename "$fn")
  case " $PUBLIC_FUNCTIONS " in
    *" $name "*) supabase functions deploy "$name" --no-verify-jwt ;;
    *)           supabase functions deploy "$name" ;;
  esac
done
```

Duas coisas que isso resolve: a lista de exceções fica versionada e revisável em
PR, e **deploy sem `config.toml` reseta `verify_jwt` para `true`** — o que quebra
o webhook em silêncio se a exceção só existia no dashboard.

Cada nome nessa lista precisa de uma linha no contrato dizendo **qual** auth
própria ele tem. Sem isso, a allowlist vira a lista de portas abertas.

## Como provar

```bash
# funções sem verificação de JWT vs allowlist declarada
grep -rn 'PUBLIC_FUNCTIONS=' .github/workflows/ 2>/dev/null
ls supabase/functions/

# cada uma valida segredo? (procure a checagem, não a variável)
for d in supabase/functions/*/; do
  n=$(basename "$d")
  if grep -qE 'headers\.get\(|verifySecret|secretMatches|timingSafeEqual' "$d/index.ts" 2>/dev/null
    then echo "OK   $n"; else echo "SEM  $n"; fi
done

# chamada de LLM sem teto
grep -rn 'chat.completions.create\|generateContent\|messages.create' supabase/functions/ src/ \
  | while read -r l; do f=${l%%:*}; grep -qE 'max_tokens|maxOutputTokens|max_output_tokens' "$f" \
  || echo "SEM max_tokens: $f"; done

# rate limit existe em algum lugar?
grep -rniE 'rate_limit|ratelimit|429|Retry-After' supabase/functions/ | grep -v node_modules | head
```

Teste vivo do limite (só em ambiente autorizado pelo contrato):

```bash
for i in $(seq 1 30); do
  curl -s -o /dev/null -w '%{http_code} ' "https://$REF.supabase.co/functions/v1/<fn>" \
    -H "Authorization: Bearer $TOKEN"
done; echo
# esperado: uma sequência de 200 e depois 429. Só 200 = não tem limite.
```

## Armadilhas

| Sintoma | Causa real |
|---|---|
| Fatura de LLM explodiu sem pico de usuários | Uma conta em loop. `max_tokens` ausente e zero quota por usuário |
| Webhook parou depois de um deploy comum | Deploy sem `config.toml` resetou `verify_jwt=true`. A exceção só existia no dashboard |
| Rate limit conta errado em processamento de lote | `now()` é constante na transação. Use `clock_timestamp()` |
| Segredo de webhook aceito e mesmo assim invadido | Comparação com `===` vaza tempo; ou o segredo estava na query string e vazou no log do proxy |
| Job agendado parou de rodar e ninguém viu | Autenticava com anon key e a policy mudou. Cron precisa de segredo próprio e de alerta (pilar 06) |
| "É interno, não precisa de limite" | Interno é onde estão os tokens válidos. Limite protege de conta comprometida, não de estranho |
| Limite existe mas ninguém sabe quando bate | `429` sem log. Estourar limite é evento de segurança, não ruído |
