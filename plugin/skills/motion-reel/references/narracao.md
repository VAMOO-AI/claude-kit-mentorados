# Narração: da fala ao corte na batida (só o Film)

A voz manda no tempo. Cada fala vira um WAV; o `build-timeline.py` mede cada um e monta a cena
em volta (`pre` antes da 1ª fala, `gap` entre falas, `post` depois da última, nunca menos que
`min`), arredonda para a batida (15 frames) e entrega à cena `beats`/`ends`: o frame local em
que cada fala começa e termina. A cena anima em cima disso com `bt(p, i, fração)`.

## De onde vem a voz: três caminhos

Pergunte ao dono qual usar antes de gerar qualquer coisa. Os dois primeiros não custam nada.

| Caminho | Custo | Como entra no projeto |
|---|---|---|
| **A pessoa grava a própria voz** | zero | grava cada bloco lendo as falas na ordem, com uma pausa de ~1 s entre elas; converte para `out/vo-blocks/<bloco>.mp3` e o `split-vo.py` corta por fala (passo 6) |
| **`say` do macOS** | zero | fala por fala direto em `public/vo/<id>.wav`, sem bloco nem corte (ver abaixo) |
| **ElevenLabs** | pago, ~1 crédito por caractere | blocos com tags de direção (passos 3–6). Rode o `blocks-text.py`, diga ao dono o total de caracteres **antes** de gerar e espere o ok |

**Gravação própria.** Qualquer gravador serve (celular, QuickTime). O `split-vo.py` só lê MP3:

```bash
mkdir -p <projeto>/out/vo-blocks
ffmpeg -i gravacao-b1.m4a -ac 1 -ar 48000 <projeto>/out/vo-blocks/b1.mp3
cd <projeto> && python3 ./scripts/split-vo.py b1
```

Pausa marcada entre as falas é o que faz o corte cair no lugar; confira a tabela que ele imprime.

**`say` do macOS.** A voz pt-BR muda de máquina para máquina, então detecte em vez de fixar o nome
(o nome pode ter espaço e parênteses, por isso o `sed` e as aspas). O `say` leria as tags
`[softly]`/`[long pause]` em voz alta: por isso ele lê o `vo.json` direto, uma fala por arquivo.

```bash
say -v '?' | grep pt_BR          # vozes pt-BR instaladas
V="$(say -v '?' | sed -nE 's/^(.*[^ ]) +pt_BR .*/\1/p' | head -1)"
P=<projeto>; mkdir -p "$P/public/vo"
python3 -c 'import json,sys;[print(l["id"]+"\t"+l["text"]) for l in json.load(open(sys.argv[1]))["lines"]]' "$P/vo.json" |
while IFS="$(printf '\t')" read -r id txt; do
  say -v "$V" -o "/tmp/$id.aiff" "$txt" && ffmpeg -v error -y -i "/tmp/$id.aiff" -ac 1 -ar 48000 "$P/public/vo/$id.wav"
done
```

Sem voz pt-BR na lista, ela se baixa em Ajustes do Sistema → Acessibilidade → Conteúdo Falado →
Voz do Sistema → Gerenciar Vozes. A troca de pronúncia do `say` do `blocks.json` não vale aqui:
escreva a grafia que soa certo direto no `vo.json` só para o áudio, se precisar.

## Arquivos do projeto

| Arquivo | O que tem |
|---|---|
| `vo.json` | `{"lines": [{"id", "text"}]}`: o texto como deve **soar**, por extenso ("nove da manhã", "quarenta horas") |
| `blocks.json` | `voice_id` (vem como `COLE_O_VOICE_ID`: cole o id da voz escolhida na conta do ElevenLabs), `model`, `blocks` (bloco → ids em ordem), `say` (troca de pronúncia, só no áudio) e `tags` (direção por fala) |
| `film.json` | `vo: [ids]` em cada cena: é aqui que fala e cena se casam |

## Passo a passo

1. **Falas.** Uma ideia por fala, curta. Número por extenso no `vo.json` e em algarismo nas
   `props` da cena (a tela mostra "40", a voz diz "quarenta").
2. **Blocos.** Agrupe 4–14 falas seguidas por bloco (um capítulo, por exemplo): a voz fica
   coerente dentro do bloco e cada geração custa menos chamadas.
3. **Texto do TTS:** `cd <projeto> && python3 ./scripts/blocks-text.py` → `out/vo-blocks/<bloco>.txt`,
   com as tags de direção, as trocas do `say` e um `[long pause]` entre falas. Ele imprime os
   caracteres de cada bloco: no ElevenLabs o custo é ~1 crédito por caractere, tags incluídas.
4. **Teste 1 bloco antes de gerar todos.** Ouça a pronúncia, o ritmo e a voz; ajuste `say` e
   `tags` e só depois gere o resto.
5. **Gerar a voz** (só no caminho ElevenLabs, depois do ok do dono sobre o custo).
   - Com chave de API do ElevenLabs: chame a API com o texto do bloco, `model_id` e `voice_id`
     do `blocks.json`, e salve em `out/vo-blocks/<bloco>.mp3`.
   - **Sem chave, pelo conector de criação:** `creative_generate_speech` com o texto do bloco, o
     `voice_id` e o modelo (`generations_count: 1`) → devolve o fluxo; `creative_get_flow_run_status`
     até terminar → `media[].url` é o MP3 numa URL assinada que **expira em 2 h** → baixe na hora com
     `cd <projeto> && bash ./scripts/dl.sh <bloco> '<url>'` (aspas simples: a URL tem `&`).
6. **Cortar por fala:** `cd <projeto> && python3 ./scripts/split-vo.py [bloco ...]` → `public/vo/<id>.wav`. Ele acha os
   silêncios do bloco (os `[long pause]`) e escolhe os N−1 cortes por programação dinâmica: cada corte
   perto da posição esperada pela proporção de caracteres, silêncio mais longo pesando a favor. Confira
   a tabela que ele imprime: fala com duração absurda (0,3 s, ou o dobro da vizinha) é corte no lugar
   errado — gere o bloco de novo com pausas mais marcadas ou divida o bloco.
7. **Timeline e trilha:** o `qa.sh` e o `final.sh` rodam `build-timeline.py` e `track_cinema.py`
   sozinhos. À mão, de dentro do projeto: `python3 ./scripts/build-timeline.py master` e `python3 ./scripts/track_cinema.py master`.

## Mix (`track_cinema.py`)

- Voz normalizada por RMS (−19 dBFS) e colocada no frame exato de `beats`.
- Ducking: música cai ≈ −8 dB e efeitos ≈ −4 dB enquanto há voz (envelope com ~150 ms de folga).
- Respiro de 0,4 s de silêncio antes de cada `braam`/`finale`.
- `--from S --to S` gera só um trecho em `out/prova-audio-<formato>.wav`, para conferir uma
  passagem sem renderizar o vídeo.
- O `final.sh` normaliza o arquivo final em −14 LUFS integrado, pico −1 dBTP.

## Pronúncia

- Nome em inglês ou de marca que o TTS erra entra no `say` com a grafia que soa certo ("Claude" →
  "Cláudi"). A troca vale só para o áudio; a tela e as `props` continuam com a grafia original.
- Sigla soletrada: escreva como se fala no `vo.json` ("erre-ele-esse").
