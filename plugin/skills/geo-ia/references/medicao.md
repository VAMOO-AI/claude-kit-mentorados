# Medição de citação e menção em IA (Canonry)

O Canonry (`@canonry/canonry`) faz as perguntas nas APIs com busca do ChatGPT (OpenAI) e do
Perplexity e guarda, por resposta, se o domínio foi **citado** (link nas fontes) e se a marca
foi **mencionada** (nome no texto).

## Chaves e custo

- Uma chave da OpenAI e uma da Perplexity, ambas da conta do mentorado. A medição de 9
  perguntas custa centavos por semana.
- **Perplexity**: a Agent API exige crédito **comprado**. Crédito gratuito (o mensal da
  assinatura Pro, ou promoção) aparece como saldo e mesmo assim dá 403 "requires paid
  credits". Os sinais: histórico de faturas vazio e nível de uso -1 em Faturamento.
- A chave nunca vai no chat nem em `--api-key` na linha de comando (fica no histórico do
  shell). Local: arquivo com permissão 600 carregado por `set -a; . arquivo; set +a`. Na
  Action: Secrets do repositório `OPENAI_API_KEY` e `PERPLEXITY_API_KEY`, que o mentorado cria
  em Settings > Secrets.

## Rodada local (primeira vez, ou para depurar)

```bash
npm install -g @canonry/canonry@7.55.1
export CANONRY_TELEMETRY_DISABLED=1
cnry bootstrap && cnry start
cnry project create <projeto> --domain <dominio> --country BR --language pt
cnry query add <projeto> "pergunta 1" "pergunta 2"
cnry run <projeto> --wait
cnry visibility-stats <projeto> --by-provider
cnry sources <projeto> --rank --limit 20
```

`cnry telemetry disable` desliga a telemetria na config. O dashboard local fica em
`http://127.0.0.1:4100`, e a chave também pode entrar por lá.

## Medição semanal na nuvem (oficial)

Não depende do computador ligado e deixa histórico comentado numa issue.

1. Copie para o projeto:
   - `${CLAUDE_PLUGIN_ROOT}/skills/geo-ia/scripts/geo-medicao.sh` → `scripts/geo-medicao.sh`
   - `${CLAUDE_PLUGIN_ROOT}/skills/geo-ia/scripts/geo-provedores.sh` → `scripts/geo-provedores.sh`
   - `${CLAUDE_PLUGIN_ROOT}/skills/geo-ia/assets/geo-medicao.yml` → `.github/workflows/geo-medicao.yml`
2. Crie `geo-perguntas.txt` ao lado do `geo-medicao.sh` copiado, com as 9 perguntas, uma por
   linha.
3. No workflow, troque `GEO_PROJETO` e `GEO_DOMINIO`. O cron padrão é segunda às 10h de
   Brasília (`0 13 * * 1`).
4. Crie o rótulo `geo-medicao` no repo (`gh label create geo-medicao`). A primeira rodada
   abre a issue; as seguintes comentam nela. Atribua a issue ao mentorado, para a
   notificação chegar.
5. Rode uma vez na mão: `gh workflow run geo-medicao.yml`.

A agenda local do Canonry (`cnry schedule`) fica desligada quando a Action está ligada, senão
a medição é paga em dobro.

## Ler o resultado

- **Por pergunta**: `Cited` e `Mentioned` de cada uma, em cada IA. A meta de trabalho é
  aparecer em pelo menos 2 das 7 perguntas sem marca, em pelo menos uma IA.
- **Por provedor**: confira que os dois aparecem. Se faltar um, o comentário abre com um aviso
  de "rodada incompleta" (vindo do `geo-provedores.sh`) e o erro de cada IA fica no log do
  passo "Medir" da Action.
- **Fontes**: os domínios mais citados mostram quem a IA lê para aquela pergunta: página de
  oferta de concorrente, lista de "melhores", imprensa ou instituição. Isso alimenta a matriz
  do plano de conteúdo.
- Uma rodada é ruído. Compare tendência de 3 ou mais semanas, sempre com as mesmas perguntas e
  os mesmos provedores.

## Linha de base manual (sem chave)

Quando ainda não há chave, faça as 9 perguntas no ChatGPT sem login, com busca
(`chatgpt.com/?q=<pergunta>&hints=search`), num navegador sem histórico, e anote numa tabela
quem a resposta cita. O Perplexity passou a pedir login até para uma pergunta só, então fica de
fora. Não é comparável com o Canonry: serve só de ponto de partida.
