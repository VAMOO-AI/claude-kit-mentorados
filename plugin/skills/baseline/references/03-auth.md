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
- [ ] **Cadastro do Auth fechado, ou conta nova nasce sem poder.** Sem tela de
      cadastro no app, o `POST /auth/v1/signup` com a chave anon continua
      aberto se o painel deixar. Ou o painel fecha (`disable_signup`), ou toda
      conta nova nasce com papel mínimo e `ativo = false` até alguém liberar.
- [ ] **Papel nunca vem de `user_metadata`.** O usuário escreve esse campo no
      `signUp` e no `updateUser`. Papel, plano e tenant saem de `app_metadata`
      ou de uma tabela que só o servidor grava, inclusive no trigger de cadastro.
- [ ] **Autenticado ≠ membro.** Nenhuma policy de dado interno aceita
      `auth.role() = 'authenticated'`, `auth.uid() is not null` ou
      `<getter>() is not null` sozinho. O predicado prova vínculo (perfil ativo
      e aprovado, ficha de equipe, liberação do módulo), e a linha que prova o
      vínculo não nasce sozinha por trigger com papel padrão.
- [ ] **Todo helper de papel confere conta ativa**, não só o de admin.
- [ ] **E-mail só identifica se foi confirmado.** Com auto-confirmação, o
      e-mail do JWT é o que a pessoa digitou: autorização por e-mail ou domínio
      exige confirmação ligada e `email_confirmed_at`.
- [ ] Senha mínima e requisitos do **painel** iguais aos da tela.
- [ ] **Uma fonte só para o papel.** Todo endpoint que responde "quem sou eu"
      (`/me`, sessão, layout) e todo lugar que decide papel leem a mesma
      fonte. Duas fontes divergem, e o front esconde o que o servidor aceita.
- [ ] **Cookie de sessão própria com prefixo `__Host-`** (`Secure`, `Path=/`,
      sem `Domain`). Sem o prefixo, qualquer subdomínio do mesmo domínio
      planta ou lê a sessão. `SameSite` não ajuda: subdomínio irmão é o mesmo
      site. Renomear desloga todo mundo; marque a janela.
- [ ] **Cookie do `@supabase/ssr` não é sessão própria: não exija `HttpOnly`.**
      O cliente do navegador (`createBrowserClient`) lê a sessão do cookie para
      falar com o PostgREST, e a biblioteca grava com `httpOnly: false` por
      padrão. Ligar `HttpOnly` quebra o login. Exija `Secure` (o mesmo
      `cookieOptions` nos clientes de browser, servidor e middleware) e trate a
      CSP do pilar 01 como a defesa contra script que lê o token. A falta de
      `HttpOnly` aqui entra como limite de arquitetura, `INFO`, não como achado.
- [ ] **Sessão de um app não autentica outro.** Apps irmãos que dividem a
      tabela de sessões ou o segredo de assinatura conferem o host (ou a
      audiência) do token.
- [ ] **Mutação com cookie confere `Origin` de forma estrita** e só aceita
      `application/json`. `text/plain` não dispara preflight, e cair para o
      `Referer` quando falta `Origin` aceita `Referer` forjado. Com app em vários
      subdomínios, some um token anti-CSRF (duplo-submit). Estrita não é
      `origin === new URL(request.url).origin`: atrás de proxy a URL da
      requisição pode trazer o host interno, e toda escrita vira 403 (a forma
      certa está em "Sessão e CSRF").

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

O único teste que vale é com um token real do papel mais restrito. Só que o token
é credencial de uma pessoa e a resposta traz linhas de produção: os dois ficam no
terminal de quem roda, e a prova volta como **contagem**. Num `HEAD` com
`Prefer: count=exact`, o PostgREST devolve o total no `Content-Range` (o número
depois da barra) e nenhuma linha.

Escreva o roteiro num arquivo e entregue o comando do `hitl-loop.sh` como a
`verificacao` manda na seção "O que só um humano consegue verificar": caminhos
absolutos, e quem roda é a pessoa, não você. Troque `erp_faturamento` pela tabela
que a UI esconde desse papel:

