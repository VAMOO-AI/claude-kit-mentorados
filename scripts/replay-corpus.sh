#!/usr/bin/env bash
# replay-corpus.sh — passa um corpus de comandos Bash pelo dispatcher plugin/hooks/pre-bash.sh
# e diz o que cada guard decide. Com --base, compara a decisão do base com a do head.
#
# Por que existe (#241, plano do núcleo único): uma regressão de guard pega todo mentorado de
# uma vez. A suíte de cada hook testa os casos que alguém pensou; o replay testa a forma real
# dos comandos (prefixo `FOO=1`, `cd x &&`, pipe, heredoc) contra o dispatcher inteiro.
#
# Uso:
#   scripts/replay-corpus.sh --base origin/main --corpus tests/corpus/comandos.jsonl   # o CI
#   scripts/replay-corpus.sh --base origin/main            # corpus real, só na sua máquina
#   scripts/replay-corpus.sh                               # contagem por decisão no head
#   scripts/replay-corpus.sh --base-dir <plugin/> --head-dir <plugin/> --corpus <arq>
#   opções: --days N (corpus real, padrão 30) · --fires <arq> (TSV comando a comando)
#           --corpo-pr <arq> (corpo do PR: com a seção "## Divergências do replay", a
#           divergência é declarada e sai 0 com aviso; é o que o CI usa)
#
# Decisão de um comando: "bloqueia" (rc 2), "ask"/"deny"/"allow" (permissionDecision no
# stdout), "reescreve" (updatedInput; desde 09/11/2026 nenhum hook do plugin reescreve), "bug" (rc ≠ 0 e ≠ 2) ou "passa". O texto da
# mensagem não entra na comparação: mudar a frase de um bloqueio não é divergência.
#
# Corpus: JSONL com {"command": "..."} por linha. Sem --corpus, sai dos transcripts de
# ~/.claude/projects dos últimos N dias. Esse corpus carrega comandos reais, que podem ter
# segredo: nasce em mktemp e NUNCA vai para o repo nem para o CI público. Cole no PR só as
# contagens. O corpus público é tests/corpus/comandos.jsonl, sintético.
#
# Isolamento: nenhum comando do corpus é executado, só entregue ao hook como payload. Os
# hooks rodam com HOME num diretório temporário e cwd num repo de mentira, no branch
# feat/replay, para que estado da sua máquina (sessões, cache) não mude a decisão.
#
# Saída: 0 sem divergência; 1 com divergência (lista no stdout); 2 erro de uso ou ambiente.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE=""; BASE_DIR=""; HEAD_DIR="$RAIZ/plugin"; CORPUS=""; DAYS=30; FIRES=""; CORPO_PR=""

uso() { sed -n '9,18p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --base)     BASE="${2:-}"; [ -n "$BASE" ] || uso; shift 2 ;;
    --base-dir) BASE_DIR="${2:-}"; [ -n "$BASE_DIR" ] || uso; shift 2 ;;
    --head-dir) HEAD_DIR="${2:-}"; [ -n "$HEAD_DIR" ] || uso; shift 2 ;;
    --corpus)   CORPUS="${2:-}"; [ -n "$CORPUS" ] || uso; shift 2 ;;
    --days)     DAYS="${2:-}"; case "$DAYS" in ''|*[!0-9]*) uso ;; esac; shift 2 ;;
    --fires)    FIRES="${2:-}"; [ -n "$FIRES" ] || uso; shift 2 ;;
    --corpo-pr) CORPO_PR="${2:-}"; [ -f "$CORPO_PR" ] || { echo "replay-corpus: --corpo-pr precisa de um arquivo" >&2; exit 2; }; shift 2 ;;
    -h|--help)  uso ;;
    *) echo "replay-corpus: opção desconhecida: $1" >&2; uso ;;
  esac
