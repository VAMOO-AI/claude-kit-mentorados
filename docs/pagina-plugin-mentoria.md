# Página do Plugin Mentoria

A página de instalação do kit para os mentorados é um artefato do claude.ai:
**https://claude.ai/artifact/WG4edt1XZBFmrsatgGPrZM**

Ela é a página única da mentoria. Instalação, skills, comandos, proteções e guias passo a passo
entram nela, não numa página separada. Este documento é para quem (pessoa ou sessão do Claude)
vai mexer nela.

## Como pedir uma mudança

Abra uma sessão nova, cole o bloco abaixo e troque o `[DESCREVA AQUI]`:

```
Quero atualizar a página do Plugin Mentoria (https://claude.ai/artifact/WG4edt1XZBFmrsatgGPrZM).
Siga as regras de docs/pagina-plugin-mentoria.md do repositório VAMOO-AI/claude-kit-mentorados
(clone local em ~/WORKSPACES/claude-kit-mentorados).

O que eu quero agora: [DESCREVA AQUI]
```

## Regras

### 1. Partir da versão publicada

- Antes de editar, leia o artefato com a ação `read` do Artifact e leia **todas as linhas** do
  arquivo que ele salva. Construa em cima dessa versão, nunca de uma cópia local antiga: mais de
  uma sessão já publicou nesta página.
- O arquivo salvo vem com o esqueleto do publish (`<!doctype html>…<body>` na primeira linha e
  `</body></html>` na última). Tire os dois antes de republicar; o publish coloca de novo.
- Se outra sessão estiver mexendo na página, combine com ela antes de publicar.
- Publique sempre no mesmo link (parâmetro `url`). Nunca crie um artefato novo.
- A página tem arquivos publicados junto com ela (o vídeo e a capa, ver "Peças ligadas"). Publicar
  só a página mantém esses arquivos. Ao mandar `files`, não passe `null` neles nem os remova sem
  pedido. Confira com a listagem de arquivos do artefato (`scope: "files"`) depois de publicar.

### 2. Manter o que já existe

- **Design system LEADSTER**: papel `#fcfcfc`, Plus Jakarta Sans, botão em pílula preta, azul
  `#007dff` só como acento, faixa escura `#05070a`. Toda cor vem dos tokens do `:root`, com os
  blocos de tema escuro (`prefers-color-scheme` e `[data-theme]`).
- **Visão geral** com as seções do menu: Guia, Instalar, Skills, Comandos, MCP do sistema,
  Proteções, Dúvidas.
- **Guias como telas separadas**, abertas por hash: `#guia` (instalação) e `#guia-mcp` (skill
  `mcp-sistema`). Cada uma tem checklist próprio salvo no navegador (`kit-steps`,
  `kit-mcp-steps`). A troca de tela fica na função `setView` e no mapa `VIEWS` do script.
- **Skills** no array `SKILLS` do script, um objeto por skill: `n` nome, `c` área, `m:1` se é
  manual, `w` o que faz, `a` frase para pedir, `r` pré-requisito, `g` link de guia (opcional).
- O prompt de instalação (`#prompt-text`) leva o link do repositório e os comandos
  `claude plugin marketplace add VAMOO-AI/claude-kit-mentorados` e
  `claude plugin install kit-vamoo@vamoo-ai`. O guia copia esse mesmo texto para `#prompt-text-2`.

### 3. Guia novo

Vira mais uma tela `#guia-<nome>`, no molde das duas que existem: topo com marca e voltar, selo,
título, barra de progresso, cards de passo com checklist (chave própria no `localStorage`),
"Deu erro? Resolva aqui" e fechamento na faixa escura. Entra também no mapa `VIEWS`, no menu e,
se for de uma skill, no campo `g` do card dela.

### 4. Bater com o kit

Confira contra a `main` deste repositório:

- O selo do topo (`Kit vX.Y.Z`) tem a versão de `plugin/.claude-plugin/plugin.json`.
- O array `SKILLS` tem exatamente as pastas de `plugin/skills/`. A contagem aparece igual no
  hero, nos números da faixa escura, no título da seção de skills e nos fechamentos dos guias.
- Os comandos da seção Comandos batem com `plugin/commands/`.

### 5. Texto

Para leigo, em português simples. Sem número sem referência e sem travessão. Nome de coisa pelo
que a pessoa reconhece, não pelo nome técnico.

### 6. Antes e depois de publicar

- Rode `node --check` no script da página e mostre o diff do que mudou.
- Depois de publicar, diga a versão do artefato e o que entrou.
- A página é privada até o Ruan liberar no menu Compartilhar. Mudança de compartilhamento é dele.

## Peças ligadas à página

- **Vídeo do kit** com a chamada do guia nos primeiros segundos: projeto
  `VIDEOEDITION/projects/claude-kit-mentorados-filme-guia/` (o `capture.mjs` dali recaptura a
  página para a miniatura do vídeo).
- **O mesmo vídeo no topo da página**: o bloco `<figure class="film">` no começo do hero toca
  `filme-kit-mentorados.mp4` com a capa `filme-poster.jpg`. Os dois são arquivos publicados junto
  com a página, não ficam dentro do HTML. O artefato só aceita até 15 MB por arquivo e não carrega
  vídeo de outro site, então a versão da página é 540 × 960, com cerca de 14 MB (sai do
  `filme-kit-mentorados-guia-9x16.mp4` em duas passadas, vídeo a 280 kbps e áudio a 56 kbps).
  Trocar o vídeo é publicar o arquivo novo com o mesmo nome. Ao abrir um guia, o `setView`
  pausa o vídeo.
