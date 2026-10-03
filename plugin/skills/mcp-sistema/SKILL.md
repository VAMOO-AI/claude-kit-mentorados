---
name: mcp-sistema
description: >-
  Cria o MCP remoto de um sistema Supabase para o usuário ligar Claude, ChatGPT
  ou outro cliente com a própria conta: Next.js com OAuth do Supabase, recorte
  por papel, escrita com prévia + confirmação + log e página de instalação; app
  não-Next (SPA Vite) com OAuth próprio numa edge function. Entrevista → spec →
  PRs → prod. Use em "cria um MCP pro sistema", "MCP com login", "ligar no
  ChatGPT", "o MCP dá timeout". Não é para MCP local/stdio (mcp-builder).
---

# MCP remoto de um sistema (Supabase)

Duas receitas, cada uma tirada de um MCP em produção, com o código de referência
despersonalizado: adapte nomes de tabela, papéis e tools ao projeto alvo.

- **Next.js + Supabase Auth** (dashboard comercial com
  vendedor/gerente/diretoria/suporte): rota `/api/mcp`, Supabase OAuth Server,
  recorte por papel, escrita, página. É o corpo desta skill e `references/code/`.
- **App não-Next + Supabase** (SPA Vite na Vercel): servidor MCP + OAuth próprio
  numa edge function, token opaco, um dono, só leitura.
  `references/edge-function.md` e `references/code/edge/`.

## Como ler esta skill

| Arquivo | Quando abrir |
|---|---|
| `references/entrevista.md` | Fase 0, antes de qualquer código |
| `references/oauth-supabase.md` | PR 1: ligar o OAuth Server, consentimento, proxy, login |
| `references/servidor.md` | PR 1 e 2: rota `/api/mcp`, `verifyToken`, principal, escopo, tools |
| `references/banco.md` | PR 1 (antes do merge) e antes de liberar a 2ª pessoa |
| `references/escrita.md` | PR 3: prévia → token → aplicar → log |
| `references/pagina.md` | PR 4: página MCP, guia de instalação, prompts, chave por usuário |
| `references/edge-function.md` | Fase 0 mandou para a receita de edge function (app não-Next ou schema grande) |
| `references/code/` | Arquivos copiáveis citados pelas referências (`code/edge/` = receita edge) |

## Fase 0 — entrevista e spec

1. Descubra a stack (`package.json`, `src/proxy.ts` ou `middleware.ts`, client
   Supabase de service role, tabela de usuários/papéis) e escolha a receita:
   - **Next.js + Supabase Auth** → receita Next (o resto deste arquivo).
   - **Não é Next.js, mas o backend é Supabase** (SPA Vite, front estático) e o
     app tem domínio próprio com rewrite (Vercel) → diga em 1 frase que a receita
     Next não cabe e siga `references/edge-function.md`. Ela entrega um dono e só
     leitura; multiusuário com papel está lá como decisão aberta, não verificada.
   - **Next.js com centenas de tabelas abertas a `authenticated`** → a trava
     RESTRICTIVE (`banco.md`) fica cara. Ofereça a receita edge como opção, com
     o tradeoff (token opaco que só abre a função × recorte por papel pronto da
     receita Next); o usuário decide.
   - **Sem Supabase** → diga em 1 frase que nenhuma das receitas cobre e pare.
2. Rode a entrevista de `references/entrevista.md` (uma pergunta por vez, com
   recomendação). Ela fecha: hierarquia, fonte do papel, quem libera o acesso,
   dados v1, escritas, endpoint, página. Na receita edge, feche dados v1, o canal
   do código ao dono (WhatsApp, e-mail) e o domínio público; papel só entra se for
   multiusuário.
3. Grave a spec em `docs/superpowers/specs/<data>-mcp-<sistema>-design.md` com a
   tabela de decisões, o escopo por papel e a ordem de rollout. A spec é o
   contrato dos 4 PRs; atualize o status dela a cada merge.

## Os 4 PRs (cada um só fecha com a prova dele)

