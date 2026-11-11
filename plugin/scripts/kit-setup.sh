#!/usr/bin/env bash
#
# Instala o que um plugin do Claude Code NÃO consegue declarar sozinho.
#
# Um plugin entrega skills, comandos, hooks e MCP. Mas o `settings.json` de
# plugin só aceita as chaves `agent` e `subagentStatusLine` — ou seja, ele não
# instala o CLAUDE.md global, a barra de status, o idioma nem a lista de
# permissões. É justamente o miolo do kit. Este script fecha esse buraco.
#
# Roda por dois caminhos e faz a mesma coisa nos dois:
#   • skill /kit-vamoo:setup  (depois do /plugin install)
#   • install.sh              (quem prefere o terminal)
#
#   bash kit-setup.sh              # instala
#   bash kit-setup.sh --dry-run    # mostra o que faria, não toca em nada
#   bash kit-setup.sh --force      # sobrescreve o CLAUDE.md que já existir e roda até por cima do kit do time
#   bash kit-setup.sh --statusline curto|painel   # barra de uma linha ou o painel de até 7
#   bash kit-setup.sh --sem-perguntas   # modo sem perguntas: bypass por padrão e só o gravíssimo pergunta
#   bash kit-setup.sh --com-perguntas   # desliga o modo: devolve as regras e o modo de antes
#
# Tudo que o script toca ganha cópia em ~/.claude/backup-kit-<data>/ antes; ficam
# os 3 backups mais recentes. O que você tem em ~/.claude e não quer ver removido
# vai em ~/.claude/.keep-local (um caminho por linha, relativo a ~/.claude, `#`
# comenta, glob simples: `skills/meu-*`). Protege contra remoção — o kit continua
# instalando e atualizando o que é dele.
#
set -euo pipefail

KIT_VERSION="0.93.0"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$PLUGIN_ROOT/templates"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backup-kit-$STAMP"
MANTER_BACKUPS=3
MANIFEST="$CLAUDE_DIR/.kit-manifest"
KEEP_LOCAL="$CLAUDE_DIR/.keep-local"
DRY=0
FORCE=0
SL_MODO=""
PERGUNTAS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --force)   FORCE=1 ;;
    --statusline)   SL_MODO="${2:-}"; [ $# -gt 1 ] && shift ;;
    --statusline=*) SL_MODO="${1#*=}" ;;
    --sem-perguntas|--com-perguntas)
      [ -n "$PERGUNTAS" ] && [ "$PERGUNTAS" != "${1#--}" ] && { echo "--sem-perguntas e --com-perguntas juntas: escolha uma" >&2; exit 2; }
      PERGUNTAS="${1#--}" ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "opção desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$SL_MODO" in
  ""|curto|painel) ;;
  *) echo "--statusline aceita curto|painel, não '$SL_MODO'" >&2; exit 2 ;;
esac

