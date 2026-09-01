# 02 — Projeto, banco, handlers, idempotência e cron

## Estrutura

```
meu-bot/
├─ src/
│  ├─ bot/index.ts              # entrypoint: carrega env e sobe o bot
│  └─ lib/
│     ├─ supabase.ts
│     └─ discord/
│        ├─ bot.ts              # orquestrador magro: client, eventos, crons
│        ├─ core/               # regras puras e testáveis (canais, membros, datas)
│        ├─ handlers/           # reagem a evento do Discord (efeito)
│        ├─ parsers/            # texto → objeto (função pura)
│        └─ modules/            # jobs e relatórios
├─ Dockerfile
├─ docker-compose.yml
├─ .env.example                 # commitado, chaves sem valores
├─ .env                         # NUNCA commitado
├─ package.json
└─ tsconfig.json
```

**A regra de arquitetura que se paga:** `bot.ts` é orquestrador **magro** — cria o client, liga
eventos, agenda cron. Regra de negócio vive em `core/` (puro, testável sem Discord) e o efeito em
`handlers/`. Quando `bot.ts` passa de ~200 linhas, o bot fica intestável e todo bug vira sessão
de tentativa e erro no servidor de verdade.

## package.json

```json
{
  "name": "meu-bot",
  "private": true,
  "type": "module",
  "scripts": {
    "bot": "tsx src/bot/index.ts",
    "bot:dev": "tsx watch src/bot/index.ts",
    "test": "vitest run"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.99.3",
    "discord.js": "^14.25.1",
    "dotenv": "^17.2.3",
    "node-cron": "^4.2.1"
  },
  "devDependencies": {
    "@types/node": "^22.19.15",
    "@types/node-cron": "^3.0.11",
    "tsx": "^4.21.0",
    "typescript": "~5.8.2",
    "vitest": "^4.1.4"
  }
}
```

`tsx` roda TypeScript direto, sem passo de build: um arquivo a menos para desincronizar entre a
sua máquina e o container. (Confirme as versões atuais com a skill `find-docs` antes de fixar.)

## tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "noEmit": true,
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*.ts"]
}
```

## src/bot/index.ts — ARMADILHA Nº 2 (ordem de carga do env)

```ts
import dotenv from 'dotenv';
import path from 'path';

// Carrega o env ANTES de qualquer import da aplicação.
// Imports ES são hoisted: um `import { startBot } from '...'` no topo executaria
// ANTES do dotenv.config(), e o client do Supabase nasceria com URL undefined.
// Por isso o import do app é dinâmico, depois do config.
dotenv.config({ path: path.resolve(process.cwd(), '.env.local') });
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

const { startBot } = await import('../lib/discord/bot.ts');

startBot().catch((err) => {
  console.error('[Bot] Falha ao iniciar:', err);
  process.exit(1);
});

process.on('SIGINT', () => { console.log('[Bot] Encerrando...'); process.exit(0); });
process.on('SIGTERM', () => { console.log('[Bot] Encerrando...'); process.exit(0); });
```

## .env.example (commitado, sem valores)

```bash
DISCORD_BOT_TOKEN=
DISCORD_GUILD_ID=
DISCORD_CHANNEL_ENTRADA=
DISCORD_CHANNEL_RELATORIOS=
DISCORD_AUTHORIZED_USERS=        # ids separados por vírgula; vazio = todos liberados
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
TZ=America/Sao_Paulo
```

## Banco

O bot é **processo de servidor**: usa a **service role key**, não a anon key.

```ts
// src/lib/supabase.ts
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL!;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY!;
if (!url || !key) throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY ausentes');

