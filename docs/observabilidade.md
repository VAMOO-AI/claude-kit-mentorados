# Como você descobre que quebrou? (observabilidade)

Faça esta pergunta sobre o seu app: **um usuário diz "deu erro ontem às 14h" — quanto
tempo até você estar olhando a linha de código?**

Se a resposta é "preciso tentar reproduzir", você não tem observabilidade. E isso não
é um detalhe de projeto grande: é o que separa "corrigi em 10 minutos" de "passei o
sábado adivinhando".

Sistema sem rastro não é sistema estável. É sistema onde ninguém enxerga a
instabilidade.

## A armadilha número 1: apagar o próprio rastro

Quase todo tutorial de build de produção manda tirar os `console.log` do bundle final:

```ts
// vite.config.ts
build: { minify: 'esbuild', drop: ['console', 'debugger'] }   // Vite
// next.config.js
compiler: { removeConsole: true }                              // Next
```

Faz sentido: `console.log` deixa o bundle maior e pode vazar informação. **Mas se você
ligar isso antes de ter um error tracker, você apagou o único registro que teria.**

O caso real que originou esta página: um app em produção tinha um `ErrorBoundary` cujo
`componentDidCatch` fazia só `console.error(erro)`. O build de produção removia o
`console`. Resultado: **erro de React em produção não deixava rastro em lugar nenhum** —
nem no navegador do usuário, nem em servidor, nem em log. O time só sabia de bug quando
alguém reclamava no WhatsApp.

**A regra:** error tracking entra **antes** do `drop: ['console']`. Nunca o contrário.
As duas coisas no mesmo PR, nessa ordem.

## O mínimo que resolve 90%

### 1. Um error tracker (Sentry é o default sensato)

Tem plano gratuito que dá conta de projeto pequeno.

```bash
npm install @sentry/react     # ou @sentry/nextjs
```

```ts
// src/lib/observability.ts
import * as Sentry from '@sentry/react'

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,   // o DSN é público por design, pode ir no bundle
  environment: import.meta.env.MODE,
  release: __BUILD_SHA__,                  // sem isso o stack trace vem minificado
  sendDefaultPii: false,
  beforeSend(event) {
    delete event.request?.headers          // nunca mande header de autenticação
    return event
  },
})
```

Duas coisas que a maioria esquece e que decidem se aquilo vai servir pra alguma coisa:

- **`release`** — sem ele, o stack trace chega como `a.b.c is not a function` na linha
  1 do bundle minificado. Inútil.
- **`beforeSend`** — evita mandar token e dado de cliente pro serviço de terceiro por
  acidente.

### 2. Sourcemap: gerar sim, publicar não

O sourcemap é o que traduz o bundle minificado de volta pro seu código. Você **precisa**
dele no error tracker, e **não quer** ele servido junto com o site (senão qualquer um lê
seu código-fonte original).

```bash
sentry-cli sourcemaps upload --release "$GITHUB_SHA" ./dist
find dist -name '*.map' -delete     # sobe pro Sentry, some do que é publicado
```

### 3. ErrorBoundary por área, não um só

Um `ErrorBoundary` no topo da árvore transforma erro de qualquer componente em tela
branca do app inteiro. Um por área isola o estrago:

```tsx
<ErrorBoundary area="checkout" onError={report}><Checkout /></ErrorBoundary>
<ErrorBoundary area="perfil"   onError={report}><Perfil /></ErrorBoundary>

function report(error, info, area) {
  Sentry.captureException(error, { tags: { area } })   // <- chama o tracker, não console
}
```

### 4. Log estruturado no servidor

Em API route, server action ou Edge Function, JSON de uma linha em vez de texto solto:

```ts
console.log(JSON.stringify({ ts: new Date().toISOString(), fn: 'checkout', event: 'pagamento.falhou', pedido_id }))
```

Texto livre você não consegue filtrar nem agrupar. JSON você consegue. E **nunca** logue
o corpo inteiro da requisição: ali moram senha, token e dado pessoal.

## Alerta tem que sair do sistema que ele vigia

Erro comum e traiçoeiro: criar um monitor que grava o alerta numa tabela que o próprio
app exibe numa tela de notificações.

Quando o app cai, o alerta cai junto — e **o silêncio parece normalidade.** Você só
descobre pelo cliente.

Alerta útil vai pra fora: WhatsApp, e-mail, Slack, Telegram. Um webhook simples resolve.

E monitore **ausência de evento**, não status. "O serviço está ativo" mente: já houve
caso de integração marcada como ativa que não recebia nada havia horas. O alerta certo é
*"nenhum pedido nas últimas 3 horas"*, não *"o servidor respondeu"*.

## Checklist

- [ ] Error tracker instalado **antes** de qualquer `drop: ['console']`
- [ ] `release` configurado e sourcemap enviado (e apagado do que é publicado)
- [ ] `ErrorBoundary` por área, chamando o tracker no `onError`
- [ ] Log de servidor em JSON com um campo que identifique a função
- [ ] Nenhum token, senha ou dado pessoal indo pro tracker ou pro log
- [ ] Alerta com destino **fora** do app que ele monitora

## A skill `baseline` faz esse check por você

O kit instala a skill **`baseline`**, que audita isso e mais seis frentes (bundle, RLS,
login e permissão, limites de uso, carga, segredos). Peça *"roda o baseline"* ou
*"esse app está pronto pra produção?"*.

Ela tem uma regra que vale a pena entender, porque é útil em qualquer auditoria:
**quando não consegue medir alguma coisa, ela diz "não medido" — nunca "está ok".** Se
faltar uma ferramenta, o relatório mostra o buraco em vez de fingir cobertura. E se ela
não conseguir medir nada, **falha de propósito**, porque relatório vazio parece
aprovação e é o pior resultado possível.

Detalhes de segurança em [`seguranca.md`](seguranca.md).
