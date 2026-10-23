#!/usr/bin/env bash
# codex-optimize.sh — aplica em ~/.codex as otimizações de custo e latência do kit.
# Porte do kit do time (F5 do núcleo único, #241). Precisa de python3 (edita o config.toml).
#
#   bash codex-optimize.sh              # diagnóstico: mostra o que está fora do padrão
#   bash codex-optimize.sh --apply      # aplica (backup antes de cada escrita)
#
# O que faz:
#   1. Cria os perfis review/max (`codex -p review`, `codex -p max`)
#   2. Baixa model_reasoning_effort de "max" para "high" no config base
#   3. Lista plugins ligados e desliga os que não são de dev (--apply)
#   4. Aponta skills do time que estejam com enabled = false
#   5. Instala e registra os guards de git do kit (antes do RTK)
#   6. Instala o hook do RTK (se o rtk estiver no PATH)
#
# Por que isso importa: cada plugin ligado ocupa o orçamento de contexto que o Codex
# reserva para descrições de skill. Com 20 plugins ele TRUNCA as descrições das suas
# skills e passa a rotear mal. Medido numa máquina do time: 21.946 → 10.434 tokens de
# contexto base (-52%) só desligando o que não se usa de dentro do CLI.
#
# Idempotente: rodar duas vezes não duplica nada.
set -uo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1
# python3 lê e edita o config.toml (tomllib, 3.11+). Não é pré-requisito do kit: sem ele, o
# script diz o que falta e sai sem tocar em nada.
command -v python3 >/dev/null 2>&1 || { echo "codex-optimize precisa de python3 (3.11 ou mais novo). Instale e rode de novo."; exit 2; }

STAMP="$(date +%Y%m%d-%H%M%S)"
say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; }
todo() { printf '  → %s\n' "$*"; }

[ -d "$CODEX_HOME" ] || { echo "✗ não achei $CODEX_HOME — o Codex CLI está instalado?"; exit 1; }
CONFIG="$CODEX_HOME/config.toml"
[ -f "$CONFIG" ] || { echo "✗ não achei $CONFIG"; exit 1; }

[ "$APPLY" = 0 ] && say "MODO DIAGNÓSTICO — nada será alterado (use --apply)"

# ---------------------------------------------------------------- 1. perfis
say "1. Perfis de reasoning effort"
write_profile() {
  local nome="$1" corpo="$2" alvo="$CODEX_HOME/$1.config.toml"
  if [ -f "$alvo" ]; then ok "$nome.config.toml já existe"; return; fi
  if [ "$APPLY" = 1 ]; then printf '%s' "$corpo" > "$alvo"; ok "criado $nome.config.toml"
  else todo "criaria $nome.config.toml"; fi
}
write_profile review '# Revisor: high, sem memories, sem subagente. Uso: codex -p review ...
model_reasoning_effort = "high"

[features]
memories = false
multi_agent = false

[memories]
generate_memories = false
use_memories = false
'
write_profile max '# Effort máximo sob demanda. Uso: codex -p max ...
# Só para arquitetura difícil de reverter ou debug que já resistiu a 2 tentativas.
model_reasoning_effort = "max"
'

# ------------------------------------------------------- 2. effort do config base
say "2. Effort default do config base"
EFFORT="$(grep -m1 '^model_reasoning_effort' "$CONFIG" | sed 's/.*= *"\(.*\)"/\1/')"
if [ "$EFFORT" = "max" ]; then
  if [ "$APPLY" = 1 ]; then
    cp "$CONFIG" "$CONFIG.bak-$STAMP"
    python3 - "$CONFIG" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
open(p,'w').write(s.replace('model_reasoning_effort = "max"', 'model_reasoning_effort = "high"', 1))
PY
    ok "max → high (backup em config.toml.bak-$STAMP)"
  else
    todo "está em \"max\" — baixaria para \"high\" (use -p max quando precisar do antigo)"
  fi
else
  ok "já está em \"${EFFORT:-?}\""
fi

