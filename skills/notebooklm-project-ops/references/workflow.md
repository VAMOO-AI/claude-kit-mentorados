# Workflow

Fluxo operacional completo da skill `notebooklm-project-ops`.

## 1. Detect

Objetivo: entender o que o projeto já tem disponível.

### Ações
- Verificar se `.context/docs/` existe
- Verificar se `docs/client-notebook/` existe
- Verificar se `sources-manifest.md` já foi criado
- Verificar se `notebooklm-validation-log.md` já contém um notebook ID
- Classificar o cenário (A, B, C ou D conforme `project-detection.md`)

### Saída
- cenário identificado
- lista de arquivos curados disponíveis
- notebook ID existente (se houver)

## 2. Check Infra

Objetivo: garantir que a operação pode ser feita.

### Ações
- `claude mcp get notebooklm-mcp` — verificar servidor MCP
- `nlm notebook list` — verificar CLI e auth
- Se falhar: verificar fallback em `~/.claude/skills/notebooklm/`

### Saída
- caminho principal disponível: sim/não
- auth válida: sim/não
- fallback disponível: sim/não

### Bloqueios
- Se nem principal nem fallback estiverem disponíveis: parar e orientar setup

## 3. Prepare Sources

Objetivo: preparar o conjunto exato de fontes para o NotebookLM.

### Ações
- Listar `.md` em `docs/client-notebook/`
- Excluir arquivos de controle (manifest, log, checklist, setup notes, strategy)
- Se `sources-manifest.md` existe: validar que bate com os arquivos reais
- Se não existe: gerar manifesto novo
- Confirmar nome do notebook (do manifesto ou perguntando ao usuário)

### Saída
- manifesto validado ou gerado
- nome do notebook confirmado
- lista ordenada de fontes para upload

## 4. Create or Sync

Objetivo: criar o notebook ou sincronizar fontes em notebook existente.

### Branch: criar
Condição: notebook não existe ainda.

Ações:
1. `nlm notebook create "<nome>"`
2. Capturar notebook ID
3. Para cada fonte no manifesto: `nlm source add <ID> --file "<path>" --wait`
4. Verificar source count com `nlm notebook list`

### Branch: sincronizar
Condição: notebook já existe (ID conhecido).

Ações:
1. Para cada fonte no manifesto: `nlm source add <ID> --file "<path>" --wait`
2. Verificar source count

### Saída
- notebook ID registrado
- todas as fontes enviadas com sucesso ou falhas documentadas

## 5. Validate

Objetivo: verificar se o notebook responde corretamente.

### Ações
- Executar 3 perguntas de smoke test
- Avaliar se respostas são grounded nas fontes curadas
- Registrar resultados resumidos

### Perguntas default (adaptar por projeto)
1. Qual o propósito principal deste sistema?
2. Quais os principais módulos ou áreas disponíveis?
3. O que o usuário final ou cliente consegue ver?

### Saída
- resultado de cada pergunta (resumo curto)
- avaliação: ok / precisa revisão

## 6. Record Artifacts

Objetivo: deixar o projeto com tudo registrado para manutenção futura.

### Ações
- Criar ou atualizar `docs/client-notebook/notebooklm-validation-log.md`
- Criar ou atualizar `docs/client-notebook/notebooklm-sync-checklist.md`
- Atualizar `docs/client-notebook/sources-manifest.md` se mudou

### Saída ao usuário
Reportar de forma clara:
- nome do notebook
- notebook ID
- número de fontes
- resultado dos smoke tests
- checklist de manutenção futura

## Fluxo resumido

```
Detect → Check → Prepare → Create/Sync → Validate → Record
  ↓        ↓        ↓          ↓            ↓          ↓
cenário  infra ok  manifest  notebook     smoke     artefatos
         auth ok   fontes    fontes up    tests     log/checklist
```
