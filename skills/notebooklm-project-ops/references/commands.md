# Commands Reference

Comandos exatos validados no ambiente do usuário para operar o NotebookLM.

## Caminho principal: `nlm` / `notebooklm-mcp`

### Verificar MCP
```bash
claude mcp get notebooklm-mcp
claude mcp list
```

### Listar notebooks
```bash
PYTHONIOENCODING=utf-8 nlm notebook list
```

Se `nlm` não estiver no PATH, usar caminho absoluto:
```bash
PYTHONIOENCODING=utf-8 "C:/Users/<seu-usuario>/AppData/Roaming/Python/Python314/Scripts/nlm.exe" notebook list
```

### Criar notebook
```bash
PYTHONIOENCODING=utf-8 nlm notebook create "<nome do notebook>"
```

### Adicionar fonte local
```bash
PYTHONIOENCODING=utf-8 nlm source add <NOTEBOOK_ID> --file "<caminho absoluto do arquivo>" --wait
```

### Consultar notebook
```bash
PYTHONIOENCODING=utf-8 nlm query notebook <NOTEBOOK_ID> "<pergunta>"
```

### Autenticar
```bash
PYTHONIOENCODING=utf-8 nlm login
```
Requer interação no navegador. Credenciais salvas em `~/.notebooklm-mcp-cli/profiles/default`.

### Diagnóstico
```bash
PYTHONIOENCODING=utf-8 nlm doctor
```

## MCP tools (quando disponíveis na sessão)

Se os tools MCP estiverem carregados na sessão Claude Code, preferir:
- `mcp__notebooklm-mcp__notebook_list`
- `mcp__notebooklm-mcp__notebook_create`
- `mcp__notebooklm-mcp__source_add`
- `mcp__notebooklm-mcp__notebook_query`
- `mcp__notebooklm-mcp__server_info`

## Caminho fallback: skill local `notebooklm`

Localização: `~/.claude/skills/notebooklm/`

### Wrapper obrigatório
```bash
py -3 "C:/Users/<seu-usuario>/.claude/skills/notebooklm/scripts/run.py" <script> [args]
```

### Verificar auth
```bash
py -3 ".../scripts/run.py" auth_manager.py status
```

### Listar notebooks da biblioteca local
```bash
py -3 ".../scripts/run.py" notebook_manager.py list
```

### Consultar notebook
```bash
py -3 ".../scripts/run.py" ask_question.py --question "<pergunta>" --notebook-id <ID>
```

## Notas importantes sobre o ambiente

- No Windows com bash do Git, `python` pode não existir; usar `py -3`
- `nlm.exe` pode não estar no PATH; usar caminho absoluto quando necessário
- `PYTHONIOENCODING=utf-8` é necessário para evitar erros de encoding Unicode no Windows
- No PowerShell, a sintaxe muda: `$env:PYTHONIOENCODING="utf-8"; & nlm.exe ...`
- A configuração MCP global do Claude fica em `~/.claude.json` (não em `~/.claude/settings.json`)

## Smoke tests padrão

Perguntas baseline que podem ser adaptadas por projeto:
1. Qual o propósito principal deste sistema?
2. Quais os principais módulos ou áreas disponíveis?
3. O que o usuário final ou cliente consegue ver?
