# Testes end-to-end (e2e) com Playwright

Type-check e lint dizem que o código **compila**. Eles NÃO dizem que **funciona**.
Teste e2e = um robô abre o navegador, loga, clica e confere a tela — o caminho do usuário de verdade.
É o que pega "o botão existe mas não faz nada", "a tela bugou ao clicar", "salvou mas deu erro silencioso".

> Comece pelo **smoke test**: 1 teste do caminho mais crítico (login → home → ação central).
> Um smoke verde já vale muito. Não precisa testar tudo de cara.

## Setup (uma vez por projeto)

```bash
npm i -D @playwright/test
npx playwright install chromium
```

Copie os exemplos de `templates/playwright/` (tirando o `.exemplo` do nome):
- `playwright.config.ts` — sobe seu app e configura o browser
- `e2e/smoke.spec.ts` — o teste (ajuste os seletores pra SUA tela)
- `scripts/seed-e2e-user.mjs` — cria um usuário de teste no Supabase
- `.github/workflows/e2e.yml` — roda no CI

No `package.json`, adicione: `"test:e2e": "playwright test"`.
No `.gitignore`, adicione: `/test-results/`, `/playwright-report/`, `/e2e/.auth/` (esse último guarda sessão = token; NUNCA commitar).

## Rodar

```bash
npx playwright test            # roda tudo
npx playwright test --ui       # modo visual — MELHOR pra debugar: vê cada passo e o print
```

## Como achar os seletores certos (método)

Não adivinhe. Rode `--ui`, deixe o teste falhar, e o Playwright mostra um **print da tela real**
+ a "árvore" de elementos. Aí você ajusta `getByRole`/`getByLabel`/`getByPlaceholder` pro que está lá.
Prefira seletores por **papel + nome** (`getByRole('button', { name: 'Salvar' })`) — eles
sobrevivem a mudança de CSS.

## ⚠️ Armadilhas que já custaram horas (pule elas)

1. **`localhost`, não `127.0.0.1`** no `baseURL`. Com `127.0.0.1` o Next bloqueia recursos do dev
   por "cross-origin" → a página não hidrata → os cliques param de funcionar no teste (e o erro é confuso).
2. **Botão ambíguo** → use `{ exact: true }`. `name: 'Entrar'` casa também "Entrar com Google" e o teste quebra.
3. **Página "server component" que usa a service_role** → no CI o app dá **erro 500** se você não passar
   `SUPABASE_SERVICE_ROLE_KEY` pro passo que roda o app (não basta passar só pro seed).
4. **Esperar tempo fixo é frágil.** Nada de `waitForTimeout(2000)`. Use `await expect(algo).toBeVisible()` —
   o Playwright espera o elemento aparecer, no tempo certo.
5. **Login com botão "custom"** que não é `<button type="submit">` de verdade: às vezes o clique não envia o
   form. Saídas: apertar Enter no campo de senha, ou logar via API (`fetch('/api/login')`) no setup.
6. **Teste que se auto-pula quando falta variável** vira **CI verde mentiroso** (parece que passou, mas nada rodou).
   Se você usar `test.skip(semEnv)`, faça ele **FALHAR no CI** (não pular) quando o secret faltar — senão você
   nunca descobre que está sem cobertura.

## O usuário de teste e os Secrets

- O `seed-e2e-user.mjs` cria um `e2e@...` dedicado com a `service_role`. Não use uma conta real.
- Local: as chaves ficam no `.env.local` (gitignored). CI: cadastre os mesmos nomes em
  **Settings → Secrets and variables → Actions** do repo.
- Se o app aponta pra **produção**, prefira um projeto Supabase de teste — o e2e escreve dados ao logar/clicar.

## Quando travar

Roda `--ui`, olha o print da falha, ajusta o seletor. Se não destravar, manda o print pro Claude
(ou pro Ruan) — com a imagem da tela real, o seletor certo sai na hora.
