---
name: verificacao
description: >-
  Casos de verificação end-to-end aprendidos em produção: testar TODOS
  os ramos de um fluxo, rodar TODOS os runners, pegar o erro REAL de prod antes
  do repro, inspecionar UI visualmente. Use antes de declarar "pronto" em fix
  com ramos, mudança que toca UI, erro de prod mascarado, ou teste em pasta com
  múltiplos runners, ou ANTES de qualquer disparo que sai da máquina e chega
  numa pessoa (mensagem, e-mail, cobrança, webhook de terceiro). Complementa a
  skill built-in `verify`. Gatilhos: "pronto", "verificar", "testar antes de
  entregar", "erro de prod / digest", "dry-run", "pode disparar?".
---

> Derivada de `claude-config-team/skills/vamoo-verificacao`. Ao divergir de propósito, diga aqui o quê e por quê.

# Verificação e2e — casos de produção

Os **princípios** ("verify don't claim", tsc+eslint antes de pronto, caminho
real do usuário) vivem no CLAUDE.md e valem sempre. Esta skill guarda os
war-stories e checklists por categoria.

## Fix em fluxo com ramos → teste TODOS os ramos

Mexeu em nó/módulo/função **compartilhado** por N ramos (IF/Switch, texto vs
áudio, N webhooks/tipos de evento, feliz vs erro) → exercite os N antes de
"pronto". O que conserta um ramo pode quebrar o irmão. Verificar só um caminho
e declarar pronto já mascarou regressão (fix de áudio num workflow n8n que quebrou o
ramo de texto, 2026-06-17).

## Múltiplos runners → rode TODOS

Um mesmo arquivo de teste pode ser coletado por mais de um runner (vitest
globando `supabase/functions/**` além do deno; jest+vitest). Adicionou teste
numa pasta coberta por N runners → registre nas listas include/exclude de cada
um E rode os N. Validar só um runner mascarou regressão (teste deno coletado
pelo vitest quebrou a suíte, 2026-06-29).

## Erro de prod mascarado → pegue o erro REAL primeiro

Digest / "Server Components render" / Sentry / 500-503 genérico: pegue o erro
REAL primeiro — logs/Observability do Vercel pelo digest, Sentry, ou peça pro
usuário colar — ANTES de montar repro local. Repro que não exercita o caminho
real engana: passa verde e some o bug (ex: render em vitest/jsdom NÃO tem
fronteira RSC, então erro server→client de Next "passa"). O erro real aponta
arquivo:linha na hora; horas de eliminação não.

## Mudança que toca UI → inspeção visual

Rode o app e inspecione visualmente (skill `run`/`verify`/screenshot) antes de
"pronto", incluindo estados interativos (clique, hover, loading, empty) —
static check não pega blur, layout quebrado nem botão morto. Isso é bug de
entrega, não polimento.

## Pipe não mascara falha

Nunca pipe `tsc`/`eslint` pra `head`/`tail` sem `set -o pipefail` (ou checar
`${PIPESTATUS[0]}`) — o exit code é o do pipe, não do checker, e mascara falha
como falso verde.

## CI vermelho → leia o erro literal antes de formular hipótese

Diagnóstico de CI é onde mais se inventa causa plausível e errada. A ordem que
funciona:

1. **Pegue a mensagem literal.** `gh run view <id> --log-failed` (o
   `sed -e 's/\x1b\[[0-9;]*m//g'` limpa os códigos de cor). Se você já rerodou
   e passou, o `--log-failed` volta vazio — baixe a tentativa 1 com
   `gh api "repos/<owner>/<repo>/actions/runs/<id>/attempts/1/logs"`.
2. **Só então** olhe o diff e a arquitetura.

Num caso real (2026-08-11) a hipótese de pé era estado compartilhado entre
testes. Errada: o erro literal era `duplicate key value violates unique
constraint` — o seed gerava sufixo aleatório num espaço pequeno demais, e a
colisão aparecia em menos de 1% das execuções. Uma linha de log encerrou o que
horas de teoria de arquitetura não encerravam.

Antes de chamar um teste de **instável**, exija as três coisas juntas: o arquivo
não está no seu diff, ele passa localmente **e** o rerun fecha verde. Duas não
bastam. E quando for instável mesmo, **corrija a causa** e escreva um teste
determinístico que provaria o bug antigo — rode-o contra o código anterior pra
confirmar que ele falharia. Teste novo que passa nos dois lados não prova nada.

## Efeito colateral externo → simulado, dry-run, e só então o real

Vale para tudo que sai da sua máquina e chega numa pessoa: mensagem de
WhatsApp, e-mail, cobrança, webhook em sistema de terceiro, post. Aqui "rodei e
passou" e "mandei mensagem errada pra 200 pessoas" são separados por um degrau
só, e ele quase nunca é escrito:

1. **Simulado** — provider fake/mock. Prova a lógica, prova ramo, não prova
   integração.
2. **Dry-run com o envio final bloqueado** — o fluxo REAL roda inteiro (fila,
   template, dedupe, guard de pausa, montagem do payload), e a última chamada,
   a que entrega, é a única coisa desligada. Logue o payload exato que teria
   saído e confira destinatário, texto e contagem. É aqui que aparecem os erros
   que o mock não tem: destinatário duplicado, template com variável vazia,
   lista maior do que devia.
3. **Smoke real e limitado, com autorização explícita** — um destinatário, seu
   próprio número, e você olhando. Nunca um lote, nunca "só pra ver se sobe".

O degrau 2 é o que costuma faltar: sem ele, o primeiro exercício do caminho
real de verdade é o disparo em produção. Um flag de ambiente (`DRY_RUN=1`) que
corta só o `POST` de entrega custa uma linha e é o que separa teste de
incidente.

**A contagem antes do disparo é parte do teste.** Antes de tirar o freio,
imprima quantos vão receber e quem são os 3 primeiros. Número que surpreende =
não dispare; um filtro está errado.

## Fechamento

Converta o teste descartável em ao menos UM teste que fica no repo. Após fix:
causa raiz + como prevenir a categoria do bug. Re-leia tudo que modificou antes
de reportar.
