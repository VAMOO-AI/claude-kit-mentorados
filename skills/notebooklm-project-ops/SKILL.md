---
name: notebooklm-project-ops
description: >-
  Use this skill to detect project documentation, validate NotebookLM infrastructure,
  create or sync a NotebookLM notebook from curated project docs, and record validation
  artifacts. Works across projects that follow the `.context/docs` + `docs/client-notebook/`
  convention. Triggers on phrases like "configure notebooklm", "create notebook",
  "sync notebooklm", "validate notebook", "notebooklm for this project".
---

# NotebookLM Project Ops

Operacionaliza o fluxo completo de NotebookLM em projetos: detectar documentação, validar infraestrutura, criar ou sincronizar notebook e registrar artefatos de manutenção.

## When to Use This Skill

Trigger when user:
- Wants to configure NotebookLM for a project
- Wants to create a client notebook or user manual in NotebookLM
- Wants to sync or update NotebookLM sources from project docs
- Wants to validate an existing NotebookLM notebook
- Uses phrases like "configure notebooklm", "create notebook", "sync notebooklm", "validate notebook", "notebooklm for this project", "manual do usuario no notebooklm"

Do NOT trigger when user just wants to query an existing notebook — use the `notebooklm` skill for that instead.

## Workflow Overview

```
1. Detect  → find project documentation structure
2. Build   → generate docs/client-notebook/ if missing (from .context/docs)
3. Check   → validate NotebookLM MCP/CLI and auth
4. Prepare → validate curated sources + manifest
5. Operate → create notebook or sync existing one
6. Validate → smoke tests against the notebook
7. Record  → update manifest, log and checklist
```

## Phase 1 — Detect Project Structure

Check the project for documentation layers:

```bash
# Check for technical docs
ls .context/docs/ 2>/dev/null

# Check for client-facing curated docs
ls docs/client-notebook/ 2>/dev/null

# Check for existing NotebookLM artifacts
ls docs/client-notebook/sources-manifest.md 2>/dev/null
ls docs/client-notebook/notebooklm-validation-log.md 2>/dev/null
```

### Scenario routing

| `.context/docs/` | `docs/client-notebook/` | Action |
|---|---|---|
| exists | exists | proceed to Phase 3 (Check Infra) |
| exists | missing | proceed to Phase 2 (Build client-facing layer) |
| missing | exists | proceed to Phase 3 (Check Infra) — use existing client docs |
| missing | missing | BLOCK — tell user documentation is needed before NotebookLM |
| any | any + notebook ID known | sync instead of create |

**If blocked (no docs at all):** explain clearly what is missing and stop.

## Phase 2 — Build Client-Facing Layer (when missing)

This phase runs ONLY when `.context/docs/` exists but `docs/client-notebook/` does not.

### Goal
Generate a curated, client-facing documentation layer derived from the technical docs, suitable for NotebookLM ingestion.

### How to generate
1. Read the technical docs in `.context/docs/` to understand the project
2. Create `docs/client-notebook/` with these files:

```
docs/client-notebook/
  README.md                    — index + editorial rules
  01-visao-geral.md            — product overview in simple language
  02-modulos-e-telas.md        — user-visible modules and screens
  03-fluxos-principais.md      — main operational workflows
  04-perfis-e-permissoes.md    — user roles in functional language
  05-integracoes-visiveis.md   — integrations the user can see
  06-faq.md                    — practical frequently asked questions
  07-glossario.md              — domain terms in plain language
  08-limites-e-boas-praticas.md — usage tips and limits
```

### Editorial rules for generated content
- Use simple language oriented to the end user/client
- Prioritize what is clearly central to the system's daily use
- Avoid absolute claims about administrative or less central modules
- Describe integrations only when there is visible effect for the user
- Standardize role/area names consistently (e.g. Secretaria, Mecanico)
- Never include database schemas, secrets, tokens, RLS policies, JWT details or internal implementation

### Adaptation for different projects
The file names and structure above are the default convention. If the project has a different documentation style, adapt the file names but keep the same editorial principles. The key requirement is: every file must be safe and useful for NotebookLM ingestion by a non-technical user.

### After generation
- Review the generated docs for tone and accuracy
- Proceed to Phase 3

---

## Phase 3 — Check Infrastructure

Validate NotebookLM tooling in this order:

```bash
# 1. Check MCP server
claude mcp get notebooklm-mcp

# 2. Check CLI availability
PYTHONIOENCODING=utf-8 nlm --help
# If nlm is not on PATH, use full path:
# "C:/Users/<seu-usuario>/AppData/Roaming/Python/Python314/Scripts/nlm.exe"

# 3. Check authentication
PYTHONIOENCODING=utf-8 nlm notebook list
```

**If MCP not connected:** direct user to run `claude mcp add -s user notebooklm-mcp -- <path-to-notebooklm-mcp.exe>`

