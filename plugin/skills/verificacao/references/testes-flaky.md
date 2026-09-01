# Teste instável — as duas causas que mais aparecem

A memória do time tem um caso por semestre de "E2E que falha e não é o seu
código". Quase sempre é uma destas duas.

## 1. Espera por tempo em vez de espera por condição

`sleep(50)`, `setTimeout(r, 2000)`, `waitForTimeout(1000)`: o teste chuta
quanto tempo a operação leva. Passa na sua máquina, falha no CI sob carga, e
falha mais quando a suíte roda em paralelo.

```ts
// antes: chute
await new Promise(r => setTimeout(r, 50));
expect(getResult()).toBeDefined();

// depois: condição
await waitFor(() => getResult() !== undefined);
expect(getResult()).toBeDefined();
```

Padrões:

| Espera por | Escreva |
|---|---|
| evento | `waitFor(() => events.find(e => e.type === 'DONE'))` |
| estado | `waitFor(() => machine.state === 'ready')` |
| contagem | `waitFor(() => items.length >= 5)` |
| arquivo | `waitFor(() => fs.existsSync(path))` |
| Playwright | `await expect(locator).toBeVisible()` — nunca `waitForTimeout` |

`waitFor` genérico, quando o framework não dá um:

```ts
async function waitFor(cond: () => boolean, timeoutMs = 5000, stepMs = 10) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    if (cond()) return;
    await new Promise(r => setTimeout(r, stepMs));
  }
  throw new Error(`waitFor: condição não satisfeita em ${timeoutMs}ms`);
}
```

A exceção legítima é teste **do próprio tempo** (debounce, throttle, TTL). Aí o
timeout fica, com um comentário dizendo por que aquele número.

## 2. Um teste suja o estado que outro lê

Arquivo criado no diretório errado, `.git` aparecendo dentro de `src/`, linha
no banco que só existe quando a suíte roda inteira. O teste que falha não é o
culpado; o culpado rodou antes.

Bisseção: rode os arquivos um a um e pare no primeiro que produz a sujeira.

```bash
bash <pasta-desta-skill>/scripts/find-polluter.sh '.git/index.lock' 'src/**/*.test.ts'
```

A pasta da skill é a de onde este arquivo foi carregado. O script detecta o runner (`bun test`, `npx vitest run`, `npm test`) e imprime
qual arquivo criou o alvo. Achado o poluidor, o fix é no `afterEach` dele, não
no teste que quebrou.

Quando não dá pra bissectar (a sujeira é em memória), instrumente antes da
operação perigosa, não depois que ela falha:

```ts
console.error('DEBUG git init:', { dir, cwd: process.cwd(), stack: new Error().stack });
```

`console.error`, não o logger: em teste o logger costuma estar silenciado. O
stack mostra qual arquivo de teste chamou, em que linha, e com que argumento
vazio.

Origem: `condition-based-waiting.md` e `find-polluter.sh` do superpowers
(obra/superpowers, MIT).
