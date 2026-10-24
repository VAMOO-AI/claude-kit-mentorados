# Checklist de incidentes — 27 checks que já custaram caro

> Referência da skill `secscan`. Consulte durante as Fases 2 (C2/C3), 4 (C5) e o fim da
> Fase 3 e da Fase 5 (C6), ou quando um finding precisar de precedente. Não é leitura
> obrigatória.

Cada check nasceu de um incidente real num stack Next.js/React + Supabase + n8n: um deploy
que derrubou alertas em silêncio, um cron que falhou por semanas sem ninguém ver, uma view que
entregou dado de todos os clientes. O que está aqui é a parte que vale em qualquer projeto,
com como achar a ferramenta equivalente no repo auditado. Todo comando **localiza**; nenhum
aplica fix. Se a casa tem o comando exato do stack dela, ele está no guia de calibração (ver
"Calibração da casa" na `SKILL.md`).

## C1 — Injeção

Sem item aqui: os sete grupos estão em `c1-injecao.md`, e nenhum tem incidente registrado.

## C2 — Autenticação e autorização (13 itens · a categoria com mais incidentes)

### C2.1 Toda função serverless tem entrada explícita no manifesto, com a política de auth que ela de fato precisa?
- deploy que não acha declaração cai no **default da plataforma**, e o default costuma ser o oposto do que a função server-to-server precisa. Ache o manifesto (`supabase/config.toml`, `vercel.json`, `serverless.yml`, `wrangler.toml`, `*.tf`) e faça o diff entre "funções que existem no disco" e "funções declaradas".

### C2.2 Toda função com auth de gateway desligada valida o chamador internamente?
- desligar a verificação no gateway transforma o endpoint em público; a única defesa passa a ser o código. Enumere os endpoints com auth desligada no manifesto e exija, no corpo de cada um, uma prova de chamador: segredo compartilhado em header, HMAC do payload, ou validação de token.

### C2.3 Toda chamada server-to-server usa o helper de invocação interna, e não `fetch` montado à mão?
- quando existe um helper que carimba a credencial interna, `fetch` na mão é a forma de esquecê-la. Ache o helper (`grep -rl 'internalInvoke\|internal_client\|service_client'`) e liste quem monta a URL de função sem passar por ele.

### C2.4 A guarda de autorização reconhece o scheduler do banco como chamador legítimo?
- job agendado dentro do banco (pg_cron, Hangfire, cron do SO) roda **sem sessão de usuário**: guarda baseada em claim de JWT ou id de usuário fica permanentemente falsa. Antes de pôr guarda em qualquer função, pergunte quem mais a chama — e confirme que alguém observa a taxa de falha do scheduler.

### C2.5 Nenhuma chamada com credencial de serviço depende de função que lê a identidade do usuário?
- cliente admin/service não carrega o contexto do usuário: qualquer função que decida por "quem é o chamador" retorna vazio/false quando invocada assim. Validar o token não muda o contexto das chamadas seguintes. Liste as RPCs chamadas pelo caminho admin e verifique o corpo de cada uma.

### C2.6 Todo trigger que escreve em tabela com autorização restritiva roda com privilégio elevado?
- trigger roda com a permissão de quem disparou o DML. Se ele escreve numa tabela com regra restritiva, a operação **do usuário** quebra (não a do trigger). E confirme que a migration que corrige isso está **aplicada no ambiente**, não só no repo.

### C2.7 Toda troca de insert por upsert veio no mesmo PR com o privilégio e a regra de UPDATE?
- upsert é `INSERT … ON CONFLICT DO UPDATE`: o ramo de update exige **privilégio e regra próprios**. Vale em qualquer camada com autorização por linha (RLS, Firestore rules, Hasura permissions). Grep pelo verbo do seu client (`upsert`, `merge`, `save()` com pk) e cruze com a lista de regras por comando.