```text
# /tmp/roteiro-gate.txt (escrito pelo agente)
# 1) o token entra no terminal da pessoa, nunca na conversa
passo Em outra aba do terminal: read -rs TOKEN e cole o access_token de um usuário do papel restrito (login na app, devtools); depois REF='<project-ref>'; ANON='<anon-key>'
# 2) o que ele consegue ler de uma tabela que a UI esconde dele?
passo Nessa aba: curl -sI "https://$REF.supabase.co/rest/v1/erp_faturamento?select=*" -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H "Prefer: count=exact" | grep -iE '^http|^content-range'
captura LINHAS_COM_TOKEN Qual é o número depois da barra no content-range? (*/0 é 0; sem content-range, rode o mesmo curl sem o -I e sem o grep, e responda negado, o status e a mensagem de erro, ex.: negado 401 JWT expired)
# 3) e sem token nenhum?
passo Agora sem o token: curl -sI "https://$REF.supabase.co/rest/v1/erp_faturamento?select=*" -H "apikey: $ANON" -H "Prefer: count=exact" | grep -iE '^http|^content-range'
captura LINHAS_SEM_TOKEN E o número depois da barra, sem token? (mesma regra)
```

```bash
# o que a pessoa roda, num terminal dela (caminho absoluto no lugar da variável)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/hitl-loop.sh" /tmp/roteiro-gate.txt --saida /tmp/gate.txt
# LINHAS_COM_TOKEN=0 → a policy protege (0 só prova se a tabela tem linhas). >0 → o gate era só da UI.
# LINHAS_SEM_TOKEN>0 → qualquer um com a anon key lê a tabela.
# negado … permission denied → o papel não tem GRANT na tabela, e isso também protege.
# negado com outra mensagem (JWT, API key) → a prova não rodou: corrija e refaça.
```

O bloco `--- capturado ---` do `--saida` é a prova que vai no report, sem token e
sem linha de produção.

**Com acesso SQL, a mesma prova sai sem token e para todas as tabelas de uma vez:**
`scripts/matriz-rls.sql` personifica um usuário existente numa transação `read only` e
devolve, por objeto, quantas linhas existem e quantas o papel lê. É o denominador que falta
no roteiro acima: "0 linhas" numa tabela vazia não prova nada.

```bash
psql "$SUPABASE_DB_URL_RO" -X -v ator=<uuid do usuário do papel restrito> -f "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/matriz-rls.sql"
```

### Sessão e CSRF (só leitura)

Os dois primeiros comandos só leem o `Set-Cookie` da resposta de login de uma
conta de teste e o que a API aceita, sem mudar nada. Troque `<host>` e a rota.

```bash
# atributos do cookie de sessão: o nome tem que começar com __Host-, e sem Domain=
curl -sS -o /dev/null -D - "https://<host>/login" | grep -i '^set-cookie' | sed -E 's/=[^;]*/=<valor>/'
# a mutação aceita text/plain? Rode em ambiente local ou de teste, sem cookie: só o
# status importa (415 é o certo; 401/403 aceitou o tipo e barrou pela sessão)
curl -sS -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: text/plain' \
  --data '{}' "http://localhost:3000/api/<rota de escrita>"
```

O teste do `Origin` e do `Referer` forjados manda uma mutação com sessão: só
em ambiente local ou de teste, nunca em produção.

O atributo `__Host-` e a exigência de `HttpOnly` valem para cookie de sessão
própria. Com `@supabase/ssr`, leia `Secure` e `SameSite` no `Set-Cookie` de
depois do login (o `GET /login` ainda não tem o cookie de sessão) e não acuse a
falta de `HttpOnly` (ver o Contrato).

**A forma da checagem de `Origin` que não quebra atrás de proxy:**

1. `Sec-Fetch-Site` primeiro: `same-origin` e `none` passam, o resto é 403;
2. só sem esse header, compare o `Origin` com o conjunto {origem da URL da
   requisição, `x-forwarded-host` **quando o proxy da plataforma o sobrescreve**,
   URL pública do app vinda de variável de ambiente};
3. corpo `application/json` obrigatório;
4. rota que autentica por `Authorization: Bearer` (token de API, OAuth, MCP) fica
   fora: é cross-origin por desenho, e o helper aplicado no middleware inteiro
   derruba o integrador.

O teste que prova: requisição com URL interna e `Origin` público passa; `Origin`
de outro site é 403. Rode os dois antes de "pronto".

### Quem vira membro

