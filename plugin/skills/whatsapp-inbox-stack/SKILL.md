---
name: whatsapp-inbox-stack
description: >-
  Inbox/chat de WhatsApp sobre n8n + Supabase ou API própria (página própria ou
  Chatwoot, via NotificaMe ou UAZAPI). Use ao construir ou debugar a ponta do
  inbox: mídia que não chega ou não toca, IA e humano no mesmo fio, sessão que
  cai, entrega sem confirmação, não lidas, histórico, relatório de quem falou
  com o lead. O workflow n8n em si é da n8n-workflow-agent.
---

# WhatsApp Inbox Stack

Padrão pra montar um inbox de WhatsApp COMPLETO (mídia inclusa). Nasceu de produção: **cada gotcha corrigiu um bug real**. Este arquivo é o roteador; o detalhe e o código copia-e-cola vivem em `references/` (`media-pipeline.md` tem o código de mídia).

O WORKFLOW n8n em si (Code Node, API, layout, outbound) é da **`/kit-vamoo:n8n-workflow-agent`**. Esta skill foca na ponta inbox: schema, render, storage, edge e os gotchas que ninguém vê até quebrar em prod.

**Depois de uma compactação só o começo desta skill volta:** releia a `references/` do passo que a cita.

## Regras duras (cada uma corrigiu um bug real)

