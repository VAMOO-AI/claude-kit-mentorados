# Escrita — prévia, token de confirmação, aplicar, log

Toda escrita vira DUAS tools: `<nome>_previa` e `<nome>_aplicar`.

```
<nome>_previa   → relê o estado, checa permissão, devolve antes/depois + confirm_token
                  (NÃO grava; readOnlyHint: true)
usuário confirma no agente
<nome>_aplicar  → valida o token, relê e checa TUDO de novo, recusa se o estado
                  mudou, grava o log (antes de escrever), aplica, fecha o log
```

## Peças

| Arquivo | O quê |
|---|---|
| `code/confirm-token.ts` | HMAC stateless de `{uid, kind, args, state, exp}`, TTL 5 min. Segredo: `MCP_CONFIRM_SECRET` ou derivado da service role (trocar a service role só invalida prévias em aberto) |
| `code/audit-log.ts` | `startAudit` (insere `iniciado`, lança se falhar) e `finishAudit` |
| `code/write-tools.ts` | `registerWrite(server, kind)` — gera as duas tools a partir de um `prepare(principal, args)` |
| `write-plan.ts` (do projeto) | Regras de permissão PURAS por escrita (`planX({ scope, ... }) → { ok, antes, depois } \| { ok: false, motivo }`), testadas |

## Regras

- `prepare` é a MESMA função na prévia e no aplicar, com dados relidos: permissão
  perdida entre as duas chamadas (troca de time, papel rebaixado) também barra o
  aplicar.
- `state` = o que a prévia leu e que a escrita sobrescreve. O aplicar compara
  `JSON.stringify(state)`; mudou → "o dado mudou desde a prévia, chame de novo".
- Token de outra conta, de outra escrita ou expirado → recusa com mensagem que diz
  o que fazer.
- Cache de leitura da lib (ex.: 60 s) não vale no `prepare`: leia direto.
- Grave pela MESMA função de escrita que a rota do app usa. Se ela vive dentro da
  rota, extraia para `src/lib/` por movimento literal (commit separado) e faça a
  rota chamar a lib.
- `annotations` do aplicar: `readOnlyHint: false`, `destructiveHint` = sobrescreve
  valor existente (true) ou cria algo novo (false), `idempotentHint: false`.
- `description` da prévia manda o agente mostrar a prévia e só chamar o aplicar
  com confirmação; a resposta da prévia repete isso em `proximo_passo`.
- Escrita que depende de identificador de sistema externo que o agente não tem
  (ex.: id de card de outro CRM) fica fora — melhor sem a tool que com tool que
  pede id inventado.

## Testes (antes de registrar as tools)

- `plan*`: cada fronteira de papel (sem canWrite, fora do time, destino fora do
  time, já no estado pedido, valor inválido).
- `confirm-token`: ida e volta, assinatura adulterada, expirado, formato inválido.
- `registerWrite` com mocks: token de outra conta, de outra escrita, estado
  mudado, `startAudit` falhando (nada é aplicado), `apply` lançando (log fecha
  como `falhou`).