A pergunta que vem antes de "o corretor A vê a carteira do B?" é "quem consegue
virar corretor?". Dois pentests de sistemas com RLS correta em todas as tabelas
acharam o mesmo caminho: cadastro aberto no painel, mais um predicado que lê
"tem sessão" como "é da equipe", ou um trigger que copia o papel do metadata. O
`collect.sh` roda o `quem-entra.py` no pilar 03; para ler sozinho:

```bash
python3 -I "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/quem-entra.py" --root .
```

Ele lê o estado **efetivo** das migrations (a última definição de cada função,
policy e trigger vence, na ordem do arquivo) e emite uma linha por fato:

| Check | O que acusa |
|---|---|
| `auth_signup_aberto`, `auth_sem_confirmacao`, `auth_senha_curta` | bloco `[auth]` do `config.toml`. Sem o arquivo, sai `nao_medido` dizendo que o estado mora no painel |
| `papel_do_metadata` | função, trigger ou policy que decide papel por `raw_user_meta_data` / `user_metadata` |
| `autoprovisao_cadastro`, `autoprovisao_acesso` | o que roda quando a conta nasce, com o papel padrão; trigger que cria a linha que uma policy usa como prova de vínculo |
| `autenticado_e_membro` | policy efetiva com predicado de existência. HIGH quando escreve e o cadastro está aberto ou não foi medido |
| `papel_sem_conta_ativa` | helper `is_*`/`sou_*`/`eh_*` que lê o perfil sem olhar `ativo` |
| `identidade_por_email` | `auth.jwt()->>'email'` sem `email_confirmed_at` |
| `hmac_sem_janela`, `segredo_na_query`, `cota_em_tabela_do_usuario`, `guard_depois_do_stream`, `escrita_sem_conferir`, `cookie_longo` | as armadilhas da tabela abaixo |

A config do `config.toml` vale para o ambiente local. O que vale em produção é o
painel. O `sonda-auth-viva.sh` lê o mesmo que o atacante, só com GET:

```bash
# a anon é pública; o PAT é opcional e só serve para ler a senha mínima
SUPABASE_URL='https://<ref>.supabase.co' SUPABASE_ANON_KEY='<anon>' APP_URL='https://<app>' \
  bash "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/sonda-auth-viva.sh" /admin /api/diag
# VEREDITO cadastro ABERTO (disable_signup=false) → com autenticado_e_membro acima, é o achado alto
```

Sem o painel lido, o cadastro é `não medido`, nunca "fechado". Calar foi o que
deixou passar uma conta `admin` criada por `signUp`.

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
| Conta criada pela API entra como admin, e o app nem tem tela de cadastro | Signup aberto no painel e o trigger de cadastro copia `raw_user_meta_data->>'role'` |
| RLS impecável e um estranho lê a carteira inteira | O predicado é `auth.role() = 'authenticated'` ou `is_membro()` sem `ativo`. Correto para funcionário, e o cadastro estava aberto |
| Policy exige ficha e a ficha aparece sozinha | Trigger de auto-provisão cria a linha com papel padrão no `else`. A prova de vínculo virou prova de existência |
| `email @suaempresa.com` vira "da casa" sem convite | Auto-confirmação ligada: o e-mail do JWT é o que a pessoa digitou |
| Conta desativada continua gravando por até 1 h | Só o helper de admin confere `ativo`; o JWT segue válido |
| `/admin` "redireciona" e o monitor diz 200 | `loading.tsx` acima da página: o shell sai antes do `redirect()`, que vira meta-refresh |
| Cota de IA esgota sem ninguém perguntar nada | O freio conta linhas de uma tabela que a sessão insere direto pelo PostgREST |
| Grep acusa o que a migration seguinte já corrigiu | Lida a primeira definição, não a efetiva. Vale a última, e o banco vivo vence as duas |
| Front esconde a escrita e o servidor aceita | `/me` lê uma fonte de papel e o middleware outra. Uma fonte só |
| `SameSite=lax` e a sessão vaza para outro app da casa | Subdomínio irmão é o mesmo site. Cookie sem `__Host-` e sessão aceita no outro host |
| `Origin` forjado é recusado e o CSRF passa mesmo assim | A checagem cai para o `Referer` quando falta `Origin`, e a API aceita `text/plain` |