# ------------------------------------------------------------------ 3. plugins
say "3. Plugins ligados"
DEV_KEEP="github codex-security frontend-design hostinger chrome computer-use"
LIGADOS="$(python3 - "$CONFIG" <<'PY'
import tomllib, sys
d = tomllib.load(open(sys.argv[1],'rb'))
print('\n'.join(k for k,v in d.get('plugins',{}).items() if v.get('enabled')))
PY
)"
N=$(printf '%s' "$LIGADOS" | grep -c . || true)
echo "  $N ligado(s)"
DESLIGAR=""
while IFS= read -r p; do
  [ -z "$p" ] && continue
  base="${p%%@*}"
  case " $DEV_KEEP " in *" $base "*) ok "mantém  $p" ;; *) DESLIGAR="$DESLIGAR $p"; warn "desliga $p" ;; esac
done <<< "$LIGADOS"

if [ -n "$DESLIGAR" ]; then
  if [ "$APPLY" = 1 ]; then
    [ -f "$CONFIG.bak-$STAMP" ] || cp "$CONFIG" "$CONFIG.bak-$STAMP"
    python3 - "$CONFIG" $DESLIGAR <<'PY'
import re, sys
p, nomes = sys.argv[1], sys.argv[2:]
s = open(p).read()
for n in nomes:
    s = re.sub(r'(\[plugins\."' + re.escape(n) + r'"\]\nenabled = )true', r'\1false', s)
open(p,'w').write(s)
PY
    ok "desligados (backup em config.toml.bak-$STAMP)"
  else
    todo "rode com --apply para desligar os marcados acima"
  fi
  echo "  (para religar: enabled = true no bloco [plugins.\"<nome>\"] do config.toml)"
fi

# ------------------------------------------------------------------- 4. skills
say "4. Skills do time no Codex"
python3 - "$CONFIG" <<'PY'
import tomllib, sys
d = tomllib.load(open(sys.argv[1],'rb'))
cfg = d.get('skills',{}).get('config',[])
# Skill de plugin entra por `name`, sem `path` (ex.: name = "kit-vamoo:source-command-explicar").
off = [s.get('path') or s.get('name') or '(sem path nem name)' for s in cfg if not s.get('enabled')]
if not cfg:
    print("  (nenhuma skill registrada — o Codex descobre pelas pastas padrão)")
elif off:
    print(f"  ⚠ {len(off)} skill(s) com enabled = false:")
    for p in off: print("     ", p)
    print("  → ligue no ~/.codex/config.toml se você usa essas regras")
else:
    print(f"  ✓ todas as {len(cfg)} registradas estão ligadas")
PY

# ------------------------------------------------------------- 5. guards de git
# Este Mac roda o Codex com aprovação ampla: o guard é a única barreira (#315). Os guards
# leem o comando em array e o tool_input.workdir do Codex. Entram ANTES do rtk-codex,
# porque o rtk reescreve o comando e o guard tem que ver o original.
# Fica de fora o block-cd-leitura-relativa: ele existe por uma escalada de permissão do
# Claude Code (`cd X && cat rel` com regra Read() no deny), que o Codex não tem.
# O block-parallel-clone-switch só enxerga sessões Claude: quem escreve o marcador em
# repo-sessions é o repo-session.sh do Claude Code, e a sessão Codex não se registra.
say "5. Guards de git do kit"
GUARDS="block-main-commit.sh check-careful.sh block-parallel-clone-switch.sh block-delete-branch-with-children.sh"
# A fonte é a pasta de hooks do plugin; fora dele, o ~/.claude/hooks de quem instalou à mão.
# O guard copiado para ~/.codex/hooks lê o payload pelo ../scripts/hookjson.js: ele vai junto.
GSRC="$(cd "$(dirname "$0")/../hooks" 2>/dev/null && pwd)"
[ -f "$GSRC/block-main-commit.sh" ] || GSRC="$HOME/.claude/hooks"
HJ="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/hookjson.js"
[ -f "$HJ" ] || HJ="$HOME/.claude/scripts/hookjson.js"
FALTAM=""
for g in $GUARDS; do
  [ -f "$GSRC/$g" ] || { warn "não achei $g em $GSRC"; continue; }
  if [ -f "$CODEX_HOME/hooks.json" ] && grep -q "$g" "$CODEX_HOME/hooks.json" && [ -f "$CODEX_HOME/hooks/$g" ]; then
    ok "$g registrado"
  else
    FALTAM="$FALTAM $g"; warn "$g fora do Codex"
  fi
