# Página do Plugin Mentoria

A página oficial do kit para os mentorados é a vitrine de templates:
**https://templates-mentorados.vercel.app/kit-vamoo.html**

Ela é gerada pelo repositório `VAMOO-AI/templates-mentorados` (clone local em
`~/WORKSPACES/templates-mentorados`). O kit fica na família `base` da vitrine, em primeiro lugar,
e os guias dele saem de três manifestos:

| Manifesto | O que vira |
|---|---|
| `catalogo/kit-vamoo.json` | a página do Plugin Mentoria: instalação, skills, comandos, proteções, dúvidas |
| `catalogo/primeiro-projeto.json` | o guia do primeiro pedido num projeto, do começo ao PR |
| `catalogo/mcp-sistema.json` | o guia da skill `mcp-sistema` |

Os guias da Secretária, da Gestão de RH e do Link na Bio também moram lá, cada um no manifesto
do próprio template. O filme do kit e a capa dele ficam em `midia/` do mesmo repositório.

Decisão de 15/10/2026, no PR VAMOO-AI/templates-mentorados#10. Antes disso a página era um
artefato do claude.ai; ver "O artefato antigo" no fim.

## Como pedir uma mudança

Mudança no conteúdo do kit na página é um PR no manifesto do `templates-mentorados`, nunca uma
edição no HTML e nunca no artefato. Abra uma sessão nova no clone do `templates-mentorados`, cole
o bloco abaixo e troque o `[DESCREVA AQUI]`:

```
Quero atualizar a página do Plugin Mentoria na vitrine (https://templates-mentorados.vercel.app/kit-vamoo.html).
Siga o AGENTS.md deste repositório e as regras de docs/pagina-plugin-mentoria.md do repositório
VAMOO-AI/claude-kit-mentorados (clone local em ~/WORKSPACES/claude-kit-mentorados).

O que eu quero agora: [DESCREVA AQUI]
```

## Regras

### 1. Valem as regras do `templates-mentorados`

Estão no `AGENTS.md` de lá. As que mais pegam numa mudança do kit:

- **O guia nunca é escrito à mão.** Muda o manifesto e regera com o `gerar.mjs`. Campo novo entra
  no schema (`schema/template.schema.json`) e no gerador no mesmo commit.
- **Prompt para colar no Claude é cópia literal da fonte.** O manifesto copia o texto, não o
  reescreve. Mudou a instalação aqui (a seção de instalação do `README.md`, os comandos
  `/plugin marketplace add` e `/plugin install`, o `/kit-vamoo:setup`), atualize o manifesto lá;
  nunca invente nem "melhore" o prompt na vitrine.
- **Sem travessão, e a marca é sempre "VAMOO AI".** O `gerar.mjs` e o `checar.mjs` reprovam.
- Antes do PR, `npm run check` lá dentro. Mudou layout: vitrine e guia em 375 px e nos dois temas.
- O merge na `main` do `templates-mentorados` publica na Vercel.

### 2. Bater com o kit

Confira o manifesto `catalogo/kit-vamoo.json` contra a `main` deste repositório:

- `versao` é o `version` de `plugin/.claude-plugin/plugin.json`.
- A contagem de skills (no `resumo`, nos `fatos` e no título "As N skills") é o número de pastas de
  `plugin/skills/`, e a lista de skills tem exatamente essas pastas.
- Os comandos batem com `plugin/commands/`.

Hoje: 29 skills, 3 comandos (`atalhos`, `explicar`, `revisar`); a versão é a do `plugin.json`. Release do kit que
muda versão, skill ou comando pede o PR correspondente no manifesto.

### 3. Texto

Para leigo, em português simples. Sem número sem referência. Nome de coisa pelo que a pessoa
reconhece, não pelo nome técnico.

## Peças ligadas à página

- **Filme do kit**: `midia/filme-kit-mentorados.mp4` e a capa `midia/filme-poster.jpg` no
  `templates-mentorados`, ligados pelo campo `filme` do manifesto. O projeto de edição é
  `VIDEOEDITION/projects/claude-kit-mentorados-filme-guia/`. Trocar o vídeo é publicar o arquivo
  novo com o mesmo nome em `midia/`.

## O artefato antigo

**https://claude.ai/artifact/WG4edt1XZBFmrsatgGPrZM** foi a página até 15/10/2026. Hoje é só
arquivo: na versão 17 ganhou um aviso no topo apontando para a vitrine, e os links de guia
apontam para lá.

- Não recebe conteúdo novo. Mudança no kit vai para o manifesto, não para o artefato.
- O conteúdo antigo continua lá de propósito. Remover conteúdo ou apagar o artefato é decisão do
  Ruan.
- Mudança de compartilhamento também é dele.
