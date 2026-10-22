# Teste instável — as duas causas que mais aparecem

A memória do time tem um caso por semestre de "E2E que falha e não é o seu
código". Quase sempre é uma destas duas.


## 0. Antes: CI vermelho se lê pelo erro literal

Diagnóstico de CI é onde mais se inventa causa plausível e errada. A ordem que
funciona:

1. **Pegue a mensagem literal.** `gh run view <id> --log-failed` (o
   `sed -e 's/\x1b\[[0-9;]*m//g'` limpa os códigos de cor). Se você já rerodou
   e passou, o `--log-failed` volta vazio: baixe a tentativa 1 com
   `gh api "repos/<owner>/<repo>/actions/runs/<id>/attempts/1/logs"`.
2. **Só então** olhe o diff e a arquitetura.

Num caso real (2026-08-11) a hipótese de pé era estado compartilhado entre
testes. Errada: o erro literal era `duplicate key value violates unique
constraint`. O seed gerava sufixo aleatório num espaço pequeno demais, e a
colisão aparecia em menos de 1% das execuções. Uma linha de log encerrou o que
horas de teoria de arquitetura não encerravam.

Antes de chamar um teste de **instável**, exija as três coisas juntas: o arquivo
não está no seu diff, ele passa localmente **e** o rerun fecha verde. Duas não
bastam. Quando for instável mesmo, **corrija a causa** e escreva um teste
determinístico que provaria o bug antigo; rode-o contra o código anterior pra
confirmar que ele falharia. Teste novo que passa nos dois lados não prova nada.

Nunca pipe `tsc`/`eslint` pra `head`/`tail` sem `set -o pipefail` (ou checar
`${PIPESTATUS[0]}`): o exit code é o do pipe, não do checker, e falha vira falso
verde.

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