done
if [ -n "$FALTAM" ]; then
  if [ "$APPLY" = 1 ]; then
    mkdir -p "$CODEX_HOME/hooks"
    [ -f "$CODEX_HOME/hooks.json" ] && cp "$CODEX_HOME/hooks.json" "$CODEX_HOME/hooks.json.bak-$STAMP"
    for g in $FALTAM; do cp "$GSRC/$g" "$CODEX_HOME/hooks/$g"; chmod +x "$CODEX_HOME/hooks/$g"; done
    [ -f "$HJ" ] && mkdir -p "$CODEX_HOME/scripts" && cp "$HJ" "$CODEX_HOME/scripts/hookjson.js"
    python3 - "$CODEX_HOME/hooks.json" "$CODEX_HOME/hooks" $FALTAM <<'PY'
import json, os, sys
p, pasta, novos = sys.argv[1], sys.argv[2], sys.argv[3:]
d = json.load(open(p)) if os.path.exists(p) else {"hooks": {}}
grupos = d.setdefault('hooks', {}).setdefault('PreToolUse', [])
alvo = next((g for g in grupos if g.get('matcher') == 'Bash'), None)
if alvo is None:
    alvo = {"matcher": "Bash", "hooks": []}; grupos.append(alvo)
lista = alvo['hooks']
for g in novos:
    if any(g in h.get('command', '') for h in lista):
        continue
    f = os.path.join(pasta, g)
    # o exit 2 do guard tem que chegar ao Codex: `; exit 0` no fim jogaria o bloqueio fora
    cmd = f"if [ -f '{f}' ]; then bash '{f}'; exit $?; fi; exit 0"
    rtk = next((i for i, h in enumerate(lista) if 'rtk-codex' in h.get('command', '')), None)
    lista.insert(len(lista) if rtk is None else rtk, {"type": "command", "command": cmd})
json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
print("  ✓ registrados no hooks.json, antes do rtk-codex")
PY
    echo "  → ABRA 'codex' no TUI uma vez e APROVE cada hook novo."
    echo "    Sem trust o Codex os ignora em SILÊNCIO, e o guard não bloqueia nada."
  else
    todo "instalaria e registraria:$FALTAM (antes do rtk-codex)"
  fi
fi

# ---------------------------------------------------------------------- 6. RTK
say "6. Hook do RTK (opcional)"
if ! command -v rtk >/dev/null 2>&1; then
  ok "rtk não instalado — pulando"
else
  HOOK="$CODEX_HOME/hooks/rtk-codex.sh"
  SRC="$(dirname "$0")/../hooks/rtk-codex.sh"
  [ -f "$SRC" ] || SRC="$HOME/.claude/hooks/rtk-codex.sh"
  if [ ! -f "$SRC" ]; then
    warn "não achei o rtk-codex.sh para copiar"
  elif [ "$APPLY" = 1 ]; then
    mkdir -p "$CODEX_HOME/hooks"; cp "$SRC" "$HOOK"; chmod +x "$HOOK"
    python3 - "$CODEX_HOME/hooks.json" "$HOOK" <<'PY'
import json, os, sys
p, hook = sys.argv[1], sys.argv[2]
d = json.load(open(p)) if os.path.exists(p) else {"hooks": {}}
grupos = d.setdefault('hooks', {}).setdefault('PreToolUse', [])
alvo = next((g for g in grupos if g.get('matcher') == 'Bash'), None)
if alvo is None:
    alvo = {"matcher": "Bash", "hooks": []}; grupos.append(alvo)
cmd = f"bash '{hook}'"
# por ÚLTIMO: os hooks de segurança avaliam o comando ORIGINAL antes da reescrita
if not any('rtk-codex' in h.get('command','') for h in alvo['hooks']):
    alvo['hooks'].append({"type": "command", "command": cmd})
json.dump(d, open(p,'w'), indent=2, ensure_ascii=False)
print("  ✓ registrado no hooks.json (após os hooks de segurança)")
PY
    echo "  → ABRA 'codex' no TUI uma vez e APROVE o hook."
    echo "    Sem trust o Codex o ignora em SILÊNCIO (ele imprime 'hook: PreToolUse' mesmo assim)."
  else
    todo "instalaria o hook em $HOOK + registro no hooks.json"
  fi
fi

say "Depois de aplicar, valide:"
cat <<'EOF'
  codex -p review exec --skip-git-repo-check "Responda apenas: OK"
    → cabeçalho deve mostrar  reasoning effort: high
    → o warning "Skill descriptions were shortened" deve ter sumido
    → compare o "tokens used" com o de antes: deve cair perto da metade
EOF
