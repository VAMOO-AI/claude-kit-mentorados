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
- **`aplicavel: false`** imprime a categoria com o motivo em vez de "nenhum
  achado". Use sempre que a stack não tiver a superfície; nunca deixe a
  categoria de fora do array.
- **`trecho`**: copiado do arquivo, com quebras de linha reais (`\n` no JSON).
  Não reescreva o código de memória.
- **`issues[].achados`** referencia `achados[].id`: o gerador monta a seção de
  evidência com o trecho de cada achado citado. Um achado sem issue é decisão
  consciente (trivial ou já agrupado), não esquecimento.
- **`issues[].markdown`** (opcional) sobrescreve a montagem automática quando a
  issue precisa de um texto que o schema não expressa.
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
