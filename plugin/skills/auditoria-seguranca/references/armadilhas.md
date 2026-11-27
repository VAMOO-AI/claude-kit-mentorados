# auditoria-seguranca — Armadilhas

Lido antes de entregar o PDF, como conferência final.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| Auditoria "limpa" em projeto que nunca foi auditado | Amostrou handlers em vez de percorrer. Conte e publique a razão lidos/total |
| Achado de A1 que o time rebate em 5 minutos | O projeto usa middleware de tenant e você leu a query sem ler o middleware |
| Categoria some do relatório | Stack sem frontend/sem multi-tenant. Isso é "não aplicável **escrito**", nunca seção ausente |
| PDF com número diferente do texto | Alguém editou a tabela à mão. Os números saem só do `findings.json` |
| Issue devolvida como "não reproduz" | Faltou a condição de explorabilidade (flag, config, papel necessário) |
| Segredo "já rotacionado" reaparece | Rotação não reescreve histórico: sem `gitleaks` no histórico você não sabe o que ainda está lá |
| Relatório todo `corroborado` com confiança alta | Autodeclaração: o modelo chamou a própria leitura de segunda fonte. Corroborado exige fonte externa nomeada em `fonte` |
| Veredito `LIBERADO` num projeto com achado crítico | O crítico está com `status` não acionável. Confira se o `risco_aceito` foi decisão de alguém ou preguiça de confirmar |
| Auditoria "limpa" numa categoria inteira | A ferramenta daquela superfície não rodou. Ela tem que estar em `ferramentas[]` com `nao_instalado`, e o aviso sai no PDF |
| O PDF entregue contém a chave que o relatório denuncia | `redacao: false` usado em segredo vivo. A escotilha é só para default público já versionado |
| Relatório cheio de `baixa` que ninguém vai corrigir | Desvio de checklist virou achado para não perder a nota. Sem fronteira cruzada é `hardening[]` |
| Achado que o dono responde "o nginx já trata isso" | Você adivinhou o deploy. Era `a_validar` com o `bloqueio` "config do proxy não está no repo" e o plano do dono |
| Segunda auditoria repete o falso positivo da primeira | O `falso_positivo` foi apagado do JSON em vez de ficar com `motivo`. Ele é memória, não lixo |
| `alta` que o juiz derruba em dois minutos | Você leu a query sem ler o caller. O revisor fresco é para isso — rode-o antes do PDF, não depois da reunião |
| `--verificar` recusa um trecho que "está igual" | Está reescrito: aspas, espaço, nome de variável. Copie do arquivo com `sed -n 'a,bp'` e cole; achado de segredo sai pelo bloco mascarado da Fase 6, nunca pelo `sed -n` cru |
| Auditoria de agente de IA "limpa" | Você auditou o prompt. A6 é o handler da tool: com que identidade roda e o que re-checa |
| Juiz refutou com "o framework já trata" e o achado volta em produção | Refutação sem `arquivo:linha` do controle, ou com o controle num caminho só. Descartar pede a mesma prova que confirmar |
| `alta` virou `falso_positivo` quando o juiz só achou a nota exagerada | Discordar da severidade não apaga o achado: rebaixe, com a condição de `muda_severidade_se` que se confirmou |
| Lint `0015` limpo e a conta nasce admin no cadastro | O lint só lê policy. A trigger de signup copia `raw_user_meta_data` para a coluna de papel |
| A1 "isolamento por dono" medido e um estranho entra como funcionário | Você mediu dono contra dono e não perguntou quem vira dono: signup aberto no painel + predicado `autenticado = membro` (`quem-entra.py`) |
| Grep de `user_metadata` limpo e o trigger em `.sql` copia o papel | O grep era só de `*.ts`, e `user_metadata` não casa `raw_user_meta_data`. Use `user_meta_?data` e leia as migrations |
| Achado citado na migration baseline e o time mostra que já trocou | Você leu a primeira definição. Vale a última (`quem-entra.py` lê o efetivo) e, com banco, `pg_policies` |
| HMAC listado como ponto forte e o pentest faz replay | Comparação em tempo constante não é janela. Sem timestamp e nonce na assinatura, ela vale para sempre |
| Escrita negada "passou" no script de carga | O PostgREST responde 204 quando a RLS filtra todas as linhas. Conte (`count=exact`) ou peça a linha de volta |
| `REVOKE UPDATE (is_admin)` na migration e o usuário ainda grava a coluna | Revogar por coluna não anula o `GRANT` da tabela inteira. Confira `has_column_privilege`, não a migration |
| "Migramos para as chaves novas" e a service_role que vazou ainda funciona | Chave nova não desativa a legada. Sem o painel, é `a_validar` com o plano do dono |
| "Revogada, deu 401" | 401 tem outras causas. Estado de chave é fato do painel: `a_validar` |
| Bundle limpo e a senha de admin aparece no `.map` | O `sourcesContent` traz o fonte original, inclusive o que o tree-shaking tirou do `.js`, e a busca 4 só acha token de formato conhecido. Rode o bloco do `.map` da A4 |
| Tool MCP liberada sem aprovação porque "é só leitura" | A hint é declaração de quem escreveu a tool, não autorização |
| Agente aprovado para "enviar e-mail" manda o histórico para fora | Aprovação presa ao nome da tool, não aos argumentos, e destino sem allowlist |
| A3 "34/34 handlers" e o pentest acha função de escrita sem dono | O denominador contou rotas. Função em `public` é rota `/rest/v1/rpc/<nome>`, e o gateway `rpc(nome)` esconde centenas de ações. Some as três |
| Vertical limpo (ninguém vira admin) e o colega toma o registro | Faltou o eixo horizontal: mesmo papel, registro de outra pessoa, medido por ação de escrita. Compare a família (`familias-rpc.py`) |
| Editar, mover e descartar conferem o dono, e a auditoria passa | Leu as irmãs certas e não a que muda o dono. Transferir, atribuir e assumir são a chave das outras ações |
| Conta de teste não achou nada horizontal | A conta era admin ou dona de tudo. Use o ator C: papel de escrita, escopo vazio |
| `auth.uid()` na função e o dono não é conferido | Está no `SET` (`atualizado_por = auth.uid()`). Carimbar quem fez não é checar quem pode |
| Salvar confere dono no update e cria registro em cliente alheio | O ramo de criação do upsert não tem linha para conferir. Cheque o vínculo antes do `insert` |
| Endpoint genérico "nega" e mesmo assim entrega o schema | Valida tabela e coluna antes do papel. Cada mensagem distinta é um bit do oráculo |
| Front esconde escrita que o servidor aceita | Dois endpoints de identidade com fontes diferentes. Liste todos e compare a fonte |
| "Somente leitura" e o relatório não diz o que ele lê | Leitor sem partição lê a base inteira, inclusive quem é admin. Escreva o escopo de leitura de cada papel restrito |
| `SameSite=lax` listado como proteção de CSRF com apps irmãos no domínio | Subdomínio irmão é o mesmo site. Sem `__Host-` e com sessão aceita no outro host, o subdomínio fraco planta ou lê a sessão |
| Relatório pede limpeza que ninguém consegue fazer | Escreveu em produção para provar. Desfazer exigia ser dono e o `atualizado_por` não volta. Escrita é no Supabase local |
