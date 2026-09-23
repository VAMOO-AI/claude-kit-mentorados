# Schema do `findings.json`

Entrada única do `scripts/gerar-relatorio.py`. Todo número do PDF (resumo,
rosca, barras) é derivado daqui — não existe contagem escrita à mão.

Obrigatórios: `projeto`, `data`, `categorias`. O resto é opcional e some do PDF
quando ausente (seção vazia sai com aviso explícito, nunca em silêncio).

```jsonc
{
  "projeto": "acme-crm",
  "data": "01/09/2026",
  "escopo": ["src/", "api/routes/", "docker-compose.yml"],
  "stack": { "Linguagem": "TypeScript (Node 20)", "ORM": "Prisma 5", "Auth": "JWT próprio" },
  "nota_metodologica": "Como cada categoria foi mapeada para esta stack.",
  "resumo": "Uma ou duas frases: o que foi percorrido e onde o risco se concentra.",
  "auditoria_anterior": { "data": "01/06/2026", "arquivo": "docs/security-audit/findings.json@abc123",
                          "nota": "3 achados reverificados no código atual; F2 corrigido, F4 ainda aberto." },

  "categorias": [
    { "id": "A1", "nome": "Isolamento de inquilino", "aplicavel": true,
      "nota": "O projeto não usa RLS; o isolamento é filtro manual por organizationId." },
    { "id": "A5", "nome": "Inputs sem tratamento (XSS)", "aplicavel": false,
      "nota": "Projeto sem frontend e sem HTML gerado no servidor." },
    { "id": "A6", "nome": "Agente de IA com ferramentas", "aplicavel": false,
      "nota": "Nenhum LLM decide ação neste projeto." }
  ],

  "ferramentas": [
    { "nome": "gitleaks", "versao": "8.18.4", "estado": "executado",
      "escopo": "HEAD + 412 commits" },
    { "nome": "trivy", "versao": "—", "estado": "nao_instalado",
      "nota": "imagem do projeto não foi varrida" }
  ],

  "cobertura": [
    { "categoria": "A3", "estado": "medido", "medido": "34/34 handlers percorridos, não amostra" }
  ],

  "pontos_fortes": [
    { "categoria": "A3", "titulo": "Router de faturas valida posse em todos os handlers",
      "descricao": "Os 7 handlers cruzam id com organizationId.",
      "evidencia": "api/routes/invoices.ts:22,48,71,95,118,140,166" }
  ],

  "pontos_fracos": [
    { "titulo": "O isolamento depende de disciplina, não de mecanismo",
      "descricao": "Sem RLS nem middleware: cada query precisa lembrar do filtro." }
  ],

  "hardening": [
    { "titulo": "Cookie de sessão sem SameSite explícito",
      "descricao": "Camada B ausente com a camada A funcionando: não é achado, não pesa no veredito.",
      "arquivo": "api/plugins/session.ts:18" }
  ],

  "achados": [
    { "id": "F1", "categoria": "A1", "severidade": "critica",
      "evidencia": "lido", "confianca": 0.85,
      "fonte": "leitura de api/routes/reports.ts:88-96 e do middleware de auth",
      "status": "aberto",
      "desde": "01/06/2026",
      "titulo": "Relatório de vendas agrega todas as organizações",
      "arquivo": "api/routes/reports.ts", "linhas": "88-96",
      "caminho": [
        { "tipo": "entrada",    "arquivo": "api/routes/reports.ts", "linha": "80",
          "descricao": "GET /reports/sales aberto a qualquer usuário autenticado" },
        { "tipo": "propagacao", "arquivo": "api/plugins/auth.ts",   "linha": "31",
          "descricao": "requireAuth valida assinatura; não carrega a organização" },
        { "tipo": "sink",       "arquivo": "api/routes/reports.ts", "linha": "91",
          "descricao": "groupBy sem organizationId no where" }
      ],
      "trecho": "where: { createdAt: { gte: from, lte: to } },   // sem organizationId",
      "por_que": "Por que é explorável, em uma frase concreta.",
      "impacto": "O que o atacante consegue.",
      "condicoes": [
        { "tipo": "autenticacao", "descricao": "conta válida de qualquer plano" }
      ],
      "correcao": "O fix, específico o bastante para virar PR." },

    { "id": "F7", "categoria": "A2", "severidade": "critica",
      "status": "a_validar", "evidencia": "lido",
      "titulo": "CORS reflete qualquer Origin com credentials — se o proxy não sobrescrever",
      "arquivo": "api/plugins/cors.ts", "linhas": "9-14",
      "por_que": "A hipótese, com o caminho no código.",
      "bloqueio": "O nginx de produção não está no repositório e pode reescrever o header.",
      "plano_validacao": {
        "local": "Subir com docker-compose e fazer fetch com credentials de origem dummy.",
        "dono":  "Abrir a config do nginx e conferir add_header Access-Control-Allow-Origin." } },

    { "id": "F8", "categoria": "A3", "severidade": "alta",
      "status": "falso_positivo", "evidencia": "lido",
      "motivo": "Juiz independente em 19/09: o middleware tenantScope (api/plugins/tenant.ts:12) injeta organizationId em todo delete. Fica registrado para a próxima auditoria não repetir.",
      "titulo": "DELETE /invoices/:id sem posse",
      "arquivo": "api/routes/invoices.ts", "linhas": "140" }
  ],

  "recomendacoes": [
    { "prioridade": "P1", "texto": "Fechar os dois furos de isolamento", "achados": ["F1", "F2"] }
  ],

  "issues": [
    { "titulo": "Relatório de vendas agrega dados de todas as organizações",
      "severidade": "critica", "achados": ["F1"],
      "problema": "...", "impacto": "...", "correcao": "...",
      "criterios_aceite": ["A query filtra por organizationId",
                           "Teste com dois tenants prova o isolamento",
                           "O teste falha no commit anterior ao fix"] }
  ]
}
```

