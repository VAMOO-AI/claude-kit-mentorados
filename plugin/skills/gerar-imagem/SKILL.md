---
name: gerar-imagem
description: EXECUTA a geração de imagem pela API da OpenAI (gpt-image-*) e entrega o JPEG pronto para a web ou publicado dentro de um artefato. Use em "gera essa imagem", "cria uma foto para a landing", "precisa de imagem aqui", ou quando uma página/deck/proposta pede foto e não há banco de imagens. Para ESCREVER o prompt (luz, lente, direção de arte), carregue antes a skill diretor-imagem — esta aqui roda o comando, não dirige a foto.
---

# Gerar imagem

Não existe geração de imagem pelo Codex CLI (o `-i/--image` dele só ANEXA imagem ao
prompt) e o login por conta ChatGPT não dá acesso programático. O caminho é a API de
imagens, chamada pelo script desta skill.

## Fluxo

1. **Prompt** — escreva com a skill `diretor-imagem` (lean, 80–180 palavras: câmera +
   lente + abertura + ISO, esquema de luz, textura, output specs, negative).
2. **Gerar**:

```bash
python3 scripts/gerar-imagem.py --prompt-file /tmp/p.txt --out hero.jpg
python3 scripts/gerar-imagem.py --listar-modelos     # antes de assumir o modelo
```

3. **Conferir com os olhos.** Leia o arquivo gerado. É o único caso em que screenshot
   não é desperdício: o pixel é a evidência.
4. **Publicar** — em artefato, mande as imagens em `files` com caminho relativo
   (`{"hero.jpg": "/caminho/local/hero.jpg"}`) e referencie `src="hero.jpg"`. **Não**
   precisa da capability `assets`. Foto de host externo é bloqueada pela CSP do
   artefato — é por isso que geramos e publicamos junto.

## A chave

O script procura nesta ordem e **imprime de onde veio**: `$OPENAI_API_KEY` →
`~/.codex/.env.tokens` → `.env`/`.env.local` do diretório atual → `--env-file`.

`~/.codex/.env.tokens` é o lugar da chave padrão, fora de qualquer repositório — usar
ela não gera aviso. Chave lida de um `.env` de repo sai com `⚠️ o custo cai naquela
conta`: material de um projeto gerado com a chave de outro cobra do outro, e descobrir
na fatura é pior. Se a chave padrão for emprestada de algum projeto, deixe isso escrito
num comentário ao lado dela no arquivo.

## O modelo não é fixo

`--listar-modelos` faz `GET /v1/models` e filtra os de imagem. Em 18/09/2026 a conta
via `gpt-image-1`, `1.5`, `2`, `2.5-flare` e `2.5-sunburst` (default do script).
Nunca afirme de memória qual é o mais novo — uma chamada resolve.

## O que evita retrabalho

- **Proíba texto e interface no negative.** Letra gerada por IA é o "tell" mais óbvio.
  Tela de celular e monitor pedem `screen content illegible, pure glow`; o texto de
  verdade entra depois, como card HTML sobreposto à foto.
- **Equipamento que o leitor vai avaliar, não gere.** Para máquina que ele está
  pesquisando comprar, fotografe a **saída** (a peça produzida) ou o contexto. Uma
  máquina fictícia é lida como ficha técnica errada.
- **Crop de foto existente é grátis — cheque o foco antes.** Recorte de fundo com
  bokeh não vira foto de produto e custa uma geração.
- `ffmpeg` desta máquina **não tem encoder webp**: o script vai direto a JPEG `-q:v 4`
  em ~1400px, que dá 90–190KB por imagem.

## Custo

Cada geração é paga por imagem. Gere o que vai usar; itere no prompt, não na sorte.
