# verificacao — Bug difícil: o loop vermelho antes da hipótese

Lido quando a seção "Bug difícil" da `verificacao` dispara: bug que não se explica no primeiro
olhar, regressão de desempenho ou falha intermitente. Adaptado de
[mattpocock/skills](https://github.com/mattpocock/skills) (`diagnosing-bugs`, licença MIT).

## Segredo fora do que você mostra

Comando, output e captura que você cola levam `<REDACTED>` no lugar de token, chave e cookie.
Monte o loop lendo a credencial do ambiente (`$SUPABASE_SERVICE_ROLE_KEY`, `.env.local`), não
escrita no comando. De um HAR ou log com header de auth, cite só as linhas que carregam o sinal.

## 1. O loop (é aqui que o bug se resolve)

Com um sinal de passa/falha que fica vermelho **neste** bug, bisect, hipótese e log só consomem
esse sinal. Sem ele, ler código não acha a causa. Gaste o esforço aqui. Na ordem em que costuma
valer:

1. Teste falhando na costura que alcança o bug (unitário, integração ou e2e).
2. `curl` contra o dev server ou a edge function local.
3. CLI com uma entrada fixa, comparando o stdout com um snapshot bom.
4. Playwright dirigindo a UI e afirmando sobre DOM, console ou rede.
5. Replay de um payload capturado: o webhook, o evento do n8n ou a request salva em disco,
   rodando só aquele caminho.
6. Harness descartável: o pedaço mínimo do sistema (uma função, dependências falsas) chamado uma vez.
7. Loop de entrada aleatória (1000 casos) quando o sintoma é "às vezes sai errado".
8. `git bisect run` com um script que sobe o estado, checa e devolve 0/1, quando o bug apareceu
   entre dois estados conhecidos.
9. Diferencial: a mesma entrada na versão velha e na nova (ou em duas configs), com diff da saída.
10. Último recurso, quando só um humano consegue clicar: o roteiro do `hitl-loop.sh` (seção
    "O que só um humano consegue verificar" da `verificacao`).

**Aperte o loop.** Mais rápido (cache do setup, escopo do teste menor), sinal mais preciso
(afirmar o sintoma, não "não quebrou") e determinístico (relógio fixo, seed, rede congelada).
Um loop de 30 s que oscila quase não ajuda; um de 2 s estável resolve.

**Intermitente:** a meta é subir a taxa de reprodução, não um repro limpo. Rode o gatilho 100
vezes, em paralelo, com carga ou `sleep` estreitando a janela. Com 50% de falha dá para
depurar; com 1%, não. Para teste instável no CI, `references/testes-flaky.md`.

**Sem loop possível:** pare e diga, com o que tentou. Peça (a) acesso ao ambiente que reproduz,
(b) uma captura com segredo removido (HAR, log, gravação de tela com horário) ou (c)
autorização para instrumentar produção por um tempo. Hipótese sem loop não começa.

**Pronto quando** você nomeia **um comando** já rodado ao menos uma vez (cole a invocação e o
output) que:

- [ ] passa pelo caminho real do bug e afirma **o sintoma exato que a pessoa relatou**, então
      fica vermelho agora e verde depois do fix;
- [ ] dá o mesmo veredito toda vez (intermitente: uma taxa alta e fixa);
- [ ] roda em segundos;
- [ ] roda sem você parar para alguém clicar (humano só pelo `hitl-loop.sh`).

Se você se pegar lendo código para montar uma teoria antes desse comando existir, volte: pular
para a hipótese é exatamente a falha que esta etapa evita.

## 2. Reproduzir e reduzir

Rode o loop e veja ficar vermelho. Confira que é **a falha que a pessoa descreveu**, não uma
vizinha (bug errado, fix errado), e guarde o sintoma literal (mensagem, saída, tempo).

Depois reduza: corte entrada, caller, config, dado e passo **um por vez**, rodando o loop a cada
corte. Fica pronto quando todo elemento que sobrou é necessário: tirar qualquer um deixa verde.
O caso mínimo encolhe o espaço de hipóteses e vira o teste de regressão do passo 5.

## 3. Hipóteses: 3 a 5, ranqueadas, antes de testar qualquer uma

Uma hipótese só ancora na primeira ideia plausível. Cada uma diz o que prevê:

> "Se a causa é X, mudar Y faz o bug sumir / mudar Z piora."

Sem previsão, é palpite: afie ou descarte. **Mostre a lista à pessoa antes de testar**: ela sabe
que "o #3 foi o deploy de ontem" ou que o #1 já foi descartado. Se ela não estiver, siga com o
seu ranking.

## 4. Instrumentar: uma variável por vez

Cada sonda responde a uma previsão do passo 3. Prefira debugger ou REPL; depois log nas
fronteiras que separam as hipóteses; "logar tudo e dar grep" não entra.

**Todo log de debug leva uma tag única**, por exemplo `[DEBUG-a4f2]`. A limpeza vira um grep;
log sem tag fica para sempre no código.

**Desempenho:** log costuma enganar. Meça primeiro (`performance.now()`, profiler,
`EXPLAIN ANALYZE` da query), guarde a linha de base e então bisseque.

## 5. Teste de regressão antes do fix, na costura certa

Costura certa é a que exercita o padrão real do bug como ele acontece no caller. Se a única
disponível é rasa demais (teste de um caller só quando o bug precisa de dois, unitário que não
reproduz a cadeia), o teste ali dá falsa confiança: registre que **falta costura** como achado.
É a arquitetura impedindo de travar o bug.

Com costura certa:

1. Transforme o caso mínimo em teste que falha.
2. Veja falhar. Se forçou o vermelho mexendo em código ou fixture, faça `diff` contra a cópia
   limpa para provar que a mudança pegou.
3. Aplique o fix e veja passar.
4. Rode de novo o loop do passo 1 no cenário original, não reduzido.

## 6. Limpeza antes de "pronto"

- [ ] O loop do passo 1 não reproduz mais.
- [ ] O teste de regressão passa (ou a falta de costura está registrada).
- [ ] `grep -rn 'DEBUG-a4f2'` volta vazio.
- [ ] Protótipo descartável apagado ou numa pasta marcada como debug.
- [ ] A hipótese que se confirmou está na mensagem do commit ou no PR.