## Regras dos campos

- **`severidade`**: `critica` · `alta` · `media` · `baixa` · `informativa`. Sem
  acento e sem maiúscula — a cor e o rótulo do chip saem daí. **Âncoras**, para a
  nota não sair do que o achado parece:

  | nível | o que precisa estar demonstrado |
  |---|---|
  | `critica` | ator **não autenticado** ganha execução de código, o banco inteiro ou qualquer conta |
  | `alta` | derrota **por completo** um controle explícito com consequência real: bypass de auth, leitura ou escrita cross-tenant, XSS armazenado que atinge outros usuários, execução autenticada |
  | `media` | violação real de fronteira com raio pequeno, pré-condição incomum ou recurso restrito |
  | `baixa` | disclosure de interno não secreto, ou efeito que exige esforço sustentado por ganho mínimo |
  | `informativa` | observação confirmada de impacto mínimo, útil como pré-requisito de outro achado |

  A pergunta que separa `alta` de `media`: o resultado demonstrado **derrota** o
  controle ou só o **enfraquece**? E a regra que corta inflação: **a severidade
  nunca passa do impacto demonstrado** — se você não consegue escrever o dano
  concreto em `impacto`, a nota é menor do que parece.
- **`evidencia`**: como o achado foi obtido. Default `padrao` — quem não declarou
  não confirmou.

  | valor | significa | confiança base | teto |
  |---|---|---|---|
  | `padrao` | grep/ferramenta casou, ninguém abriu o arquivo | 0,45 | **0,60** |
  | `lido` | arquivo aberto, caminho conferido linha a linha | 0,70 | 0,85 |
  | `corroborado` | segunda fonte **independente** confirma (outra ferramenta, ou requisição real) | 0,90 | 1,00 |

- **`confianca`**: 0,0–1,0, opcional. **O teto do nível de evidência sempre vence**
  a declaração: `padrao` com `"confianca": 0.95` sai 0,60 no relatório. Convicção
  não é evidência — inclusive (e principalmente) a do modelo que escreveu o JSON.
- **`corroborado` não é autodeclaração.** Só marque com uma segunda fonte que
  exista fora da sua leitura, e nomeie-a em `fonte`. Um modelo dizendo "confirmei"
  continua sendo fonte única.