export const supabase = createClient(url, key, { auth: { persistSession: false } });
```

Não caia no padrão "RLS ligada + `policy USING (true)` + anon key": é RLS decorativa — qualquer
um com a anon key (que fica exposta no frontend) escreve na sua tabela. Service role no bot,
policy restritiva de verdade para o que o frontend lê. Se estiver auditando um projeto assim,
a skill `secscan` pega isso.

Schema mínimo típico:

```sql
create table bot_messages (
  id uuid primary key default gen_random_uuid(),
  discord_message_id text unique not null,   -- UNIQUE = idempotência
  discord_author_id  text not null,
  channel_id text not null,
  business_date date not null,               -- data "de negócio", não created_at
  payload jsonb not null default '{}',
  raw_content text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index on bot_messages (business_date);
create index on bot_messages (created_at desc);

create table team_members (
  id uuid primary key default gen_random_uuid(),
  discord_author_id text unique not null,
  display_name text not null,
  role text not null check (role in ('member','manager','support')),
  is_active boolean default true
);
```

Guarde `discord_message_id` **sempre**: é a chave de reprocessar edição, deduplicar restart e
marcar efeito já executado.

## Orquestrador — src/lib/discord/bot.ts

```ts
import { Client, Events, GatewayIntentBits, Partials } from 'discord.js';
import cron from 'node-cron';
import { handleMessage } from './handlers/message-handler.ts';
import { handleCommand, registerSlashCommands, handleSlashCommand } from './handlers/command-handler.ts';
import { handleReaction, CONFIRMED_REACTION } from './handlers/reaction-handler.ts';
import { getListenChannels, isConfiguredGuild } from './core/channel-registry.ts';

export function buildClient(): Client {
  return new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMessages,
      GatewayIntentBits.GuildMessageReactions,
      GatewayIntentBits.MessageContent,   // exige o toggle do portal (reference 01)
      GatewayIntentBits.DirectMessages,
    ],
    // Sem Partials, evento em mensagem antiga (fora do cache) é IGNORADO em silêncio.
    partials: [Partials.Message, Partials.Channel, Partials.Reaction],
  });
}

export async function startBot() {
  const token = process.env.DISCORD_BOT_TOKEN;
  if (!token) { console.error('[Bot] DISCORD_BOT_TOKEN ausente. Não vou subir.'); return; }

  for (const name of ['DISCORD_GUILD_ID', 'DISCORD_CHANNEL_ENTRADA']) {
    if (!process.env[name]) console.warn(`[Bot] env recomendada ausente: ${name}`);
  }

  const client = buildClient();

  client.once(Events.ClientReady, async (ready) => {
    // ESTA linha é o critério de "subiu de verdade" (Fase 9 do SKILL.md).
    console.log(`[Bot] Online as ${ready.user.tag}`);
    console.log(`[Bot] Canais escutados: ${getListenChannels().join(', ') || 'nenhum configurado'}`);
    await registerSlashCommands(client);
    setupCrons(client);
  });

  client.on(Events.MessageCreate, async (message) => {
    await handleMessage(message);
    await handleCommand(message);
  });

  // Mensagem editada precisa REPROCESSAR: o usuário corrige a linha errada
  // em vez de postar de novo. Sem isso o banco fica com o dado velho.
  client.on(Events.MessageUpdate, async (_old, updated) => {
    if (updated.partial) { try { updated = await updated.fetch(); } catch { return; } }
    await handleMessage(updated, /* isEdit */ true);
  });

  client.on(Events.MessageReactionAdd, async (reaction, user) => {
    if (user.bot) return;
    if (reaction.partial) { try { await reaction.fetch(); } catch { return; } }
    if (!reaction.message.inGuild() || !isConfiguredGuild(reaction.message.guildId)) return;
    if (!getListenChannels().includes(reaction.message.channel.id)) return;
    if (reaction.emoji.name === CONFIRMED_REACTION) await handleReaction(reaction.message.id);
  });

  client.on(Events.InteractionCreate, async (interaction) => {
    if (!interaction.isChatInputCommand()) return;
    await handleSlashCommand(interaction);
  });

  client.on(Events.Error, (e) => console.error('[Bot] Erro do client:', e));

  await client.login(token);
  return client;
}
```

## Canais sempre por env — registry central

```ts
// src/lib/discord/core/channel-registry.ts
export function getInboxChannel()   { return process.env.DISCORD_CHANNEL_ENTRADA ?? null; }
export function getReportsChannel() { return process.env.DISCORD_CHANNEL_RELATORIOS ?? null; }

// Canal único de saída: com ele configurado, TODA publicação converge pra lá.
// Evita o bot virar spam em cinco canais quando o cliente pede "manda tudo num lugar só".
export function resolveOutboundChannel(intended: string | null): string | null {
  return getReportsChannel() ?? intended;
}