**If auth missing:** direct user to run `nlm login` in their terminal (requires browser interaction).

**Fallback path:** if `nlm` / `notebooklm-mcp` is completely unavailable, check for the local skill at `~/.claude/skills/notebooklm/` and use its wrapper `py -3 scripts/run.py` as documented fallback.

See `references/commands.md` for exact command patterns.

## Phase 4 — Prepare Sources

1. List all `.md` files in `docs/client-notebook/` (excluding NotebookLM artifacts like `sources-manifest.md`, `notebooklm-validation-log.md`, `notebooklm-sync-checklist.md`, `notebooklm-setup-notes.md`, `notebooklm-integration-strategy.md`)
2. If `sources-manifest.md` exists, validate it matches the actual file set
3. If `sources-manifest.md` does not exist, generate it
4. Confirm the notebook name — check manifest first, then ask user if missing

### Manifest format

```md
# NotebookLM Source Manifest

## Notebook name
<exact notebook title>

## Source files
- docs/client-notebook/README.md
- docs/client-notebook/01-visao-geral.md
- ...

## Upload order
1. README
2. ...
```

## Phase 5 — Create or Sync

### If notebook does not exist yet

```bash
PYTHONIOENCODING=utf-8 nlm notebook create "<notebook name>"
# Capture the notebook ID from the output
PYTHONIOENCODING=utf-8 nlm notebook list
```

Then upload each source from the manifest in order:

```bash
PYTHONIOENCODING=utf-8 nlm source add <NOTEBOOK_ID> --file "<absolute-path>" --wait
```

### If notebook already exists

Re-upload sources from the manifest. The notebook ID should be in `notebooklm-validation-log.md` or can be found via:

```bash
PYTHONIOENCODING=utf-8 nlm notebook list
```

### MCP tool alternative

If the MCP tools are available in this session, prefer them over CLI:
- `mcp__notebooklm-mcp__notebook_create`
- `mcp__notebooklm-mcp__notebook_list`
- `mcp__notebooklm-mcp__source_add`
- `mcp__notebooklm-mcp__notebook_query`

## Phase 6 — Validate

Run 3 smoke-test questions against the notebook:

```bash
PYTHONIOENCODING=utf-8 nlm query notebook <NOTEBOOK_ID> "<question>"
```

Default baseline questions (adapt to project context):
1. What is the main purpose of this system?
2. What are the main modules or areas available?
3. What can the end user or client see?

Evaluate: answers should be grounded in the uploaded docs, not generic.

## Phase 7 — Record Artifacts

Create or update these files in `docs/client-notebook/`:

### `notebooklm-validation-log.md`
```md
# NotebookLM Validation Log

## Notebook
- Title: <name>
- Notebook ID: <id>

## Creation
- Status: created | synced
- Path used: nlm / notebooklm-mcp

## Source upload
- <filename>: ok | failed

## Smoke tests
- <question> → <short result>
```

### `notebooklm-sync-checklist.md`
```md
# NotebookLM Sync Checklist

1. Atualizar `.context/docs`
2. Atualizar `docs/client-notebook/`
3. Revisar o manifesto de fontes
4. Atualizar as fontes do notebook no NotebookLM
5. Fazer 3 perguntas de validação
6. Atualizar o log de validação
```

## Hard Rules

- Never invent notebook IDs
- Never upload files outside the curated `docs/client-notebook/` set
- Never upload files containing secrets, tokens, database schemas or internal configs
- Block only if NEITHER `.context/docs/` NOR `docs/client-notebook/` exists
- If `.context/docs/` exists but `docs/client-notebook/` is missing, generate the client-facing layer automatically (Phase 2)
- Prefer `nlm` / `notebooklm-mcp` over browser-only fallback
- Always register what was created, uploaded and validated in the project artifacts
- If auth fails, stop and direct the user to authenticate manually

## Fallback: Local NotebookLM Skill

If the primary path (`nlm` / `notebooklm-mcp`) is completely unavailable, the local skill at `~/.claude/skills/notebooklm` can be used for:
- querying an existing notebook
- manual validation

It cannot be used for:
- creating notebooks programmatically
- uploading local files as sources

See `references/troubleshooting.md` for failure recovery.

## Example Prompts

- "Configure NotebookLM for this project"
- "Create the client NotebookLM manual from docs/client-notebook"
- "Sync the NotebookLM sources for this project"
- "Validate the existing NotebookLM manual"
- "Update the NotebookLM notebook with the latest docs"
- "What is the notebook ID for this project?"

## References

- `references/workflow.md` — end-to-end operational flow with details
- `references/commands.md` — exact command patterns for primary and fallback paths
- `references/troubleshooting.md` — failure cases and recovery actions
- `references/project-detection.md` — detection scenarios and artifact checks
