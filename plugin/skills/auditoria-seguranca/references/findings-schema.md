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

  "categorias": [
    { "id": "A1", "nome": "Isolamento de inquilino", "aplicavel": true,
      "nota": "O projeto não usa RLS; o isolamento é filtro manual por organizationId." },
    { "id": "A5", "nome": "Inputs sem tratamento (XSS)", "aplicavel": false,
      "nota": "Projeto sem frontend e sem HTML gerado no servidor." }
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

  "achados": [
    { "id": "F1", "categoria": "A1", "severidade": "critica",
      "evidencia": "lido", "confianca": 0.85,
      "fonte": "leitura de api/routes/reports.ts:88-96 e do middleware de auth",
      "status": "aberto",
      "titulo": "Relatório de vendas agrega todas as organizações",
      "arquivo": "api/routes/reports.ts", "linhas": "88-96",
      "trecho": "where: { createdAt: { gte: from, lte: to } },   // sem organizationId",
      "por_que": "Por que é explorável, em uma frase concreta.",
      "impacto": "O que o atacante consegue.",
      "condicoes": "Flag, config ou papel necessário. Omita se não houver.",
      "correcao": "O fix, específico o bastante para virar PR." }
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
  acento e sem maiúscula — a cor e o rótulo do chip saem daí.
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
  `risco_aceito` · `aceito_por_design`. Os quatro últimos saem do cálculo do
  veredito e aparecem com selo na tabela. Valor desconhecido em `evidencia` ou
  `status` **aborta** o gerador em vez de virar default em silêncio.
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
| só `baixa`/`informativa`, ou nada acionável | **LIBERADO** |

Crítica não confirmada nunca sai LIBERADO: confiança baixa é motivo para ir
confirmar, não para dar o assunto por encerrado.
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
python3 gerar-relatorio.py findings.json --out docs/security-audit/relatorio-auditoria-seguranca.pdf
python3 gerar-relatorio.py findings.json --out ... --html-only   # itera layout sem abrir o Chrome
```

Requisitos: Python 3.9+ (só stdlib) e um Chromium instalado (Chrome, Chromium,
Brave ou Edge — a busca cobre macOS e Linux). `pdfinfo`/`pdftoppm` (poppler) são
opcionais e servem à verificação; sem eles o script avisa que o número de
páginas **não** foi conferido.
