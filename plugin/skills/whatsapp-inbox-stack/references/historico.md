# whatsapp-inbox-stack — importar o histórico do celular (#28)

Lido no passo 3 do SKILL.md, antes de importar mensagens anteriores à conexão do número.

### #28 — Importar o histórico sem acionar nada
Pedido real: "não puxa o histórico do WhatsApp anterior à conexão". Gravar uma mensagem pelo caminho normal mexe em tudo: soma não lidas, desarquiva, muda prévia e ordem da caixa, dispara sino, IA, automação, outbox, SLA e métricas. **A importação NÃO passa pelo pipeline de inbound.**

**Desenho**
- **Marca de importada:** coluna `messages.imported_at timestamptz NULL` (nulo = viva). Coluna, não `metadata`, porque gatilhos e métricas filtram por ela de forma indexável.
- **Gatilhos de banco** que atualizam atividade da conversa e analytics por hora retornam cedo com `NEW.imported_at IS NOT NULL`. SLA, funil e contadores da memória da IA ganham `AND imported_at IS NULL`.
- **Entrada própria:** `INSERT ... ON CONFLICT DO NOTHING` no único `(organization_id, provider, phone_id, provider_message_id)`. Repetir não duplica, e mensagem que chegou ao vivo é ignorada. `occurred_at` = timestamp original. Direção por `fromMe`. **Não toca na linha da conversa** (não lidas, arquivo, prévia, ordem). Ignora reação, protocolo, chamada e status.

**Fonte UAZAPI:** `POST /message/history-sync` com **`sync: true`** + `timeoutMs` (≤25 s) devolve as mensagens na própria resposta (`status`, `has_more`, `next_request`, `history_access`).
- Reenvie `next_request` até `null`. Pare em `has_more:false`, `blocked` (`pagination_no_progress`, `anchor_unavailable`, `history_access_unavailable`), `timeout`, data de corte ou teto de páginas.
- `pending` (202) quer dizer que o celular demorou: leia depois por `POST /message/find`.
- Um pedido por vez por conversa, uma conversa por vez no número (servidor compartilhado), com pausa entre páginas.
- Isso **dispensa** assinar o evento `history` no webhook de produção e mexer no n8n.

**Limites reais**
- O WhatsApp entrega o que o **celular** tem e quer entregar (online, app aberto ou em segundo plano). Alguns aparelhos param cedo em `blocked`. A tela mostra o resultado honesto ("X mensagens até DD/MM; o celular não entregou mais").
- Teto = janela da retenção: importar além dela é apagado na rodada seguinte.
- Mídia antiga: baixar na hora ou só rótulo, porque a UAZAPI guarda ~7 dias (#5).

**Memória/IA:** as importadas ficam mais antigas que o cursor incremental da memória, então ela nunca as vê. Precisa de "reconstruir do zero", em janelas, respeitando a edição manual.

**Gravação em produção**
- Antes, confira por leitura se há webhook de banco, `pg_cron` ou fluxo n8n observando a tabela.
- Uma transação por conversa: foto antes (não lidas, arquivo, prévia, datas, contagens de notificações/outbox/jobs/automações/IA/analytics), só INSERT, foto depois, e **ROLLBACK se qualquer número mudou**.
- Ordem: ensaio, 1 conversa, conferência na tela, o resto. Desfazer: apagar o lote marcado.

**Extrator de outro provider** (migrando de outra ferramenta): trave no código para só GET, só o host dela, lista fechada de rotas, nenhuma credencial do sistema novo no processo.
