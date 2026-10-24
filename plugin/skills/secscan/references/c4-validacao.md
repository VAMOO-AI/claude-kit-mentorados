# C4 — Validação de entrada: o que caçar

> Referência da skill `secscan`, Fase 2.5. Leia ao avaliar C4.

Achados a caçar:

- **Boundary sem schema**: dado externo entra por route handler, server action, function
  serverless, webhook, form action, consumidor de fila e função do banco exposta ao papel
  anônimo. Enumere pelos caminhos, filtre os que leem entrada crua (`req.json()`,
  `request.body`, `new URL(req.url)`, `formData()`) e **imprima a diferença** contra os que
  importam o validador: inventário não é check, o gap é. Rode o comando e cole a saída;
  número desta skill é calibração de outro repo, nunca resposta.
- **Server action e form action**: `grep -rln "'use server'" src app` (vazio num repo Vite:
  responda "não aplicável", não omita). Validação de form é UX, não autorização: ela
  denuncia o contrato que precisa existir do outro lado (CHECK constraint ou schema no
  servidor). Os dois lados vazios = ninguém valida.
- **Fila é boundary duas vezes**: linha enfileirada por quem validou continua entrada não
  validada no consumidor, que costuma rodar com `service_role` e sem RLS. Valide na leitura
  da fila, não só na escrita.
- **Webhook de automação**: schema é aqui, auth/segredo é o bloco de webhooks da Fase 3.
  **Descubra o diretório dos fluxos, não presuma `n8n/`**: glob fixo em pasta inexistente
  devolve "no matches" e a categoria sai "não aplicável" em cima de dezenas de fluxos.
- **Valor que decide dinheiro, permissão ou identidade é recalculado no servidor**, nunca
  aceito do cliente: preço, total, desconto, quantidade, status, `role`, `user_id`,
  `owner_id`, tenant. Schema não salva: `p_total = 1` passa em qualquer validação de tipo.
  Estático: `grep -rn 'GRANT EXECUTE ON FUNCTION .* TO anon' supabase/migrations/*.sql` e
  leia a assinatura de cada uma na migration que a criou.
- **Policy permissiva sem constraint compensando**: a detecção de `using (true)` é da
  Fase 2. Aqui é a contrapartida: policy frouxa consciente deixa como única defesa a
  constraint de domínio na tabela, e ela precisa existir. **Teste do silêncio**: `count(*)` e
  `max(created_at)` da tabela que recebe escrita anônima. Zero linhas não é "não chegou
  lead", é boundary quebrado que ninguém viu.
- **Comparação de identidade sem normalização** é falha de autorização disfarçada de bug
  de matching: lados normalizados por regras diferentes ou não casam (nega acesso
  legítimo) ou casam demais (entrega dado ao dono errado). Normalize uma vez, num helper
  testado, e compare só a forma canônica: telefone, e-mail (caixa, `+tag`, unicode), host,
  path, slug.
- **Limite de entrada ausente = DoS**: tamanho do body, profundidade do JSON, quantidade de
  itens de array, tamanho e tipo de upload. A falta de qualquer um é finding.
- **Mass assignment**: objeto do request repassado inteiro para insert/update sem lista de
  campos permitidos; o atacante manda `role`, `owner_id`, `is_admin` junto e o ORM grava.
  Lista explícita no boundary, nunca spread do body. **Comece pelas functions do servidor**:
  no navegador a RLS ainda barra coluna de outro tenant; com `service_role`, nada barra.
- **Confusão de tipo**: query string entrega string, multipart entrega string **ou array**,
  JSON entrega o que o cliente quiser. `Number("abc")` vira NaN calado, `"9" > "10"` é
  `true`, `?id=1&id=2` vira `["1","2"]`, e `"false"`/`"0"` são truthy. Schema com
  **coerção explícita** resolve os três; `typeof` na mão não. O grep acha a coerção, não a
  falta de guarda de NaN: esse passo é leitura, e o finding diz que foi leitura.