### C2.8 Antes de `CREATE OR REPLACE` numa função usada por autorização, alguém greppou todas as regras que a chamam?
- redefinir um predicado compartilhado por N regras é **ampliação silenciosa de acesso**: não gera erro, gera leitura a mais. Grep o nome em todo lugar que possa referenciá-lo, inclusive migrations arquivadas e testes, antes de mudar a semântica.

### C2.9 Toda policy que filtra por papel usa a função helper, e não um SELECT direto na tabela de perfis?
- regra sobre a tabela X que faz SELECT em X entra em **recursão infinita** e derruba a tabela inteira, não só a query. Use a função estável/elevada do projeto. Grep o padrão de subselect dentro das definições de policy.

### C2.10 As RPCs internas continuam negadas ao papel do browser depois da última migration que mexeu em GRANT?
- migration de "restaurar grants" costuma conceder mais do que devia, e privilégio default (`ALTER DEFAULT PRIVILEGES`) atinge o que ainda nem existe. Depois de qualquer mexida em GRANT, re-enumere o que o papel anônimo/autenticado consegue executar e compare com uma allowlist versionada.

### C2.11 Toda função com privilégio elevado fixa o `search_path`?
- função que roda como owner sem resolução de nomes fixada é vetor de escalação: quem controla o schema de busca controla qual `tabela` ou `função()` ela chama. O equivalente fora do Postgres é qualquer execução privilegiada herdando `PATH`/classpath do chamador.

### C2.12 A verificação de autorização que **não** roda no CI foi rodada à mão antes deste PR?
- todo repo tem um check que foi removido do CI por motivo de infra e virou disciplina. Ache: `grep -rn 'verify:\|check:' package.json` e compare com os steps do workflow — o que existe no `package.json` e não está no CI é o ponto cego.

### C2.13 A conta usada no teste tem realmente o privilégio que o teste supõe?
- antes de concluir "401/403 = bug de autorização", prove a identidade do lado que testou. Fixture com nome de admin não é admin, e a credencial do seu `.env` local pode não ser a que o runtime enxerga.

## C3 — Exposição de dado (7 itens)

### C3.1 Existe mais de uma policy PERMISSIVE do mesmo comando para o mesmo papel na mesma tabela?
- regras permissivas **se somam com OR**: a mais frouxa vence e torna a restritiva decorativa. Vale pra RLS, IAM e qualquer motor de policy aditivo. Agrupe as regras por (recurso, comando, papel) e olhe todo grupo com mais de uma.

### C3.2 Toda view que lê tabela protegida foi criada com o modo invoker?
- view no Postgres roda por default como **definer** e **bypassa a RLS da tabela base**; o equivalente noutros bancos é qualquer objeto derivado que herda o privilégio do criador. Enumere as views e confirme a opção explícita.

### C3.3 Acesso público a dado de negócio passa só por função controlada, nunca por regra de leitura para o papel anônimo?
- regra de SELECT para anônimo numa tabela de negócio é **enumeração** via a API REST automática: o cliente pede um id, o atacante pede a coleção. O padrão seguro é uma função que recebe o identificador e devolve só o registro.

### C3.4 Nenhuma variável do prefixo público carrega segredo de servidor?
- o prefixo que o bundler injeta no browser (`VITE_`, `NEXT_PUBLIC_`, `REACT_APP_`, `PUBLIC_`) é **publicação**, não configuração. Liste as usadas de fato no código (não as do `.env`) e confronte com a lista do que pode ser público. Depois confira o artefato buildado, não só a fonte. Ver Fase 1.

### C3.5 Nenhum endpoint de alerta ou webhook está hardcoded em arquivo versionado?
- canal de notificação sem autenticação (ntfy, webhook de Slack/Discord/Teams) é credencial disfarçada de URL: **quem sabe o nome lê e escreve**. Grep os hosts conhecidos em tudo que é versionado, incluindo export de automação e IaC.