export function getListenChannels(): string[] {
  const ids = [
    getInboxChannel(),
    process.env.DISCORD_CHANNEL_EQUIPE_A,
    process.env.DISCORD_CHANNEL_EQUIPE_B,
  ].filter((id): id is string => Boolean(id));

  // dedup obrigatório: dois envs podem apontar pro MESMO canal (fallback, canal legado)
  // e sem isso a mesma mensagem é processada duas vezes.
  return Array.from(new Set(ids));
}

export function isConfiguredGuild(guildId: string | null): boolean {
  const configured = process.env.DISCORD_GUILD_ID;
  return !configured || guildId === configured;
}
```

Duas coisas que só aparecem depois de meses em produção:

- **Canal dual-use** (o bot escuta *e* publica nele) não pode ser remapeado quando você troca o
  canal de saída — senão ele para de escutar sem ninguém perceber. Mantenha `getListen*` e
  `getOutbound*` separados, mesmo quando apontam pro mesmo lugar hoje.
- **Env nova precisa existir em todo ambiente.** Variável criada só na sua máquina = feature morta
  em produção, em silêncio, porque o `??` cai no fallback e nada quebra.

## Comandos com prefixo e allowlist

```ts
// src/lib/discord/handlers/command-handler.ts
import type { Message } from 'discord.js';
import { isConfiguredGuild } from '../core/channel-registry.ts';

function authorizedUsers(): string[] | null {
  const raw = process.env.DISCORD_AUTHORIZED_USERS;
  if (!raw) return null;                        // vazio = todo mundo pode
  return raw.split(',').map((s) => s.trim()).filter(Boolean);
}

export function isAuthorized(userId: string): boolean {
  const allow = authorizedUsers();
  return !allow || allow.includes(userId);
}

export async function handleCommand(message: Message) {
  const isDM = !message.inGuild();
  if (!isDM && !isConfiguredGuild(message.guildId)) return;
  if (message.author.bot || !message.content.startsWith('!')) return;   // ignorar bots evita loop

  const [command] = message.content.slice(1).trim().split(/\s+/);
  if (!command) return;

  if (!isAuthorized(message.author.id)) {
    await message.reply('Você não tem permissão para usar esse comando.');
    return;
  }

  switch (command.toLowerCase()) {
    case 'resumo':
      await message.reply((await montarResumoDoDia()) || 'Nenhum registro hoje.');
      break;
    case 'ajuda':
      await message.reply(['Comandos:', '`!resumo` — resumo de hoje', '`!ajuda` — esta lista'].join('\n'));
      break;
  }
}
```

Allowlist por env (`vazio = todos`) é o controle de acesso mais barato que existe: liberar alguém
é editar uma variável e reiniciar o container — **zero deploy de código**.

## Slash commands

```ts
import { REST, Routes, SlashCommandBuilder, type Client, type ChatInputCommandInteraction } from 'discord.js';

const commands = [
  new SlashCommandBuilder().setName('resumo').setDescription('Resumo de hoje'),
  new SlashCommandBuilder()
    .setName('ranking')
    .setDescription('Ranking do período')
    .addStringOption((o) => o.setName('periodo').setDescription('Período')
      .addChoices({ name: 'hoje', value: 'hoje' }, { name: 'mes', value: 'mes' })),
].map((c) => c.toJSON());

export async function registerSlashCommands(client: Client) {
  const guildId = process.env.DISCORD_GUILD_ID;
  if (!guildId || !client.user) return;
  const rest = new REST({ version: '10' }).setToken(process.env.DISCORD_BOT_TOKEN!);
  // Registro por GUILD aparece na hora; registro GLOBAL demora até 1h pra propagar.
  // Em desenvolvimento use sempre guild.
  await rest.put(Routes.applicationGuildCommands(client.user.id, guildId), { body: commands });
  console.log(`[Bot] ${commands.length} slash commands registrados`);
}

