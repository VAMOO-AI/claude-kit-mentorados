# Troubleshooting

Problemas comuns e ações de recuperação para a skill `notebooklm-project-ops`.

## Infraestrutura

### `notebooklm-mcp` não conectado
**Sintoma:** `claude mcp get notebooklm-mcp` retorna erro ou não encontrado.

**Ação:**
1. Verificar se `notebooklm-mcp-cli` está instalado: `py -m pip show notebooklm-mcp-cli`
2. Se não instalado: `py -m pip install --user notebooklm-mcp-cli`
3. Localizar o executável: tipicamente em `C:\Users\<user>\AppData\Roaming\Python\Python3XX\Scripts\notebooklm-mcp.exe`
4. Registrar no Claude: `claude mcp add -s user notebooklm-mcp -- "<caminho absoluto do executável>"`
5. Verificar: `claude mcp get notebooklm-mcp`

### `nlm` não encontrado no PATH
**Sintoma:** `nlm --help` retorna "command not found".

**Ação:** usar caminho absoluto do executável. Exemplo:
```bash
PYTHONIOENCODING=utf-8 "C:/Users/<seu-usuario>/AppData/Roaming/Python/Python314/Scripts/nlm.exe" --help
```

### Auth ausente ou expirada
**Sintoma:** `nlm notebook list` retorna "Profile 'default' not found" ou erro de auth.

**Ação:** o usuário precisa fazer login manualmente:
- No PowerShell: `$env:PYTHONIOENCODING="utf-8"; & nlm.exe login`
- No bash: `PYTHONIOENCODING=utf-8 nlm login`

Requer interação no navegador. A skill deve parar e pedir que o usuário complete o login.

### Login timeout
**Sintoma:** `nlm login` retorna "Error: Login timeout".

**Ação:** o usuário precisa completar o login no navegador mais rápido. Rodar de novo e fazer login imediatamente quando o browser abrir.

## Documentação do projeto

### `docs/client-notebook/` não existe
**Sintoma:** a skill detecta cenário B ou C.

**Ação:** BLOQUEAR. Informar que a camada client-facing precisa existir antes. Esta skill não gera documentação do zero.

### Manifesto desatualizado
**Sintoma:** `sources-manifest.md` lista arquivos que não existem mais, ou faltam arquivos novos.

**Ação:** regenerar o manifesto a partir do conjunto real de `.md` em `docs/client-notebook/`, excluindo arquivos de controle.

### Notebook ID perdido
**Sintoma:** `notebooklm-validation-log.md` não contém notebook ID, ou foi deletado.

**Ação:** listar notebooks com `nlm notebook list` e encontrar pelo título. Atualizar o log com o ID correto.

## Upload de fontes

### Upload falha com erro de auth
**Sintoma:** `nlm source add` retorna erro de autenticação durante upload.

**Ação:** re-autenticar com `nlm login` e tentar de novo.

### Upload falha com "file not found"
**Sintoma:** caminho do arquivo incorreto ou relativo.

**Ação:** sempre usar caminho absoluto nos uploads.

### Source count não bate
**Sintoma:** `nlm notebook list` mostra menos fontes do que as enviadas.

**Ação:** verificar quais fontes falharam no upload e reenviá-las individualmente.

## Windows-specific

### `python` não existe no bash
**Sintoma:** `/usr/bin/bash: python: command not found`

**Ação:** usar `py -3` no lugar de `python` para chamar scripts Python no Git Bash do Windows.

### Erros de Unicode no terminal
**Sintoma:** `UnicodeEncodeError` ao rodar `nlm` ou scripts Python.

**Ação:** sempre prefixar com `PYTHONIOENCODING=utf-8` no bash, ou `$env:PYTHONIOENCODING="utf-8"` no PowerShell.

### Configuração MCP global
**Sintoma:** editar `~/.claude/settings.json` com `mcpServers` é rejeitado pelo Claude Code.

**Ação:** a versão atual do Claude Code persiste MCP global via `claude mcp add -s user`, que grava em `~/.claude.json` (não em `~/.claude/settings.json`).

## Fallback

### Quando usar a skill local `notebooklm`
- `nlm` não está instalado e não pode ser instalado
- MCP `notebooklm-mcp` não pode ser configurado
- Usuário quer apenas consultar um notebook existente sem operar

### Limitações da skill local
- Não pode criar notebooks programaticamente
- Não pode fazer upload de arquivos locais
- Cada consulta abre e fecha um navegador
- Rate limit de ~50 queries/dia em contas Google gratuitas
