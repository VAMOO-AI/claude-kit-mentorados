# 03 · Autenticação, permissão por usuário e rotas protegidas

A regra que resume o pilar inteiro: **esconder um botão não é proteger um dado.**
O front decide o que *mostrar*; o banco decide o que *entregar*. Quando essas duas
decisões discordam, quem ganha é o banco — e é por isso que só uma delas é
segurança.

## Contrato

- [ ] Sessão validada contra o provedor, não contra o que está no `localStorage`.
- [ ] **Fail-closed em papel desconhecido.** Papel que não está no mapa vê o
      mínimo, nunca o máximo.
- [ ] **Fail-closed em perfil ausente.** Autenticado sem registro de perfil = sem
      acesso, não acesso padrão.
- [ ] **Todo gate de UI declara sua contrapartida no banco, ou é marcado como
      cosmético** no contrato do projeto. Sem meio-termo, sem "é só pra
      organizar".
- [ ] Rota/módulo sensível resolve permissão **antes** de renderizar e antes de
      buscar dado.
- [ ] MFA quando o dado justifica — e com contrapartida no banco, senão é
      decoração.
- [ ] Logout e expiração limpam estado local; sessão expirada não vira request
      anônima silenciosa.

## Como implementar

**Fail-closed — o antipadrão e o padrão, lado a lado:**

```ts
// ERRADO: papel novo no banco passa a ver tudo
export const canAccess = (role: Role, mod: Module) =>
  (ROLE_MODULES[role] ?? ALL_MODULES).includes(mod)

// CERTO: desconhecido cai no mínimo
export const canAccess = (role: Role | undefined, mod: Module) =>
  (role ? ROLE_MODULES[role] ?? MINIMAL_MODULES : MINIMAL_MODULES).includes(mod)
```

O `?? ALL_MODULES` parece defensivo ("não quebrar a UI") e é o oposto: no dia em
que alguém cadastra um papel novo no banco, ele nasce com acesso total e ninguém
recebe erro. Falha silenciosa e aberta é a pior combinação possível.

**Perfil ausente também é fail-closed:**

```ts
const { data: profile, error } = await supabase
  .from('user_profiles').select('role').eq('id', user.id).maybeSingle()

if (error || !profile) {
  // autenticado mas sem perfil → NÃO autorizado.
  return { isAuthenticated: false, reason: 'perfil-ausente' }
}
```

**Gate de rota — quando não há router**, o gate vive na resolução do módulo ativo
e precisa rodar antes do fetch:

```tsx
const allowed = canAccess(role, requested)
const active  = allowed ? requested : defaultModuleFor(role)
// resolver ANTES: um <Component/> montado dispara o fetch, e o fetch é o que
// realmente vaza — a tela em branco não protege nada.
```

**MFA com contrapartida no banco** — o padrão que funciona: o front exige AAL2
para considerar autenticado, e o banco também exige, via helper usado nas policies.

```sql
create or replace function public.auth_has_aal2()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(
    (current_setting('request.jwt.claims', true)::jsonb ->> 'aal') = 'aal2',
    false)
$$;

-- e a policy usa:
create policy "financeiro exige aal2" on public.faturamento
  for select to authenticated
  using (public.auth_has_aal2() and <regra de linha>);
```

Sem essa função na policy, o MFA é uma tela: o token de AAL1 continua valendo no
PostgREST.

**Declarar a contrapartida.** No contrato do projeto, cada gate vira uma linha:

| Gate na UI | Contrapartida no banco | Veredito |
|---|---|---|
| ATENDIMENTO só vê o módulo SDR | *(nenhuma — tabelas ERP têm `USING (true)`)* | **cosmético** |
| Vendedor vê só a carteira dele | policy em `customers` via `customer_owners` | real |
| Só ADMIN gerencia usuários | policy em `user_profiles` + `role_permissions` | real |

"Cosmético" não é acusação — é informação. O problema não é ter gate cosmético; é
não saber qual dos seus gates é.

## Como provar

O único teste que vale é com um token real do papel mais restrito.

```bash
# 1) pegue um access_token de um usuário do papel restrito (login na app, devtools)
TOKEN='eyJ...'
REF='<project-ref>'; ANON='<anon-key>'

# 2) o que ele consegue ler de uma tabela que a UI esconde dele?
curl -s "https://$REF.supabase.co/rest/v1/erp_faturamento?select=*&limit=5" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" | head -c 400
# [] → a policy protege.  linhas → o gate era só da UI.

# 3) e sem token nenhum?
curl -s "https://$REF.supabase.co/rest/v1/erp_faturamento?select=*&limit=1" \
  -H "apikey: $ANON" | head -c 200
```

Estático, como apoio:

```bash
# fail-open em mapa de permissão
grep -rn '?? ALL\|?? \[\]' src/constants src/lib 2>/dev/null | grep -i 'role\|module\|permission'

# rota/módulo sem checagem antes do fetch
grep -rn 'canAccess\|hasPermission\|PermissionGate' src/ | wc -l
```

O passo 2 é o pilar inteiro. Ele responde "o gate é real ou é tela?" em um
comando — e responde para o dado, não para o componente.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| Papel novo no banco enxerga tudo | `ROLE_MODULES[role] ?? ALL_MODULES`. Fail-open disfarçado de defensivo |
| Lista volta vazia sem erro depois de um tempo aberto | Sessão expirou, o cliente caiu pra anon, RLS devolveu `200 []`. Não é bug de dado |
| "O vendedor não deveria ver isso" e a tela não mostra | Ele não vê na tela; vê no PostgREST. Teste com token, não com screenshot |
| MFA ligado e o dado continua acessível | O gate de AAL2 está só no front. Sem helper na policy, o token AAL1 passa |
| Usuário sem perfil entra e vê o app quebrado | Faltou fail-closed em perfil ausente. Autenticado ≠ autorizado |
| Componente escondido mas request disparada | Gate resolvido depois da montagem. O `useEffect` do filho já buscou |
| Permissão só muda com deploy | Papel e permissão hardcoded no front. Permissão granular pertence a tabela |