export async function handleSlashCommand(interaction: ChatInputCommandInteraction) {
  // Interaction expira em 3 s. Qualquer coisa que consulte banco/API PRECISA de deferReply.
  await interaction.deferReply();
  try {
    await interaction.editReply((await montarResumoDoDia()) || 'Nenhum registro hoje.');
  } catch (e) {
    console.error('[Bot] slash falhou:', e);
    await interaction.editReply('Deu erro ao montar o resumo.');
  }
}
```

## Parser: função pura, testada

Se o bot lê mensagem escrita por gente (lista colada, formulário livre, planilha em texto), o
parser é uma função pura `(texto: string) => Registro[]` — sem `Message`, sem banco, sem rede.
É o único jeito de ter teste de verdade, e parser de texto humano quebra toda semana.

```ts
it('lê a data do cabeçalho da lista', () => {
  expect(parseList('LISTA 05/09\n- ACME | 1.200,00').date).toBe('2026-09-05');
});
```

Se for usar LLM para o que o regex não pega: **regex primeiro, LLM como fallback**, e nunca deixe
o modelo decidir sozinho um evento de negócio. Um parser generoso demais já criou "registro" a
partir de um "Bom dia" no canal. Quando desligar algo assim, escreva **por que** no código —
senão alguém religa em três meses.

## Idempotência — a parte que ninguém lembra e que mais dói

Um bot reprocessa a mesma mensagem em três situações garantidas: o autor **edita**, o container
**reinicia**, alguém **reage de novo**. Se cada passagem manda DM, posta alerta ou incrementa
contador, a equipe recebe tudo três vezes e para de confiar no bot.

**1. Upsert pela chave natural** (`discord_message_id UNIQUE`):

```ts
await supabase.from('bot_messages')
  .upsert({ discord_message_id: message.id, /* ... */ }, { onConflict: 'discord_message_id' });
```

**2. Ledger de efeitos colaterais** — uma linha por mensagem, um boolean por efeito. O gate é um
UPDATE condicional, atômico no Postgres: quem consegue atualizar a linha ganha o direito de executar.

```sql
create table side_effects (
  discord_message_id text primary key,
  alert_sent boolean not null default false,
  dm_sent    boolean not null default false
);
```

```ts
async function acquireGate(messageId: string, field: 'alert_sent' | 'dm_sent') {
  await supabase.from('side_effects')
    .upsert({ discord_message_id: messageId }, { onConflict: 'discord_message_id' });

  const { data } = await supabase.from('side_effects')
    .update({ [field]: true })
    .eq('discord_message_id', messageId)
    .eq(field, false)            // só passa quem encontrou false → executa exatamente uma vez
    .select('discord_message_id');

  return Array.isArray(data) && data.length > 0;
}

if (await acquireGate(message.id, 'alert_sent')) {
  await enviarAlerta();          // roda uma vez só, mesmo com edição, restart ou corrida
}
```

Regra geral: **gravar dado é idempotente por upsert; avisar gente precisa de gate.**

## Crons dentro do bot

```ts
function setupCrons(client: Client) {
  const tz = { timezone: 'America/Sao_Paulo' };

  cron.schedule('*/5 * * * *',  () => void recarregarCacheDeMembros(), tz);
  cron.schedule('0 8 * * *',    () => void digestMatinal(client), tz);
  cron.schedule('0 18 * * 1-5', () => void resumoDoDia(client, { silentIfEmpty: true }), tz);

  console.log('[Bot] Crons: cache 5min | digest 08:00 | resumo 18:00 (seg-sex)');
}
```

- **`timezone` sempre.** O container roda em UTC; sem isso o relatório das 8h sai às 5h.
- **`silentIfEmpty` não é detalhe.** Cron que posta "nenhum registro hoje" quatro vezes por dia
  treina a equipe a ignorar o bot. Sem conteúdo → não posta.
- **Comece com poucos.** Um bot que nasceu com 13 jobs (motivacional aleatório, saudação 7h,
  lembrete 9h e 15h…) teve que cortar para 5 porque o canal virou ruído. Adicione sob demanda.
- **Cron não é fonte de verdade.** Todo job agendado tem um comando manual equivalente (`!resumo`)
  chamando **a mesma função**: o usuário se vira quando o job falha, e você testa sem esperar as 18h.