- **`fonte`**: uma frase dizendo de onde veio a evidência. Obrigatória na prática
  para `corroborado`, útil sempre.
- **`status`**: `aberto` (default) · `corrigido` · `falso_positivo` ·
  `risco_aceito` · `aceito_por_design` · `a_validar`. Todos menos `aberto` saem
  do cálculo do veredito e aparecem com selo. Valor desconhecido em `evidencia`
  ou `status` **aborta** o gerador em vez de virar default em silêncio.
- **`motivo`**: obrigatório em `falso_positivo`, `risco_aceito` e
  `aceito_por_design` (o gerador aborta sem ele). Quem tirou do veredito, por quê
  e quando — inclusive o falso positivo, que **fica no JSON** para a auditoria
  seguinte não repetir a discussão.
- **`a_validar`**: hipótese com caminho real no código cuja confirmação depende
  de um fato que o repositório **não mostra** — header do proxy, config do
  provedor, policy do deploy, comportamento do browser. Não é achado com
  confiança baixa: é achado **bloqueado**. Exige `bloqueio` (o fato exato que
  falta) e `plano_validacao` com pelo menos um de `local` (fixture ou serviço
  local com tenant dummy) ou `dono` (o que o dono do deploy abre e confere).
  Sai da rosca, das barras e da tabela; ganha seção própria, sem severidade. A
  `severidade` declarada é **potencial**: só serve para uma crítica pendente
  nunca sair `LIBERADO`. Nunca escreva ali instrução para testar contra
  produção.
- **`caminho[]`** (opcional, recomendado em A1/A3): a trilha `entrada` →
  `propagacao`* → `sink`, cada passo com `arquivo`, `linha` e `descricao`. O
  primeiro passo é uma entrada de **menor confiança** de verdade (rota, mensagem,
  arquivo recebido); o último é a query, o `innerHTML`, o `exec`. O `--verificar`
  recusa caminho que não começa em `entrada` ou não termina em `sink`.
- **`condicoes`**: texto livre continua aceito; a forma tipada é uma lista de
  `{ "tipo", "descricao" }` com `tipo` em `autenticacao` · `papel` · `interacao`
  · `configuracao` · `rede` · `dependencia` · `estado` · `tempo`. É o campo que
  evita a issue devolvida como "não reproduz".
- **`compliance`** (opcional): lista de `"FRAMEWORK:CONTROLE"` para etiquetar o
  achado nos controles de compliance (`["OWASP:A01:2025", "OWASP-API:API7:2023"]`).
  Omitido, o achado herda o **default da categoria** — não precisa declarar para
  o PDF imprimir a seção "Rastreabilidade de compliance". Declare quando o
  subtipo pede precisão (SSRF, chave de assinatura, deputado confuso) ou quando o
  dado alcançado é pessoal (`LGPD:Art.46`). O campo **substitui** o default, não
  soma. Frameworks aceitos: `OWASP` (Top 10:2025) · `OWASP-API` · `OWASP-LLM` ·
  `ISO27001` · `NIST-CSF` · `SOC2` · `PCI-DSS` · `LGPD`. Prefixo fora da lista,
  controle fora do formato da norma vigente (ex.: `OWASP:A03:2021`) ou valor que
  não é lista **abortam** o gerador, com ou sem `--verificar`. Mapa, formatos e
  justificativa de cada controle em `references/compliance-map.md`. É
  rastreabilidade sobre o achado provado: não altera severidade nem veredito.
- **`desde`**: data da auditoria em que o achado apareceu pela primeira vez,
  quando ele foi carregado de um `findings.json` anterior.
- **`hardening[]`**: melhoria de defesa em profundidade **sem violação de
  fronteira alcançável hoje** (cookie sem `SameSite` numa API que usa header,
  rate limit ausente onde não há oráculo). Seção própria, fora do veredito, fora
  das issues de segurança. É onde vai o que não é achado — em vez de inflar
  `achados[]` com `baixa` para não perder a nota.