| PR | Entrega | Prova que fecha |
|---|---|---|
| 1 — OAuth + `whoami` | deps, `/api/mcp`, well-known, proxy, consentimento, redirect do login, coluna de liberação, config do Auth | `claude mcp add` → login (com MFA se o app exige) → `whoami` responde com nome e papel; o access token traz a claim `client_id` |
| trava (entre 1 e 2) | policy RESTRICTIVE "sem token oauth" em toda tabela aberta a `authenticated` + `storage.objects` | `SET ROLE authenticated` com e sem `client_id` na claim, em `ROLLBACK`: com `client_id` lê 0 linhas e UPDATE afeta 0 |
| 2 — leitura | função de escopo pura + tools de leitura | testes de escopo por papel escritos ANTES (vendedor pedindo dado de outro, gerente fora do time, papel sem acesso a valor) |
| 3 — escrita | `*_previa` / `*_aplicar`, token HMAC, tabela de auditoria | teste: token de outra conta, de outra escrita, expirado e com estado mudado são recusados; sem a tabela de log nada grava |
| 4 — página + chave | view MCP, guia de 4 passos, prompts por papel, `GET /api/me/mcp`, chave em Usuários | a página só aparece para quem o SERVIDOR aceitaria (mesma função de decisão) |

Commit, PR e deploy de cada um seguem a skill `ship`. SQL avulso e config do
Auth rodam por script do projeto com token em variável de ambiente, nunca por
login interativo da CLI.

## Rollout em produção (ordem importa)

1. A liberação por pessoa nasce **desligada para todos** — é ela que contém o risco
   até o fim.
2. Endureça a RLS da tabela de papel (`banco.md` §2) antes do PR 1: se qualquer
   logado consegue dar UPDATE nela via REST, o MCP herda um "vira admin".
3. GET da config do Auth como baseline → PATCH só nas chaves do OAuth Server.
4. Merge do PR 1 → liga só para o dono → `whoami` ponta a ponta.
5. Aplica a trava "sem token oauth" → só então libera outra pessoa.
6. PR 2, 3, 4 na ordem. Migration de cada PR aplicada antes do merge dele.

## Armadilhas (cada uma já custou um incidente)

- **`client_id` obrigatório no `verifyToken`.** O token do OAuth Server é um JWT
  `authenticated` comum; sem exigir a claim, a sessão web colada como Bearer abre
  o MCP.
- **Token OAuth também vale no PostgREST.** O cliente MCP que tem o token lê e grava
  direto na API REST, por fora das tools e do recorte. Trava RESTRICTIVE em toda
  tabela aberta a `authenticated`/`public` — liste pela query de `banco.md`, nunca
  de memória. **Tabela nova aberta a `authenticated` entra na trava no mesmo PR.**
  Schema com centenas de tabelas: veja o ramo da Fase 0 (receita edge).
- **ChatGPT não aceita Bearer fixo.** Só OAuth, sem auth ou misto: chave estática
  no header liga no Claude Code, não no ChatGPT.
- **`x-api-key` (ou qualquer chave de serviço) não abre `/api/mcp`.** No proxy, a
  rota do MCP sai ANTES do bloco que transforma a chave em usuário de serviço.
- **Papel de UMA fonte, lido a cada chamada.** Desligar a pessoa corta na próxima
  tool, sem esperar o token expirar. Liga pessoa ↔ registro de negócio por
  `auth_user_id`, nunca por nome (homônimos existem).
- **O recorte é feito na tool.** Rota HTTP existente quase nunca recorta por papel;
  a tool chama a lib de negócio e filtra pelo escopo.
- **Hierarquia na data consultada.** Quem mudou de time no meio do ano: o recorte
  de um mês passado usa o time daquele mês, não o vivo.
- **Agregado vaza dado alheio.** Ranking, top clientes e previsão de time: quem só
  vê o próprio recebe a própria posição e o total do time, sem valores de colegas.
- **A decisão do consentimento revalida o gate.** O form é HTML puro; um POST com
  `decision=approve` chega mesmo quando a tela só ofereceu "Voltar".
- **`subscriptions/listen` recusado.** Clientes do protocolo `2026-07-28` abrem esse
  request e o SDK serve um SSE que nunca fecha: na função serverless ele morre no
  `maxDuration`, reabre, e ocupa um slot de conexão do cliente, que passa a
  enfileirar as tools. Sintoma: `The operation timed out.` em tools baratas quando
  o agente chama várias em paralelo — a tool nem chega ao servidor. Assinatura nos
  logs: um POST que morre exatamente no `maxDuration` logo depois do `initialize`,
  repetindo. `refuseListen` responde `-32601` na hora (`servidor.md`).