- **NotificaMe: todo áudio opus = fast path + background, sem exceção por tamanho.** NUNCA transcodificar antes do upload/resposta: 1min de voz cabe em ~120KB e ainda OOMa no sync (#9). UAZAPI não transcoda (#5).
- Edge: importe via `npm:ogg-opus-decoder@x`, **NÃO** `https://esm.sh/...` (o deploy passa, o runtime quebra; #2). Use `decoder.decodeFile(opus)`, não `decode()` sem `flush()` (áudio corta no final; #8).
- `supabase functions deploy` **religa verify_jwt=ON**: funções públicas com `--no-verify-jwt` no CI ou `verify_jwt=false` no `config.toml`, nunca o toggle do dashboard (#3).
- NotificaMe: NÃO baixe a `fileUrl` lookaside direta (401, expira em ~2min); baixe pelo proxy `/media` na hora do webhook. UAZAPI: `.enc` é criptografada, resolva por `/message/download` com `return_link:true` (#5).
- Bucket **privado**, `media_url` guarda o PATH, o front assina no read. Depois do UPDATE, o servidor publica broadcast só com ids e a tela relê; `postgres_changes` custa polling do WAL mesmo sem ninguém olhando (#6). Skip guard: `if(!phone||(!text&&!mediaUrl)) skip` (#7).
- CSP: `media-src 'self' data: https: blob:` no header E no meta. Foto OK ≠ áudio OK; `fetch 200` não prova que o `<audio>` toca (#1).
- `POST /webhook` do UAZAPI: sempre **read-then-write** com `action:"update"` + `id`; o modo simples substitui e derruba `messages`. Early-return pelo EVENTO, não pelo status reconhecido. `isGroupYes` no `excludeMessages` só sem grupo (#11).
- `messages_update` da UAZAPI: ids em `event.MessageIDs[]` com prefixo `numero:`, estado em `event.Type`. Depois de ligar, `group by status` tem que mostrar `delivered` (#21).
- Tire `token` do payload da UAZAPI antes de gravar o cru: autoriza envio pelo número (#23).
- **Nunca `/instance/disconnect` como conserto**: apaga as credenciais e força QR novo. Saúde da sessão: **a prova é o inbound**, nunca o outbound (#11).
- **Não zere em bloco** os avisos órfãos: cheque o dono ATUAL antes de reenviar (#12).
- Remetente de alerta marcado é o único remetente: fora do ar, o alerta não sai. Fallback para outro número manda mensagem pelo WhatsApp de alguém (#29).
- **Propriedade de canal decide quem RESPONDE, nunca quem GRAVA.** Ordem: gravar inbound → resolver dono → decidir envio; handoff é `UPDATE` explícito, sem TTL (#13).
- `sender.name`/`agent_name` é a conta do token, não a pessoa: quem falou sai do `inbox_id`. **`user` conta**; nota interna (`private: true`) não é contato (#14).
- **Broadcast é canal aberto** (sem RLS, chave no bundle): payload só com ids, quem recebe valida uuid e busca no banco; mesmo nome de canal nas duas pontas, um canal por topic no cliente (#15).
- **Nada de `router.refresh()` por aviso:** lista e painel releem só o citado por GET, com coalescência e sem eco da própria aba (#16).
- **Aviso incremental exige que toda mutação avise** (leitura, atribuição, resolução, as da app e as do provider): liste todas antes de tirar o refresh (#17).
- **Não reassine mídia que a tela já mostra:** URL assinada nova é download novo; troque só se o arquivo mudou, venceu com o player parado ou falhou (#18).

## Fluxo

### 1. Três arquiteturas (decida primeiro)

| | **A — Chatwoot É o inbox** | **B — página própria + Supabase** | **C — API própria como cérebro** |
|---|---|---|---|
| Mídia | **nativa** | **você faz tudo**: baixar, transcodar, storage, assinar | a API resolve (o token do provider vive nela) |
| Quando | já usa Chatwoot, sem UI custom | React/Next próprio, embutido no seu app | backend próprio (ex.: Go); n8n só como adaptador fino do webhook |

**A:** quase nada daqui se aplica (o Chatwoot resolve a mídia; ver `n8n-workflow-agent/references/chatwoot.md`). **B:** leia tudo. **C:** os gotchas de edge (#2, #3, #9) não se aplicam; valem #21 a #29 e o adaptador, que traduz o payload do provider (#26).

### 2. Pipeline de mídia inbound (arquitetura B)

**Leia [references/gotchas-midia.md](references/gotchas-midia.md)** antes de mexer em normalização, edge de ingestão, transcode, bucket ou CSP.

**NotificaMe/Meta:** o diagrama abaixo inteiro (proxy `/media`, transcode na edge, #2/#5/#8/#9). **UAZAPI:** resolver `.enc` por `/message/download` → re-hospedar no bucket → assinar no read; #2, #8 e #9 não se aplicam.

```
Provider webhook (NotificaMe/UAZAPI)
  → n8n: Normaliza (NÃO derrube mídia sem legenda! ver gotcha #7)
  → n8n: Brain Query → INSERT <agente>_messages (content_type, media_url=path|null)
  → n8n: IF mídia? → Ingerir Mídia (HTTP → edge function; timeout 300s; passa inbound_id)
        → edge: baixa o binário (proxy, NÃO a lookaside direta — gotcha #5)
        → edge: upload do ORIGINAL pro bucket PRIVADO → devolve o PATH (rápido — gotcha #9)
        → edge (background waitUntil): áudio ogg/opus → MP3 + Whisper + PATCH media_url (gotcha #2, #9)
  → n8n: UPDATE media_url = path (path pode ser .ogg no 1º beat; .mp3 depois, avisado por broadcast só de ids, gotcha #6)
  → front: listMessages ASSINA o path no read (signed URL) → <audio>/<img>
```

Modelo da mensagem: `content_type` (text|audio|image|document|sticker|template|…) + `media_url` (PATH do bucket privado) + `content` (legenda/texto). O front assina o path no read; `http*` ou null passam direto.

Gotchas de mídia (títulos completos na reference):
- #1 — CSP `media-src` ("áudio não toca, mas foto sim")
- #2 — Transcode opus→mp3 na edge: `npm:` NUNCA `esm.sh`
- #3 — `verify_jwt` reseta pra ON a cada deploy
- #4 — Voz = Ogg/Opus; foto jpg; sticker webp animado
- #5 — Mídia inbound: NotificaMe (não baixe a `fileUrl` direta) e UAZAPI (`.enc` criptografada)
- #6 — Bucket privado: assinar on-read + RLS + broadcast do servidor
- #7 — n8n: skip guard derruba mídia sem legenda
- #8 — Áudio corta no final: `decodeFile`, não `decode`
- #9 — Áudio longo (~1min+): OOM se transcodificar no caminho crítico

Código verificado (edge, signing, render, CSP, bucket SQL, backfill, probes): `references/media-pipeline.md`.

### 3. Sessão, entrega e retentativa

**Leia [references/sessao-e-entrega.md](references/sessao-e-entrega.md)** antes de mexer em status de sessão, webhook do provider ou retentativa de aviso:
- #10 — Inbox "vazio" é thread picada, não bug de fetch (Chatwoot)
- #11 — Ninguém sabe que a sessão caiu, e "enviado" não é "entregue" (inclui o runbook "ligar a assinatura sem derrubar a ingestão" e os 14 dias do celular principal)
- #21 — O `messages_update` real não tem `message`: o ACK fica preso em "aceito"
- #22 — Envio para grupo fica em "Enviando" (`GroupReceipts`)
- #23 — O token da instância vem dentro do webhook
- #12 — Queda longa estoura o teto de retentativa, e os avisos NÃO voltam sozinhos

**[references/contagem-e-eco.md](references/contagem-e-eco.md)** antes de mexer em não lidas ou no eco `fromMe` (UAZAPI):
- #24 — Não lidas que não acompanham o celular
- #25 — Eco do celular vs. envio pela API: corridas que duplicam ou reenviam

**[references/inbound-uazapi.md](references/inbound-uazapi.md)** antes de mexer no adaptador do webhook:
- #26 — `@lid` não é telefone
- #27 — A UAZAPI não reenvia webhook: responda 200 antes e retente você

**[references/historico.md](references/historico.md)** antes de importar o histórico do celular:
- #28 — Importar o histórico sem acionar nada

### 4. IA e humano no mesmo fio, prova de contato

**Leia [references/canal-e-auditoria.md](references/canal-e-auditoria.md)** antes de mexer em pausa/handoff ou em relatório de quem falou com o lead:
- #13 — Propriedade de canal: quem responde não é quem grava
- #14 — O webhook de CONTA é a prova de contato; o `agent_name` não diz quem falou
- #29 — O alerta não cai para outro número

### 5. Pré-flight "áudio toca" (a definição de PRONTO)

**Leia [references/preflight-audio.md](references/preflight-audio.md)** antes de declarar a mídia inbound pronta. O item **6** (toca no Chrome E no Safari) é de uma pessoa, via `hitl-loop.sh`: sem a resposta, "pronto" não sai.

### 6. Providers, reação e nota interna

**Leia [references/providers.md](references/providers.md)** antes de escolher provider ou Cloud API, editar mensagem, mexer em participantes de grupo, provisionar número, mandar áudio de saída (NotificaMe `/v1` com `type:'file'`; o `/v2` com `voice:true` não tem fonte) ou renderizar reação/nota interna:
- #20 — Chatwoot até a v4.14 manda áudio ogg/opus como `audio/opus`, e a Meta recusa (`131053`): áudio de saída em mp3

### 7. Tela que se move sem refazer a página

**Leia [references/tela-viva.md](references/tela-viva.md)** antes de mexer em Realtime, aviso, lista ou URL assinada de mídia:
- #15 — Broadcast do Realtime é canal aberto
- #16 — `router.refresh()` por aviso é o custo dominante
- #17 — Aviso incremental só funciona se toda mudança avisar
- #18 — URL assinada nova é arquivo novo para o navegador
- #19 — Nada lento no caminho da abertura

A reference fecha com o "como medir": A/B intercalado entre URLs de deploy e dois navegadores parados comparados com o banco.