- **`auditoria_anterior`**: quando existe `findings.json` de uma rodada passada,
  `data`, `arquivo` (com o ref do commit) e `nota` dizendo quantos achados foram
  reverificados e o destino de cada um. Sem o campo, a capa diz que é a primeira
  auditoria registrada.
- **`redacao: false`**: desliga a máscara automática de segredo naquele `trecho`.
  Use só quando o valor literal **é** a evidência — default público versionado,
  por exemplo. Por padrão o gerador mascara chave, JWT, token e atribuição de
  segredo antes de escrever o PDF e a issue.
- **`ferramentas[]`**: o que rodou e o que não rodou. `estado` é `executado` ·
  `nao_aplicavel` · `nao_instalado` · `falhou`. Os dois últimos imprimem um aviso
  de superfície não medida no relatório — ausência de achado onde nada rodou não
  é evidência de nada, e é assim que uma auditoria "limpa" engana quem lê.

## Veredito

Derivado, nunca escrito à mão. Sai na capa e abre o resumo executivo:

| Condição (achado acionável) | Veredito |
|---|---|
| `critica` com confiança ≥ 0,50 | **BLOQUEADO** |
| `alta` `corroborado`, ou confiança ≥ 0,70 | **BLOQUEADO** |
| `critica` com confiança < 0,50 | **REVISAR** |
| `alta` restante, ou qualquer `media` | **REVISAR** |
| `a_validar` com severidade potencial `critica` | **REVISAR** (nunca bloqueia, nunca libera) |
| só `baixa`/`informativa`, ou nada acionável | **LIBERADO** |

Crítica não confirmada nunca sai LIBERADO: confiança baixa é motivo para ir
confirmar, não para dar o assunto por encerrado. O mesmo vale para a crítica
bloqueada por fato externo — o bloqueio é para resolver.
- **`aplicavel: false`** imprime a categoria com o motivo em vez de "nenhum
  achado". Use sempre que a stack não tiver a superfície; nunca deixe a
  categoria de fora do array.
- **`trecho`**: copiado do arquivo, com quebras de linha reais (`\n` no JSON).
  Não reescreva o código de memória.
- **`issues[].achados`** referencia `achados[].id`: o gerador monta a seção de
  evidência com o trecho de cada achado citado. Um achado sem issue é decisão
  consciente (trivial ou já agrupado), não esquecimento.
- **`issues[].markdown`** (opcional) sobrescreve a montagem automática quando a
  issue precisa de um texto que o schema não expressa. Também passa pela máscara
  de segredo, e sem escotilha: aqui não há como marcar `redacao: false`.
- **Cuidado com o nome repetido:** em `achados[]`, `evidencia` é o **nível**
  (`padrao`/`lido`/`corroborado`); em `pontos_fortes[]`, `evidencia` é texto
  livre (`api/routes/invoices.ts:22,48`). Campos diferentes em listas diferentes.
- **Agrupe achados do mesmo tema numa issue só** (ex.: todos os defaults de
  segredo do compose) para não gerar spam de issues.

## Rodar

```bash
python3 gerar-relatorio.py findings.json --verificar --raiz .    # antes de gerar: falha alto
python3 gerar-relatorio.py findings.json --out docs/security-audit/relatorio-auditoria-seguranca.pdf
python3 gerar-relatorio.py findings.json --out ... --html-only   # itera layout sem abrir o Chrome
```

O `--verificar` cobra o que este arquivo promete em prosa: `arquivo` existe,
`linhas` cabem nele, cada linha do `trecho` está lá (anotação `// ...` no fim da
linha é tolerada; código reescrito de memória não é), `corroborado` tem `fonte`,
`caminho` vai de `entrada` a `sink`, e toda issue ou recomendação cita achado que
existe. Sem `--raiz` ele confere só as referências e imprime que o código **não**
foi conferido — não deixe essa linha passar.

Requisitos: Python 3.9+ (só stdlib) e um Chromium instalado (Chrome, Chromium,
Brave ou Edge — a busca cobre macOS e Linux). `pdfinfo`/`pdftoppm` (poppler) são
opcionais e servem à verificação; sem eles o script avisa que o número de
páginas **não** foi conferido.
