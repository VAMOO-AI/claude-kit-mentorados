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
- **Visão geral** com as seções do menu: Guia, Primeiro projeto, Instalar, Skills, Comandos,
  MCP do sistema, Proteções, Secretária, Gestão de RH, Dúvidas (10 links). A seção **Templates** (`#templates`, entre
  MCP do sistema e Dúvidas) apresenta a secretária e o RH e abre os guias deles; ela não tem item
  no menu.
- **Guias como telas separadas**, abertas por hash. São cinco, cada uma com checklist próprio
  salvo no navegador:

  | Hash | Tela (`data-view`) | Do quê | Chave no `localStorage` |
  |---|---|---|---|
  | `#guia` | `guia` | instalação do kit | `kit-steps` |
  | `#guia-primeiro-projeto` | `proj` | primeiro pedido num projeto, do começo ao PR | `kit-proj-steps` |
  | `#guia-mcp` | `mcp` | skill `mcp-sistema` | `kit-mcp-steps` |
  | `#guia-secretaria` | `secretaria` | template da secretária de WhatsApp | `kit-sec-steps` |
  | `#guia-rh` | `rh` | template da Gestão de RH | `kit-rh-steps` |

  A troca de tela fica na função `setView` e em dois mapas do script: `VIEWS` (hash → tela) e
  `VIEW_ROOT` (tela → seletor da raiz).
- **Menu do topo que rola de lado.** Os links não cabem numa linha (pedem 1034px e o espaço
  disponível é de no máximo 716px), então o `.nav` rola na horizontal, com esmaecido na borda.
  Quem faz isso são as variáveis `--fl`/`--fr` e a função `navFade` do script, que também
  converte a roda do mouse em rolagem lateral. Item novo no menu não quebra o header, mas fica
  mais escondido na rolagem.
- **Bloco "Por onde começar"** no topo de `#instalar`: uma tabela "seu momento → por onde ir"
  com 6 linhas (classes `.paths` e `.path`), sem item no menu. Guia novo ganha uma linha ali.
- **Skills** no array `SKILLS` do script, um objeto por skill: `n` nome, `c` área, `m:1` se é
  manual, `w` o que faz, `a` frase para pedir, `r` pré-requisito, `g` link de guia (opcional).
- O prompt de instalação (`#prompt-text`) leva o link do repositório e os comandos
  `claude plugin marketplace add VAMOO-AI/claude-kit-mentorados` e
  `claude plugin install kit-vamoo@vamoo-ai`. O guia copia esse mesmo texto para `#prompt-text-2`.

### 3. Guia novo

Vira mais uma tela `#guia-<nome>`, no molde das cinco que existem: topo com marca e voltar,
selo, título, barra de progresso, cards de passo com checklist, "Deu erro? Resolva aqui" e
fechamento na faixa escura. Uma tela nova só aparece com todas estas peças:

- entrada em `VIEWS` (`"#guia-<nome>": "<tela>"`) e em `VIEW_ROOT` (`<tela>: "#guia-<nome>"`);
- as duas regras de CSS, que usam o nome da tela e não o hash: acrescentar
  `body[data-view="<tela>"]` à lista que esconde `.top`, `.widget`, `.progress` e `#inicio`, e
  `body:not([data-view="<tela>"]) #guia-<nome>{display:none}`. Sem a primeira, a visão geral
  aparece por cima do guia; sem a segunda, o guia aparece no fim da visão geral;
- o array de passos e as funções de pintar e salvar, com chave própria `kit-<nome>-steps`;
- o item no menu, uma linha no bloco "Por onde começar" e, se for de uma skill, o campo `g`
  do card dela.

**Renomear uma tela mantém o hash antigo.** O link já circulou no grupo e no vídeo, então o
hash antigo fica em `VIEWS` como alias apontando para a mesma tela
(`"#guia-velho": "<tela>", "#guia-novo": "<tela>"`). Só o `VIEWS` ganha a linha: o `VIEW_ROOT`
e o CSS continuam com o nome da tela, que não muda. A chave do checklist também não muda, senão
quem já marcou passos perde o progresso.

### 4. Bater com o kit

Confira contra a `main` deste repositório:

- O selo do topo (`Kit vX.Y.Z`) tem a versão de `plugin/.claude-plugin/plugin.json`.
- O array `SKILLS` tem exatamente as pastas de `plugin/skills/`. A contagem aparece igual no
  hero, nos números da faixa escura, no título da seção de skills e nos fechamentos dos guias.
- Os comandos da seção Comandos batem com `plugin/commands/`.

### 5. Texto

Para leigo, em português simples. Sem número sem referência e sem travessão. Nome de coisa pelo
que a pessoa reconhece, não pelo nome técnico.

Por essa regra o "2 minutos" saiu da página e a métrica virou "5 guias", que conta as telas de
guia. O `#guia` tem o carimbo "Passos conferidos em <data> com o kit v<versão>": atualize a
data e a versão sempre que conferir os passos de novo.

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