say()  { printf '\033[1;36m›\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$1"; }

run() { if [ "$DRY" -eq 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

# Máquina com o kit do time: o update.sh de lá grava o .team-manifest, e este script
# nunca grava. Rodar por cima tiraria o agents.md do time, poria o subagentes.md e a
# barra de status daqui e misturaria o settings.json dos dois kits — já aconteceu uma vez.
if [ -f "$CLAUDE_DIR/.team-manifest" ] && [ "$FORCE" -eq 0 ]; then
  warn "~/.claude é do kit do time: o setup dos mentorados tiraria o agents.md de lá, instalaria o subagentes.md e a statusline daqui e mexeria no settings. Nada feito."
  exit 0
fi

backup() {
  local alvo="$1"
  [ -e "$CLAUDE_DIR/$alvo" ] || return 0
  run mkdir -p "$BACKUP_DIR/$(dirname "$alvo")"
  run cp -R "$CLAUDE_DIR/$alvo" "$BACKUP_DIR/$alvo"
}

# protegido <caminho relativo a ~/.claude>: está no .keep-local?
# Cada linha do arquivo é um padrão de `case` (glob simples: * ? [..]); casa o
# caminho inteiro ou uma pasta acima dele — `skills/minha-skill` protege a skill,
# `skills/meu-*` protege todas as suas, `scripts` protege a pasta inteira.
protegido() {
  local rel="$1" linha pat
  [ -f "$KEEP_LOCAL" ] || return 1
  while IFS= read -r linha || [ -n "$linha" ]; do
    pat="${linha%%#*}"                       # comentário até o fim da linha
    pat="${pat#"${pat%%[![:space:]]*}"}"     # espaços à esquerda
    pat="${pat%"${pat##*[![:space:]]}"}"     # e à direita
    pat="${pat#./}"; pat="${pat%/}"
    [ -n "$pat" ] || continue
    # shellcheck disable=SC2254  # o glob é do usuário e tem que expandir
    case "$rel" in $pat|$pat/*) return 0 ;; esac
  done < "$KEEP_LOCAL"
  return 1
}

# O último componente do caminho existe com esta caixa exata? No APFS padrão do Mac e no
# NTFS, que não diferenciam maiúscula, `[ -e ]`, `cp` e `rm` em ~/.claude/agents.md também
# acertam um AGENTS.md que o kit nunca escreveu. O glob devolve o nome como está gravado.
nome_exato() {
  local e
  for e in "${1%/*}"/* "${1%/*}"/.*; do [ "${e##*/}" = "${1##*/}" ] && return 0; done
  return 1
}

# Cada execução cria um backup-kit-<data>; sem rotação, ~/.claude acumula um por
# atualização. O nome carrega a data (AAAAMMDD-HHMMSS), então ordem alfabética
# reversa é do mais novo pro mais velho — o desta execução está sempre no topo.
rotaciona_backups() {
  local d n=0 antigos
  # O `true` no fim do grupo importa: sem nenhum backup o glob não casa, o `for`
  # termina em 1 e, com set -e + pipefail, a atribuição derrubava o script — a
  # primeira instalação numa máquina limpa morria calada antes do "Pronto.".
  antigos="$({ for d in "$CLAUDE_DIR"/backup-kit-*/; do [ -d "$d" ] && printf '%s\n' "${d%/}"; done; true; } \
             | sort -r | tail -n +"$((MANTER_BACKUPS + 1))")"
  [ -n "$antigos" ] || return 0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    run rm -rf "$d"
    n=$((n + 1))
  done <<< "$antigos"
  say "$n backup(s) antigo(s) removido(s) — ficam os $MANTER_BACKUPS mais recentes"
  return 0
}

[ -d "$TPL" ] || { echo "não achei $TPL — o plugin está incompleto." >&2; exit 1; }
command -v node >/dev/null 2>&1 || {
  warn "node não encontrado — a barra de status e os hooks não funcionam sem ele."
  warn "  Instale o Node.js LTS: https://nodejs.org   (macOS: brew install node)"
}

[ "$DRY" -eq 1 ] && say "MODO DRY-RUN: nada será modificado."
say "Kit v$KIT_VERSION — completando a instalação em $CLAUDE_DIR"
run mkdir -p "$CLAUDE_DIR" "$CLAUDE_DIR/scripts"

# ── CLAUDE.md: é SEU arquivo. Não sobrescreve sem mandado explícito ──────────
INSTALOU_CLAUDE=0
if [ -f "$CLAUDE_DIR/CLAUDE.md" ] && [ "$FORCE" -eq 0 ]; then
  run cp "$TPL/CLAUDE-global.md" "$CLAUDE_DIR/CLAUDE.kit.md"
  warn "Você já tem um CLAUDE.md — não mexi nele."
  warn "  O modelo do kit ficou em ~/.claude/CLAUDE.kit.md pra você comparar."
  warn "  Pra trocar pelo do kit: bash kit-setup.sh --force"
  # O nome antigo das regras de subagente ficou para trás no CLAUDE.md da pessoa. O
  # arquivo é dela: o setup aponta, não edita. Sem -i: AGENTS.md no texto é o do projeto.
  if grep -q 'agents\.md' "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
    warn "  Ele ainda cita agents.md: as regras de subagente agora ficam em ~/.claude/subagentes.md."
  fi
  # O MCP do dotcontext saiu do plugin na 0.56.0; o CLAUDE.md de quem instalou antes
  # continua mandando pedir "init the context". Mesmo trato do agents.md: aponta, não edita.
  if grep -qiE 'init the context|dotcontext' "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
    warn "  Ele ainda manda usar o dotcontext (\"init the context\"), que saiu do kit: troque a seção pela \"Projeto: memória, instruções e fluxo\" do CLAUDE.kit.md."
  fi
else
  backup "CLAUDE.md"
  run cp "$TPL/CLAUDE-global.md" "$CLAUDE_DIR/CLAUDE.md"
  ok "CLAUDE.md instalado  (preencha os <campos> com os seus dados)"
  INSTALOU_CLAUDE=1
fi

# ── MCP do dotcontext: saiu do kit na 0.56.0, mas o install.sh de antes de 24/08/2026 o
# registrou no escopo de usuário (~/.claude.json). Ele sobe um processo node por sessão e
# lê arquivo fora do deny de .env*, que não vale para tool de MCP (#239). Só chama o
# `claude` quando o registro existe, para o setup não depender do CLI.
if [ -f "$HOME/.claude.json" ] && node -e 'process.exit((((require(process.argv[1])||{}).mcpServers)||{}).dotcontext ? 0 : 1)' "$HOME/.claude.json" 2>/dev/null; then
  if command -v claude >/dev/null 2>&1; then
    run claude mcp remove dotcontext --scope user
    ok "MCP do dotcontext removido do escopo de usuário (saiu do kit na 0.56.0)"
  else
    warn "O MCP do dotcontext ainda está registrado e o comando claude não está no PATH: rode claude mcp remove dotcontext --scope user"
  fi
fi

# ── Regras dos subagentes: subagentes.md ────────────────────────────────────
# O nome antigo, agents.md, em disco que não diferencia maiúscula (macOS, Windows) é o
# ~/.claude/AGENTS.md que o Claude Code lê em toda sessão: as regras de subagente
# entravam em toda conversa. Ele sai com backup; o .keep-local segura, como segura
# qualquer remoção. Os dois nomes contam, porque no disco é um arquivo só. Sai o que está
# gravado como `agents.md`, o nome que o setup instalava, e o AGENTS.md com a linha-assinatura
# do template antigo (setup antigo gravou por cima de um AGENTS.md que já existia). Sem
# ela, o AGENTS.md é de outra ferramenta ou escrito pela pessoa, e fica.
# A cópia vai para backup-agents-md/, fora da rotação dos backup-kit-*: três setups
# depois ela ainda está lá.
ASSINATURA_AGENTS='Fica em `~/.claude/agents.md`'
tira_agents_antigo() { # <nome gravado no disco> <motivo>
  local nome="$1" dest="$CLAUDE_DIR/backup-agents-md/agents-$STAMP.md"
  if [ "$DRY" -eq 1 ]; then
    echo "  [dry-run] removeria ~/.claude/$nome ($2), com cópia em $dest"
    return 0
  fi
  mkdir -p "$CLAUDE_DIR/backup-agents-md"
  cp "$CLAUDE_DIR/$nome" "$dest"
  rm -f "$CLAUDE_DIR/$nome"
  ok "$nome antigo removido ($2) — as regras agora ficam em subagentes.md; cópia em $dest"
}
backup "subagentes.md"
run cp "$TPL/subagentes.md" "$CLAUDE_DIR/subagentes.md"
ok "subagentes.md instalado"
if [ -e "$CLAUDE_DIR/agents.md" ]; then
  outro="agents.md"
  nome_exato "$CLAUDE_DIR/agents.md" || outro="$(ls -A "$CLAUDE_DIR" | grep -Fxi -- agents.md | head -n 1 || true)"
  if protegido "agents.md" || protegido "AGENTS.md"; then
    warn "mantido (está no .keep-local): ${outro:-agents.md} — em disco que não diferencia maiúscula, o Claude Code o lê como AGENTS.md em toda sessão."
  elif [ "$outro" = "agents.md" ]; then
    tira_agents_antigo "agents.md" "o nome que o setup instalava"
  elif [ -n "$outro" ] && grep -qF -- "$ASSINATURA_AGENTS" "$CLAUDE_DIR/$outro" 2>/dev/null; then
    tira_agents_antigo "$outro" "é o template de um setup antigo do kit, com a linha 'Fica em ~/.claude/agents.md'"
  elif [ "$DRY" -eq 1 ]; then
    # O arquivo é da pessoa: fora do dry-run, nada a dizer sobre ele.
    echo "  [dry-run] manteria ~/.claude/${outro:-AGENTS.md}: não foi instalado pelo kit (não tem a linha 'Fica em ~/.claude/agents.md' do template antigo)."
  fi
fi

# ── Barra de status ─────────────────────────────────────────────────────────
# Cópia, não link: a barra continua funcionando quando o plugin for atualizado
# ou movido. Rodar o setup de novo atualiza a cópia.
# O modo (painel de até 7 linhas ou a linha única) é ~/.claude/statusline-modo. Sem a
# opção, instalação nova fica no painel sem gravar nada; quem já tinha a barra e nunca
# escolheu ganha `curto`, a barra de antes. Escolha gravada fica.
if [ -n "$SL_MODO" ]; then
  [ "$DRY" -eq 1 ] && echo "  [dry-run] gravaria ~/.claude/statusline-modo = $SL_MODO" || printf '%s\n' "$SL_MODO" > "$CLAUDE_DIR/statusline-modo"
elif [ ! -e "$CLAUDE_DIR/statusline-modo" ] && [ -f "$CLAUDE_DIR/scripts/statusline.js" ]; then
  [ "$DRY" -eq 1 ] && echo "  [dry-run] gravaria ~/.claude/statusline-modo = curto (a barra de antes)" || printf 'curto\n' > "$CLAUDE_DIR/statusline-modo"
fi
backup "statusline-command.sh"
run cp "$TPL/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
run chmod +x "$CLAUDE_DIR/statusline-command.sh"
backup "scripts/statusline.js"
run cp "$PLUGIN_ROOT/scripts/statusline.js" "$CLAUDE_DIR/scripts/statusline.js"
run cp "$PLUGIN_ROOT/scripts/hookjson.js" "$CLAUDE_DIR/scripts/hookjson.js"
run cp "$PLUGIN_ROOT/scripts/merge-settings.js" "$CLAUDE_DIR/scripts/merge-settings.js"

# Workflows: o Claude Code carrega a pasta workflows/ do plugin sozinho (vira
# /kit-vamoo:<nome>). Até a 0.90 este passo copiava cada um para ~/.claude/workflows/, e o
# mesmo workflow aparecia duas vezes na lista. Agora o setup só tira a cópia que ele mesmo
# punha: a que é igual, byte a byte, à do plugin. Arquivo diferente é edição da pessoa ou
# cópia de versão antiga, e fica com aviso.
for w in "$PLUGIN_ROOT/workflows"/*.js; do
  [ -e "$w" ] || continue
  n="$(basename "$w")"
  [ -f "$CLAUDE_DIR/workflows/$n" ] || continue
  if protegido "workflows/$n"; then warn "mantido (está no .keep-local): workflows/$n"; continue; fi
  if cmp -s "$w" "$CLAUDE_DIR/workflows/$n"; then
    backup "workflows/$n"; run rm -f "$CLAUDE_DIR/workflows/$n"
    if [ "$DRY" -eq 1 ]; then ok "removeria a cópia duplicada workflows/$n (o plugin já entrega /kit-vamoo:${n%.js})"
    else ok "cópia duplicada workflows/$n removida — o plugin já entrega /kit-vamoo:${n%.js}"; fi
  else
    warn "workflows/$n difere do que o plugin entrega e ficou: ele aparece em dobro com /kit-vamoo:${n%.js}. Se não é edição sua, apague ~/.claude/workflows/$n."
  fi
done
ok "barra de status instalada (diretório, branch, ↑↓, gh, PR, contexto)"

# ── settings.json: MESCLA, nunca sobrescreve ────────────────────────────────
# O instalador antigo sobrescrevia e quem tinha permissions/env customizados
# perdia tudo com um aviso fácil de não ver. Agora as suas chaves ganham: o kit
# só preenche o que está faltando, e a lista `allow` é a união das duas.
#
# Modo sem perguntas: quem liga com --sem-perguntas quer trabalhar sem prompt de permissão. A
# escolha é o arquivo ~/.claude/kit-vamoo/sem-perguntas (mesma pasta dos manter-modo-manual e
# manter-accept-edits), que este script lê a cada rodada, e sai com --com-perguntas. O modo faz
# três coisas:
#   1. o modo de permissão padrão vira bypassPermissions ("Ignorar permissões"). Até a 0.93.0
#      ele ficava como estava, e quem estava no Auto, ou no Manual por não ter Auto na conta,
#      seguia vendo "Permitir" em `gh pr merge` (pedido do Ruan de 11/11/2026);
#   2. as regras `ask` de COMANDO do kit saem e não voltam nas atualizações: regra `ask`
#      pergunta em qualquer modo, bypass incluso, e a união devolvia as do kit a cada setup;
#   3. o hook check-careful, que lê o mesmo marcador, pergunta só o gravíssimo.
# As regras deny não mudam. O marcador guarda, uma chave por linha, o que o --com-perguntas
# precisa para desfazer só o que o setup fez:
#   modo=bypass          o setup já pôs o bypass uma vez. Marcador sem a linha é da 0.93.0 e
#                        migra: o setup seguinte põe o bypass. Com a linha, um setup comum só
#                        troca Manual, modo ausente e Accept edits; quem passou para o Auto
#                        na mão fica nele;
#   modo_anterior=<modo> o modo que o setup trocou pelo bypass (vazio = não havia);
#   skip_do_kit=1        foi o setup que pôs o skipDangerousModePermissionPrompt.
SEM_PERG_MARCA="$CLAUDE_DIR/kit-vamoo/sem-perguntas"
marca_valor() { # <chave> → valor da linha chave=valor do marcador ("" se não há)
  local l
  [ -f "$SEM_PERG_MARCA" ] || return 0
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"
    case "$l" in "$1="*) printf '%s' "${l#*=}"; return 0 ;; esac
  done < "$SEM_PERG_MARCA"
  return 0
}
marca_tem() { # <chave>: o marcador tem a linha chave=...?
  local l
  [ -f "$SEM_PERG_MARCA" ] || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in "$1="*) return 0 ;; esac
  done < "$SEM_PERG_MARCA"
  return 1
}
marca_poe() { # <chave> <valor>: troca (ou acrescenta) a linha chave=valor do marcador
  local l novo=""
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"
    case "$l" in "$1="*) ;; *) novo="$novo$l"$'\n' ;; esac
  done < "$SEM_PERG_MARCA"
  printf '%s%s=%s\n' "$novo" "$1" "$2" > "$SEM_PERG_MARCA"
}
# "<defaultMode>|<1 se o skipDangerousModePermissionPrompt está definido>" do settings.json de
# agora. O arquivo chega pelo stdin, aberto pelo bash: no Git Bash o node é nativo do Windows
# e não acha o caminho do MSYS passado por argumento.
estado_settings() {
  if [ -f "$CLAUDE_DIR/settings.json" ] && command -v node >/dev/null 2>&1; then
    node -e 'let s = {}; try { s = JSON.parse(require("fs").readFileSync(0, "utf8")) || {}; } catch (e) {}
const p = s.permissions || {};
process.stdout.write((p.defaultMode || "") + "|" + (s.skipDangerousModePermissionPrompt !== undefined ? 1 : 0));' \
      < "$CLAUDE_DIR/settings.json" 2>/dev/null || printf '|0'
  else
    printf '|0'
  fi
}
SEM_PERG=0
MODO_BYPASS=""     # "", kit (--modo-bypass) ou forcar (--modo-bypass=forcar)
SAI_BYPASS=""      # a flag --sai-do-bypass=<modo de antes>, no --com-perguntas
TIRA_SKIP=0
if [ -f "$SEM_PERG_MARCA" ]; then
  SEM_PERG=1
  if marca_tem modo; then MODO_BYPASS=kit; else MODO_BYPASS=forcar; fi
fi
case "$PERGUNTAS" in
  sem-perguntas)
    SEM_PERG=1; MODO_BYPASS=forcar
    if [ "$DRY" -eq 1 ]; then echo "  [dry-run] ligaria o modo sem perguntas (gravaria ~/.claude/kit-vamoo/sem-perguntas e poria o modo de permissão em bypassPermissions)"
    elif [ ! -f "$SEM_PERG_MARCA" ]; then mkdir -p "$CLAUDE_DIR/kit-vamoo"; printf 'ligado em %s pelo kit-setup.sh --sem-perguntas\n' "$STAMP" > "$SEM_PERG_MARCA"; fi ;;
  com-perguntas)
    if marca_tem modo_anterior; then SAI_BYPASS="--sai-do-bypass=$(marca_valor modo_anterior)"; fi
    [ "$(marca_valor skip_do_kit)" = 1 ] && TIRA_SKIP=1
    SEM_PERG=0; MODO_BYPASS=""
    if [ "$DRY" -eq 1 ]; then echo "  [dry-run] desligaria o modo sem perguntas (apagaria ~/.claude/kit-vamoo/sem-perguntas e devolveria o modo de permissão de antes)"
    else rm -f "$SEM_PERG_MARCA"; fi ;;
esac
backup "settings.json"
if [ "$DRY" -eq 1 ]; then
  echo "  [dry-run] mesclaria $TPL/settings.json em $CLAUDE_DIR/settings.json"
  [ "$SEM_PERG" -eq 1 ] && echo "  [dry-run] modo sem perguntas: tiraria as regras ask de comando do kit (deny não muda)"
  [ "$MODO_BYPASS" = forcar ] && echo "  [dry-run] modo sem perguntas: poria permissions.defaultMode em bypassPermissions (Ignorar permissões)"
elif command -v node >/dev/null 2>&1; then
  MERGE_ARGS=()
  [ "$SEM_PERG" -eq 1 ] && MERGE_ARGS+=(--sem-ask-de-comando)
  case "$MODO_BYPASS" in
    kit)    MERGE_ARGS+=(--modo-bypass) ;;
    forcar) MERGE_ARGS+=(--modo-bypass=forcar) ;;
  esac
  [ -n "$SAI_BYPASS" ] && MERGE_ARGS+=("$SAI_BYPASS")
  [ "$TIRA_SKIP" -eq 1 ] && MERGE_ARGS+=(--tira-skip)
  ANTES="$(estado_settings)"
  node "$PLUGIN_ROOT/scripts/merge-settings.js" "$TPL/settings.json" "$CLAUDE_DIR/settings.json" ${MERGE_ARGS[@]+"${MERGE_ARGS[@]}"}
  if [ "$SEM_PERG" -eq 1 ] && [ -f "$SEM_PERG_MARCA" ]; then
    DEPOIS="$(estado_settings)"
    if [ "${DEPOIS%%|*}" = bypassPermissions ] && [ "${ANTES%%|*}" != bypassPermissions ]; then
      marca_poe modo_anterior "${ANTES%%|*}"
    fi
    if [ "${ANTES##*|}" = 0 ] && [ "${DEPOIS##*|}" = 1 ]; then marca_poe skip_do_kit 1; fi
    marca_tem modo || marca_poe modo bypass
  fi
  ok "settings.json mesclado (as suas chaves foram preservadas)"
  [ "$PERGUNTAS" = com-perguntas ] && ok "modo sem perguntas desligado: as regras ask de comando do kit voltaram"
else
  warn "sem node — não deu pra mesclar o settings.json. Modelo em $TPL/settings.json"
fi
run rm -f "$CLAUDE_DIR/settings.kit.json"

# ── Fantasmas: o que o kit antigo espalhou em ~/.claude e agora vem do plugin ─
# Sem isso o aluno fica com a skill duas vezes (a de ~/.claude e a do plugin) e
# com o hook rodando em dobro — inclusive a versão velha, já corrigida.
if [ -f "$MANIFEST" ]; then
  say "Removendo o que a instalação antiga deixou (agora vem do plugin)…"
  n=0; m=0
  while IFS= read -r linha; do
    case "$linha" in
      skill/*)   rel="skills/${linha#skill/}" ;;
      hook/*)    rel="hooks/${linha#hook/}" ;;
      command/*) rel="commands/${linha#command/}" ;;
      script/*)
        # statusline.js e hookjson.js continuam em ~/.claude — são deste script.
        nome="${linha#script/}"
        case "$nome" in statusline.js|hookjson.js) continue ;; esac
        rel="scripts/$nome" ;;
      *) continue ;;
    esac
    [ -e "$CLAUDE_DIR/$rel" ] || continue
    # O manifesto lista o que o instalador antigo copiou, mas quem editou a
    # cópia (ou tem algo com o mesmo nome) perde trabalho seu. O .keep-local
    # é a palavra final: o que está lá fica.
    if protegido "$rel"; then
      warn "mantido (está no .keep-local): $rel"
      m=$((m + 1))
      continue
    fi
    backup "$rel"
    run rm -rf "$CLAUDE_DIR/$rel"
    n=$((n + 1))
  done < "$MANIFEST"
  [ "$DRY" -eq 0 ] && rm -f "$MANIFEST"
  ok "$n item(ns) da instalação antiga removido(s) (cópia no backup)"
  [ "$m" -gt 0 ] && ok "$m item(ns) mantido(s) pelo ~/.claude/.keep-local"
fi

rotaciona_backups

echo
if [ "$DRY" -eq 1 ]; then ok "Dry-run concluído — nada foi modificado."; exit 0; fi
if [ "$SEM_PERG" -eq 0 ]; then
  say "Modo de permissão: quem estava no Manual ou no Accept edits passa para \"Auto\" (auto) — um classificador revisa cada comando no lugar do \"Permitir\"; force push, reset --hard e afins continuam pedindo. bypass e plan ficam."
  say "  Sem Auto disponível na sua conta ou no modelo, o Claude Code abre em Manual: não é o setup que falhou."
  say "  No app de desktop o seletor de modo (ao lado do botão de enviar) vence o settings.json e é lembrado por pasta:"
  say "  se ele mostrar \"Manual\" (ou \"Ask permissions\" em versão antiga), troque uma vez para \"Auto\" em cada pasta onde escolheu Manual."
  say "  Quer o manual de vez? Crie ~/.claude/kit-vamoo/manter-modo-manual e o setup não troca mais o seu modo."
  say "  Quer ficar no Accept edits? Crie ~/.claude/kit-vamoo/manter-accept-edits e ponha permissions.defaultMode em \"acceptEdits\"."
else
  MODO_FINAL="$(estado_settings)"; MODO_FINAL="${MODO_FINAL%%|*}"
  warn "Modo sem perguntas LIGADO (~/.claude/kit-vamoo/sem-perguntas)."
  if [ "$MODO_FINAL" = bypassPermissions ]; then
    warn "  Modo de permissão padrão: bypassPermissions (\"Ignorar permissões\" / Bypass permissions). O Claude Code roda os comandos sem pedir \"Permitir\"."
    warn "  No app de desktop o arquivo não basta, e são dois passos, uma vez:"
    warn "    1. Settings > Code > ligue \"Allow bypass permissions mode\" (em plano Team ou Enterprise quem libera é a organização);"
    warn "    2. no seletor de modo ao lado do botão de enviar, escolha \"Ignorar permissões\" em cada pasta onde já tinha outro modo:"
    warn "       o seletor é lembrado por pasta e vence o settings.json."
  else
    warn "  O modo de permissão do settings.json está em \"${MODO_FINAL:-nenhum}\", não em bypass (veja acima o que segurou):"
    warn "  fora do bypass o Claude Code segue revisando cada comando e pede \"Permitir\" no que não está no allow."
  fi
  warn "  Deixa de pedir confirmação: git push --force, --delete, --mirror e --all em branch que não é a main; push direto na main;"
  warn "  git reset --hard; git clean; git branch -D; checkout -f; checkout -- .; switch --discard-changes; restore .; stash drop/clear;"
  warn "  worktree remove --force; gh pr merge; gh release delete; supabase secrets set/unset; supabase migration repair;"
  warn "  find -delete/-exec; Remove-Item -Recurse e rm -r de pasta de dentro do projeto; git add -A; DDL (CREATE/ALTER TABLE);"
  warn "  listar variáveis de ambiente (env, printenv) e comando que cita .pem, chave SSH ou credencial (.aws, .npmrc, .netrc)."
  warn "  Ainda pergunta, em qualquer modo, porque não tem volta: rm -r fora do projeto (ou do projeto inteiro e do .git dele),"
  warn "  DROP/TRUNCATE sendo executado, supabase db reset no banco remoto, gh repo delete e comando de rede que leva credencial para fora."
  warn "  Continua barrado pelas regras deny: force push na main, supabase db push, login do Supabase e da Vercel, leitura de .env,"
  warn "  rm -rf em / e na sua pasta de usuário."
  warn "  Continuam valendo: o hook que bloqueia commit direto na main (o Claude cria a branch e segue, sem perguntar), as regras ask"
  warn "  de conector e as ask que você mesmo escreveu."
  warn "  Pra voltar a ser perguntado: /kit-vamoo:setup --com-perguntas (ou bash kit-setup.sh --com-perguntas)."
fi
ok "Pronto."
[ -d "$BACKUP_DIR" ] && say "Seus arquivos antigos: $BACKUP_DIR"
if [ "$INSTALOU_CLAUDE" -eq 1 ]; then
  say "Agora abra ~/.claude/CLAUDE.md e preencha os campos <entre-colchetes>."
else
  say "Seu CLAUDE.md ficou como estava; o do kit está em ~/.claude/CLAUDE.kit.md para comparar."
fi
say "Reinicie o Claude Code pra barra de status aparecer."
