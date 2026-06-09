# Project Detection

Como a skill detecta o contexto documental de cada projeto.

## Checklist de detecção

Ao ser acionada, a skill deve verificar nesta ordem:

1. **`.context/docs/`** — camada técnica do projeto
2. **`docs/client-notebook/`** — camada curada para cliente/usuário
3. **`docs/client-notebook/sources-manifest.md`** — manifesto de fontes já existente
4. **`docs/client-notebook/notebooklm-validation-log.md`** — log de validação com notebook ID
5. **`docs/client-notebook/notebooklm-sync-checklist.md`** — checklist de manutenção

## Cenários

### Cenário A — Projeto pronto
- `.context/docs/` existe
- `docs/client-notebook/` existe com pelo menos README + 1 doc curado

**Ação:** seguir fluxo completo.

### Cenário B — Só documentação técnica
- `.context/docs/` existe
- `docs/client-notebook/` não existe

**Ação:** GERAR automaticamente a camada client-facing.
1. Ler `.context/docs/` para entender o projeto
2. Criar `docs/client-notebook/` com a estrutura padrão (README + 8 docs curados)
3. Seguir regras editoriais: linguagem simples, sem detalhes internos, sem segredos
4. Revisar o resultado para tom e precisão
5. Depois continuar o fluxo normalmente (Phase 3+)

### Cenário C — Sem documentação adequada
- `.context/docs/` não existe
- `docs/client-notebook/` não existe

**Ação:** BLOQUEAR.
Mensagem: "Este projeto não possui a estrutura documental mínima necessária. A skill precisa de pelo menos `docs/client-notebook/` com fontes curadas para operar."

### Cenário D — Notebook já existe
- `notebooklm-validation-log.md` contém um notebook ID
- ou o nome do notebook já aparece em `nlm notebook list`

**Ação:** sincronizar em vez de criar. Não recriar notebook.

## Arquivos curados vs. arquivos de controle

### Arquivos curados (fontes para o NotebookLM)
Qualquer `.md` em `docs/client-notebook/` que **não** seja um dos arquivos de controle abaixo.

### Arquivos de controle (não enviar ao NotebookLM)
- `sources-manifest.md`
- `notebooklm-validation-log.md`
- `notebooklm-sync-checklist.md`
- `notebooklm-setup-notes.md`
- `notebooklm-integration-strategy.md`

## Adaptação entre projetos

Projetos diferentes podem ter nomes diferentes para os docs curados. A skill deve:
1. listar todos os `.md` em `docs/client-notebook/`
2. excluir os arquivos de controle
3. usar o restante como conjunto de fontes
4. gerar ou atualizar o manifesto com base nesse conjunto real