- **Log de tempo por tool desde o PR 1** (`[mcp] tool=X ms=Y ok|erro|timeout`) e
  deadline abaixo do `maxDuration`. Sem ele, travamento não deixa rastro.
- **Cache por instância não resolve concorrência na Vercel**: chamadas paralelas
  caem em instâncias diferentes. Tool pesada precisa de cache entre instâncias
  (`unstable_cache`, tabela de snapshot).
- **Escrita**: a prévia não grava; o aplicar relê TUDO, recusa se o estado mudou e
  grava o log ANTES da escrita. Sem log, sem escrita.
- **Catálogo de prompts roda no navegador**: só `import type` do módulo do
  principal, senão o bundle puxa a service role.
- **Redirect pós-login** vira open redirect sem validação (`//evil.com`, `/\evil.com`).

### Armadilhas da receita edge function (detalhe em `references/edge-function.md`)

- **O Vercel não reescreve `/.well-known`** (path reservado). Os metadados RFC 8414
  e 9728 são arquivos estáticos em `public/.well-known/`, com
  `Content-Type: application/json` no `vercel.json`. Um teste compara os
  estáticos com o handler.
- **Service worker de PWA engole a navegação do `/authorize`.** O
  `navigateFallback` serve o `index.html` do SPA, e em modo `prompt` o SW antigo
  segue ativo até o usuário atualizar. O `authorization_endpoint` fica no host da
  função e só responde 302 para um `.html` da raiz do app (com o `.html` da raiz,
  `/mcp`, `/oauth/` e `/.well-known/` no `navigateFallbackDenylist`).
- **No `supabase.co`, a edge function serve `text/html` como `text/plain`.** Nenhuma
  tela sai da função: ela devolve JSON e 302; o HTML é estático no domínio do app.
- **Protocolo `2026-07-28`.** Servidor legado responde `400` sem corpo a
  `MCP-Protocol-Version` desconhecido. Um erro "moderno" (`-32022`) faz o cliente
  não cair no `initialize`.
- **ChatGPT e RFC 9207.** Anuncie `authorization_response_iss_parameter_supported`
  e devolva `iss` em toda resposta do authorize (sucesso e erro). Sem isso o
  callback do ChatGPT muda a cada conexão (`chatgpt.com/connector/oauth/<id>`). O
  handler aceita esse formato por garantia; o verificado é o callback estável.

## Verificação (antes de dizer "pronto")

- tsc + lint + testes + build do projeto, output colado (skill `verificacao`).
- Em prod, com um cliente real: `whoami`; depois 8 tools em paralelo e leitura das
  linhas `[mcp] tool=` nos logs (`vercel logs --query "/api/mcp"`). Nenhum POST pode
  morrer no `maxDuration`.
- Papel: logue como cada papel (ou simule o principal nos testes) e peça um dado
  fora do recorte — tem que voltar "não encontrado no seu nível de acesso".
- Escrita: prévia → aplicar; prévia → mudar o dado pelo app → aplicar (tem que
  recusar); conferir a linha no log de auditoria.

**Receita Next — verificada em produção** com Claude Code (login + MFA, 22 tools,
paralelo, listen recusado sem o cliente entrar em loop). Não verificada nela:
claude.ai e ChatGPT. Ao ligar o ChatGPT, confira se o metadata do Supabase OAuth
Server traz `authorization_response_iss_parameter_supported`; sem ele o ChatGPT
registra um callback por conexão.

**Receita edge — verificada em produção em 03/10/2026** nos três clientes, login +
tools, 0 erro nos logs:

| Cliente | Como liga | Callback confirmado |
|---|---|---|
| Claude Code | `claude mcp add --transport http <nome> <url>` → `/mcp` → autenticar (`claude mcp login` só em terminal interativo) | `http://localhost:<porta>/callback` ou `http://127.0.0.1:<porta>/callback`, porta aleatória |
| claude.ai / Desktop | Conectores → Adicionar conector personalizado → URL (detecta OAuth + DCR sozinho); cada tool pede "Permitir" na 1ª chamada | `https://claude.ai/api/mcp/auth_callback` |
| ChatGPT | Plugins → Adicionar → Criar servidor MCP personalizado → URL + OAuth (não procure "Developer mode") | `https://chatgpt.com/connector_platform_oauth_redirect` (estável com RFC 9207) |
