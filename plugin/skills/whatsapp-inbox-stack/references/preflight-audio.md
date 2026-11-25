# whatsapp-inbox-stack — pré-flight "áudio toca" (a definição de PRONTO)

Lido no passo 5 do SKILL.md, antes de declarar a mídia inbound pronta. Teste o caminho real.

1. [ ] Áudio **>1 min** inbound: `media_url` **NÃO fica NULL** em até ~15s (pode ser `.ogg` no 1º beat; `.mp3` depois via background). n8n `Ingerir Mídia` **sem** "compute resources". (NotificaMe. Na UAZAPI não há transcode: o `/message/download` já devolve mp3, #5.)
1a. [ ] Áudio curto: bucket grava `.mp3` (audio/mpeg). Áudio longo: `.ogg` imediato + `.mp3` em background.
1b. [ ] **Duração do mp3 == duração do áudio enviado** (gotcha #8 — manda 7s, confere ~7s, não 6s). `afinfo` no objeto do bucket.
2. [ ] `media_url` no banco = path do bucket (não lookaside http, não `.enc`, não null).
3. [ ] Signed URL serve `200 audio/mpeg` + `Accept-Ranges: bytes` (Range → 206; `<audio>` HTML5 exige).
4. [ ] **CSP tem `media-src`** liberando o domínio do storage (header + meta).
5. [ ] `verify_jwt` OFF pra edge de ingestão (probe = 401 de função, não gateway).
6. [ ] Toca de verdade no navegador, **Chrome E Safari**, após hard refresh. Console sem "violates CSP".
7. [ ] Áudios antigos quebrados: backfill (re-transcode local + UPDATE media_url) OU aceite irrecuperáveis (lookaside expirada; na UAZAPI, mídia com mais de ~7 dias).

Os itens 1–5 e 7 o agente fecha sozinho. O **6 não**: quem ouve é uma pessoa, nos dois navegadores. Não peça isso em prosa no meio da resposta — escreva um roteiro e rode `bash "${CLAUDE_PLUGIN_ROOT}/scripts/hitl-loop.sh" <roteiro>` (receita na skill `verificacao`), que devolve `TOCOU=s|n` e o erro do console em `KEY=VALUE`. Enter vazio reprova: sem a resposta, o item 6 fica em aberto e "pronto" não sai.