done
[ -n "$BASE" ] && [ -n "$BASE_DIR" ] && { echo "replay-corpus: use --base ou --base-dir, não os dois" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "replay-corpus: precisa do python3" >&2; exit 2; }
[ -f "$HEAD_DIR/hooks/pre-bash.sh" ] || { echo "replay-corpus: $HEAD_DIR/hooks/pre-bash.sh não existe" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/replay-corpus.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

if [ -n "$BASE" ]; then
  git -C "$RAIZ" rev-parse -q --verify "$BASE^{commit}" >/dev/null \
    || { echo "replay-corpus: ref $BASE não existe (faltou o fetch?)" >&2; exit 2; }
  mkdir -p "$TMP/base"
  git -C "$RAIZ" archive "$BASE" plugin | tar -x -C "$TMP/base" \
    || { echo "replay-corpus: git archive $BASE plugin falhou" >&2; exit 2; }
  BASE_DIR="$TMP/base/plugin"
fi
if [ -n "$BASE_DIR" ] && [ ! -f "$BASE_DIR/hooks/pre-bash.sh" ]; then
  echo "replay-corpus: $BASE_DIR/hooks/pre-bash.sh não existe" >&2; exit 2
fi

if [ -z "$CORPUS" ]; then
  CORPUS="$TMP/corpus.jsonl"
  find "$HOME/.claude/projects" -name '*.jsonl' -mtime "-$DAYS" > "$TMP/arquivos.txt" 2>/dev/null
  python3 - "$TMP/arquivos.txt" "$CORPUS" <<'PY'
import json, sys
vistos, saida = set(), open(sys.argv[2], "w", encoding="utf-8")
for caminho in open(sys.argv[1], encoding="utf-8"):
    try:
        fh = open(caminho.strip(), encoding="utf-8", errors="ignore")
    except OSError:
        continue
    for linha in fh:
        if '"tool_use"' not in linha:
            continue
        try:
            conteudo = (json.loads(linha).get("message") or {}).get("content")
        except ValueError:
            continue
        for b in conteudo if isinstance(conteudo, list) else []:
            if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Bash":
                cmd = (b.get("input") or {}).get("command") or ""
                if cmd and cmd not in vistos:
                    vistos.add(cmd); saida.write(json.dumps({"command": cmd}) + "\n")
print(f"corpus real: {len(vistos)} comandos únicos (fica em mktemp, nunca commite)", file=sys.stderr)
PY
fi
[ -s "$CORPUS" ] || { echo "replay-corpus: corpus vazio ($CORPUS)" >&2; exit 2; }

# Repo de mentira e HOME isolado, iguais para os dois lados.
FIX="$TMP/repo"; mkdir -p "$FIX" "$TMP/home"
(
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  git -C "$FIX" init -q -b main 2>/dev/null || { git -C "$FIX" init -q && git -C "$FIX" checkout -q -b main; }
  printf 'replay\n' > "$FIX/LEIAME.md"
  git -C "$FIX" add LEIAME.md
  git -C "$FIX" -c user.name=replay -c user.email=replay@exemplo.invalid commit -q -m base
  git -C "$FIX" checkout -q -b feat/replay
) || { echo "replay-corpus: não montei o repo de mentira" >&2; exit 2; }

python3 - "$CORPUS" "$FIX" "$TMP/home" "$HEAD_DIR" "${BASE_DIR:-}" "${FIRES:-}" "${CORPO_PR:-}" <<'PY'
import json, os, re, subprocess, sys
from collections import Counter
corpus, fix, home, head_dir, base_dir, fires, corpo_pr = sys.argv[1:8]

cmds = []
for n, linha in enumerate(open(corpus, encoding="utf-8"), 1):
    linha = linha.strip()
    if not linha or linha.startswith("//"):
        continue
    try:
        c = json.loads(linha).get("command")
    except ValueError:
        sys.exit(f"replay-corpus: linha {n} do corpus não é JSON")
    if isinstance(c, str) and c:
        cmds.append(c)

env = dict(os.environ, HOME=home, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
env.pop("PRE_BASH_HOOKS_DIR", None)

def decide(plugin_dir, cmd):
    payload = json.dumps({"session_id": "replay", "hook_event_name": "PreToolUse",
                          "tool_name": "Bash", "tool_input": {"command": cmd},
                          "cwd": fix, "permission_mode": "default"})
    try:
        p = subprocess.run(["bash", os.path.join(plugin_dir, "hooks", "pre-bash.sh")],
                           input=payload, capture_output=True, text=True, cwd=fix, env=env, timeout=20)
    except subprocess.TimeoutExpired:
        return "timeout"
    if p.returncode == 2:
        return "bloqueia"
    if p.returncode != 0:
        return f"bug(rc={p.returncode})"
    m = re.search(r'"permissionDecision"\s*:\s*"(\w+)"', p.stdout)
    if m:
        return m.group(1)
    if '"updatedInput"' in p.stdout:
        return "reescreve"
    return "passa"

curto = lambda c: (c.replace("\n", "⏎")[:160] + ("…" if len(c) > 160 else ""))
linhas_fires, divergencias, contagem = [], [], Counter()
for c in cmds:
    h = decide(head_dir, c)
    contagem[h] += 1
    if base_dir:
        b = decide(base_dir, c)
        if b != h:
            divergencias.append((b, h, c))
        linhas_fires.append(f"{b}\t{h}\t{curto(c)}")
    else:
        linhas_fires.append(f"{h}\t{curto(c)}")

if fires:
    open(fires, "w", encoding="utf-8").write("\n".join(linhas_fires) + "\n")

resumo = " · ".join(f"{k} {v}" for k, v in sorted(contagem.items(), key=lambda x: (-x[1], x[0])))
print(f"replay: {len(cmds)} comandos · head: {resumo}")
if not base_dir:
    sys.exit(0)
if not divergencias:
    print("replay: 0 divergências entre base e head")
    sys.exit(0)
print(f"replay: {len(divergencias)} divergência(s) entre base e head (base → head):")
for b, h, c in divergencias:
    print(f"  {b} → {h}  {curto(c)}")
# O corpo do PR é dado: só se procura o cabeçalho, nada dele é executado.
if corpo_pr and re.search(r"(?im)^##\s*Diverg[eê]ncias do replay\s*$",
                          open(corpo_pr, encoding="utf-8", errors="ignore").read()):
    print("replay: o PR declara as divergências (## Divergências do replay); confira se a lista bate")
    sys.exit(0)
print('replay: mudança de decisão não declarada. Se é de propósito, explique no corpo do PR numa seção "## Divergências do replay".')
sys.exit(1)
PY
