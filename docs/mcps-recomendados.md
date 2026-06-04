# 🔌 MCPs recomendados (sob demanda)

MCP dá ao Claude novas "mãos" — conectar a um banco, controlar um browser, falar com
uma API. **Não instale todos de uma vez.** Cada MCP é mais superfície pra dar erro e
mais contexto consumido. Adicione quando a necessidade aparecer.

> O kit já instala o **dot-context** (`ai-context`). O resto abaixo é opcional.

Todos os comandos usam `--scope user` (vale em todos os seus projetos). Troque por
`--scope project` se quiser versionar a config junto com um repo específico.

---

## Playwright — testar UI de verdade

Deixa o Claude abrir um browser, clicar, preencher formulário e ler a página. Ótimo pra
verificar que uma tela funciona de fato, não só que o código compila.

```bash
claude mcp add playwright --scope user -- npx @playwright/mcp@latest
```

Quando usar: "abre essa página e confirma que o login funciona", testes E2E, screenshots.

---

## GitHub — PRs e issues estruturados

**Antes de instalar, saiba:** o Claude já opera o GitHub via o `gh` CLI (que você já tem
logado). Pra abrir PR, comentar, listar issues — `gh` resolve a maioria dos casos sem
MCP nenhum. Só instale o MCP se quiser interação mais estruturada/em volume.

Forma remota (precisa de um Personal Access Token do GitHub):

```bash
claude mcp add --scope user --transport http github https://api.githubcopilot.com/mcp \
  -H "Authorization: Bearer SEU_PAT_AQUI"
```

> Gere o PAT em GitHub → Settings → Developer settings → Personal access tokens.
> Nunca cole o PAT no chat nem commite — é um secret.

---

## Documentação (Context7) — já coberto

Você **não precisa** instalar o MCP do Context7: o kit já traz a skill `find-docs`, que
usa o mesmo motor (`ctx7`) por linha de comando. Peça "confere na doc oficial do X" e
pronto.

---

## Como remover um MCP

```bash
claude mcp list            # ver o que está instalado
claude mcp remove <nome>   # remover
```

---

## Regra de bolso

Comece com o mínimo (dot-context). Sentiu falta de uma capacidade concreta — testar UI,
mexer num serviço específico — aí sim adicione o MCP correspondente. Menos é mais
estável.