### C3.6 O detector de segredo do CI cobre os formatos que **este** stack já vazou?
- detector caseiro só pega o que alguém escreveu nele. Liste os padrões que ele tem e compare com os prefixos que este stack realmente emite (provedor de nuvem, forja de código, LLM, JWT). Onde houver gitleaks, ele é a fonte de verdade — ver Fase 1; este check é sobre o script **extra** do repo.

### C3.7 A mudança de visibilidade mexeu nos dois lugares: a regra no banco **e** o filtro no client?
- quando existe defense-in-depth (regra no servidor + filtro no client), mexer num lado só produz dois bugs opostos: acesso negado a quem devia ver, ou dado no browser de quem não devia. A regra derivada: **filtro em JS nunca é o sigilo** — se o dado não pode chegar ao cliente, a regra do servidor tem que barrar.

## C4 — Validação no boundary de entrada

Sem item aqui: está em `c4-validacao.md`.

## C5 — Dependências (1 item · sem cicatriz de vulnerabilidade)

### C5.1 O CI roda algum audit de dependência?
- detecte o lockfile e rode o audit nativo: `bun.lock`→`bun audit`, `package-lock.json`→`npm audit`, `pnpm-lock.yaml`→`pnpm audit`, `poetry.lock`/`requirements.txt`→`pip-audit`, `Cargo.lock`→`cargo audit`, `go.sum`→`govulncheck`; universal: `osv-scanner scan .`. Depois pergunte se ele **roda no CI**: `grep -rn audit .github/workflows/`. Ver Fase 4 para a execução e para pacote alucinado.

## C6 — Configuração e processo (6 itens)

### C6.1 A URL de callback do provedor de auth bate com a URL real de produção?
- `site_url` e allow-list de redirect erradas quebram o handoff de sessão pós-OAuth e, com `http://` ou glob frouxo, abrem redirect aberto. Compare o **arquivo versionado** com o **estado do provedor**: é drift dos dois lados.

### C6.2 A rotação de um segredo compartilhado atualizou **todos** os consumidores dele?
- segredo compartilhado por N sistemas tem N lugares de atualizar, e o provedor costuma aceitar **um valor válido por vez**: rotacionar num lugar quebra os outros silenciosamente. Antes de fechar a rotação, enumere os consumidores — inclusive valores inline em automação, que nenhum gerenciador de segredo enxerga.

### C6.3 Alguém confirmou que o valor copiado do gerenciador de segredos é o segredo, e não o hash?
- vários gerenciadores listam **digest**, não valor. Copiar o que a listagem mostra produz um `Unauthorized` que parece bug de auth e queima horas. Regra: a listagem serve só para confirmar **existência**; para diagnosticar sem expor valor, compare hashes.

### C6.4 O "dry-run" da migration realmente não aplicou nada em produção?
- envolver um script numa transação externa só é dry-run se o script **não commitar sozinho**. Antes de confiar, grep por transação dentro do arquivo — vale pro `.sql` e pro equivalente do seu migrador (`atomic=False` do Django, `disable_ddl_transaction!` do Rails). E confirme que o que foi aplicado fora do fluxo normal ficou **registrado** na tabela de versões, senão o próximo push tenta de novo.

### C6.5 O CI é gate de verdade, ou vermelho passa?
- separe "o check roda" de "o check bloqueia". Dois lugares: proteção de branch no servidor (`gh api repos/<owner>/<repo>/branches/main/protection`; 403 = não existe) e `grep -rn 'continue-on-error' .github/workflows/` — step com essa flag é informativo, não gate. Um SAST assim não segura nada.

### C6.6 A permissão base da organização continua `none`?
- quem consegue **ler** o repo é parte da superfície de exposição de segredo. Permissão em forja de código é **aditiva**: criar time restrito não isola ninguém se a base já concede. Cheque a base da org, os colaboradores diretos do repo mais sensível e quais repos são públicos.

## C7 — Armazenamento e segredos em repouso

Sem item aqui: está em `c7-cripto-armazenamento.md`.
