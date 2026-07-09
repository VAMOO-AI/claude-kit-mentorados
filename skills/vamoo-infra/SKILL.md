---
name: vamoo-infra
description: >-
  COMOs de infra sem CLI interativo pra projetos Supabase + Vercel: onde ficam
  as credenciais, rodar SQL, puxar env do Vercel, fazer deploy, e o erro de
  deploy BLOCKED por git author. Use ao mexer em env do Vercel, rodar SQL no
  Supabase, fazer deploy, ou debugar um deploy que não sai. Gatilhos: "env do
  vercel", "deploy", "supabase sql", "deploy bloqueado".
---

# Infra sem CLI interativo (Supabase + Vercel)

> As **proibições duras** (nunca `supabase login`/`link`/`db push`,
> `vercel login` interativos; onde ficam as credenciais) vivem no CLAUDE.md.
> Aqui ficam os COMOs.

## Onde ficam as credenciais

- Por projeto: `.env.local` (ex.: `VERCEL_PROJECT_ID`, `SUPABASE_DB_URL`,
  chaves de API). Esse arquivo **nunca** vai pro git.
- Pra checar se uma key existe sem vazar o valor: `grep -c '^KEY=' .env.local`
  no terminal — nunca cole o VALOR do secret no chat.

## Supabase

- SQL: rode pelo painel do Supabase (SQL Editor) ou pela CLI do projeto se ele
  tiver uma configurada. Guarde as migrations em arquivos versionados (ex.:
  `src/sql/` ou `supabase/migrations/` se o projeto já usa o padrão oficial).
- Edge Functions (só se existir a pasta `supabase/functions/`): deploy com
  `--project-ref` do seu projeto.
- Projeto Next.js puro (API routes + Vercel Cron) **não** é Edge Function — não
  rode `supabase functions deploy`.

## Vercel

- Puxar env vars pro `.env.local`: `vercel env pull .env.local`. O CLI lembra o
  projeto via `.vercel/project.json` (gitignored) — faça `vercel link` uma vez,
  depois `vercel env pull` sempre funciona.
- Deploy: normalmente é automático no push pra `main`. Redeploy manual pela CLI
  ou pelo painel.
- Onboarding em máquina nova: `vercel env pull` — NÃO copie o `.env.local` por
  cloud/USB/WhatsApp.
- Depois de deployar: confirme que foi **production** (não preview), pela URL
  retornada ou pelo painel.

## Deploy BLOCKED por "git author"

Vercel marca o deploy como BLOCKED com "Git author X must have access to the
team" (fica BLOCKED, sem nem buildar): o email do author do commit não é membro
do time no Vercel. **Solução grátis** — adicione esse email como email
VERIFICADO numa conta que já é membro do time (Account Settings → Emails → Add
Email → verificar no inbox). Não é problema de billing. NUNCA forje o git author
pra fingir que é outra pessoa nem desligue proteção de segurança pra contornar.

## Secrets entre pessoas

Nunca por WhatsApp/email/cloud. Fonte de verdade = env do Vercel (ou um
gerenciador de senhas compartilhado). `.env`/`.env.local` nunca no git; se
vazou, troque todas as chaves na hora. `.env.example` sempre commitado, com as
CHAVES sem valores, documentando o que precisa pra rodar.
