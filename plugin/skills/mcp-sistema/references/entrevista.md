# Entrevista — fecha as decisões antes do código

Uma pergunta por vez, sempre com a recomendação primeiro. Pergunta cuja resposta
está no código (nome da tabela de usuários, papéis existentes, domínio de prod)
você responde lendo o repo, não perguntando. No fim, a tabela abaixo vai para a
spec preenchida.

## Perguntas (nesta ordem)

1. **Quem usa e o que cada nível enxerga?** Liste os papéis que existem no app e,
   para cada um, o recorte. Recomendação: o mesmo recorte que a pessoa tem no app;
   o MCP nunca vê mais que a tela.
   - Exemplo real: vendedor → só o próprio; gerente → o time; diretoria → tudo;
     suporte → operação sem valores por vendedor.
2. **De onde vem o papel?** Se o app junta várias fontes (tabela de usuários,
   tabela de negócio, env), escolha UMA para o MCP. Recomendação: a tabela de
   usuários do app (`app_users` ou equivalente), com `is_active`. Desativar lá
   corta o agente na próxima chamada.
3. **Como a pessoa se liga ao registro de negócio** (vendedor, colaborador,
   cliente)? Recomendação: por `auth_user_id`. Nome não serve.
4. **Quem libera o acesso?** Recomendação: coluna booleana por pessoa
   (`mcp_enabled`, default `false`) com chave na tela de Usuários, só admin muda.
5. **Hierarquia muda no tempo?** (troca de time, promoção). Se sim, o recorte de um
   período passado usa a hierarquia daquele período.
6. **Dados da v1.** Liste os domínios (ex.: faturamento e metas, operação,
   reuniões). Recomendação: 3 domínios no máximo; o resto vira v2. Para cada um,
   aponte a lib que o app já usa — a tool chama a MESMA lib, não reimplementa o
   cálculo (senão o número do agente diverge da tela).
7. **Escritas.** Quais alterações o agente pode fazer e quem pode. Recomendação:
   só gestão (gerente/admin), exceto o que é da própria pessoa (ex.: concluir a
   própria tarefa). Toda escrita = prévia → confirmação → log.
8. **Endpoint e nome.** Recomendação: dentro do próprio app,
   `https://<dominio-de-prod>/api/mcp`, nome curto do sistema em minúsculas.
   Confira que o domínio de prod é o `site_url` do Supabase Auth.
9. **MFA.** O app exige? O consentimento fica atrás do mesmo gate (sessão + MFA).
10. **Página.** Recomendação: página "MCP" na área de gestão com endpoint, guia de
    instalação em 4 passos, prompts úteis por papel e dúvidas frequentes, no
    design system do app.
11. **Clientes na instalação guiada.** Recomendação: Claude (app/web), Claude
    Code, ChatGPT, Outro cliente.

## Tabela de decisões (vai para a spec)

| Tema | Decisão |
|---|---|
| Hierarquia | |
| Autenticação | OAuth 2.1 pelo navegador — OAuth Server do Supabase Auth + DCR + página de consentimento no app |
| Fonte do papel | |
| Vínculo pessoa ↔ negócio | `auth_user_id` |
| Acesso | coluna `mcp_enabled` (default false) + chave em Usuários |
| Dados v1 | |
| Escritas | |
| Proteção de escrita | prévia → token de confirmação → gravação → log |
| Endpoint | |
| Página | |
| Clientes na instalação | |

## Escopo por papel (vai para a spec)

| Papel | Registros visíveis | Valores por pessoa | Escrita de gestão |
|---|---|---|---|
| | | | |

Mais uma linha: "agregados que vazam dado alheio" — o que cada papel vê em
ranking, top N e previsões.
