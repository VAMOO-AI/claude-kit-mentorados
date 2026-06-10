#!/usr/bin/env bash
# ticktick-task.sh — helper para a skill agent-reporting
#
# Subcomandos:
#   create  "<title>" "<description>" [tag1 tag2 ...]   → cria task, escreve state
#   checkpoint "<linha>"                                 → append à description
#   done    "<resumo final>"                             → marca completa, limpa state
#   id                                                   → printa o task_id ativo (vazio se não houver)
#
# State: ~/.claude/state/agent-reporting/<cwd-hash>.json
# Token: ~/WORKSPACES/mcp-servers/ticktick-mcp/.env
# Projects: ~/.claude/state/ticktick-projects.json (key: claude_agents.id)

set -euo pipefail

# Caminhos configuráveis — exporte no seu shell se o seu setup for diferente
ENV_FILE="${TICKTICK_ENV_FILE:-$HOME/WORKSPACES/mcp-servers/ticktick-mcp/.env}"
PROJECTS_FILE="${TICKTICK_PROJECTS_FILE:-$HOME/.claude/state/ticktick-projects.json}"
STATE_DIR="$HOME/.claude/state/agent-reporting"
mkdir -p "$STATE_DIR"

# Hash cwd → 1 task ativo por diretório
CWD_HASH=$(printf '%s' "$PWD" | shasum -a 256 | cut -c1-12)
STATE_FILE="$STATE_DIR/${CWD_HASH}.json"

# Sem pré-requisito configurado a skill não dispara — avisa e sai sem quebrar
# o trabalho (alinhado ao contrato do README: sem setup, ela só não faz nada).
if [[ ! -r "$ENV_FILE" ]]; then
  echo "agent-reporting: TickTick não configurado (faltou $ENV_FILE) — pulando" >&2
  exit 0
fi
if [[ ! -r "$PROJECTS_FILE" ]]; then
  echo "agent-reporting: faltou $PROJECTS_FILE — pulando" >&2
  exit 0
fi

CMD="${1:-}"
shift || true

python3 - "$CMD" "$STATE_FILE" "$ENV_FILE" "$PROJECTS_FILE" "$@" <<'PYEOF'
import json, sys, os, urllib.request, urllib.error, pathlib, time, re, datetime

cmd, state_file, env_file, projects_file, *args = sys.argv[1:]

def load_token():
    for line in pathlib.Path(env_file).read_text().splitlines():
        if line.startswith("TICKTICK_ACCESS_TOKEN="):
            return line.split("=",1)[1].strip().strip('"').strip("'")
    raise SystemExit("ERR: TICKTICK_ACCESS_TOKEN not in env file")

def load_project_id():
    return json.loads(pathlib.Path(projects_file).read_text())["claude_agents"]["id"]

def sanitize(s):
    if s is None: return ""
    s = s.replace("\\n", " ").replace("\r", " ")
    s = re.sub(r"\\+", "/", s)
    s = re.sub(r"[\x00-\x08\x0B-\x1F\x7F]", "", s)
    return s.strip()

def api(method, path, body=None):
    token = load_token()
    req = urllib.request.Request(
        f"https://api.ticktick.com{path}",
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body else None,
    )
    try:
        resp = urllib.request.urlopen(req, timeout=15)
        body_bytes = resp.read()
        return json.loads(body_bytes) if body_bytes else {}
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"HTTP {e.code}: {e.read().decode(errors='replace')}\n")
        raise

def now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

def read_state():
    p = pathlib.Path(state_file)
    return json.loads(p.read_text()) if p.exists() else None

def write_state(d):
    p = pathlib.Path(state_file)
    p.write_text(json.dumps(d, ensure_ascii=False, indent=2))
    p.chmod(0o600)

def clear_state():
    p = pathlib.Path(state_file)
    if p.exists(): p.unlink()

if cmd == "create":
    if len(args) < 2:
        raise SystemExit("usage: create <title> <description> [tags...]")
    title = sanitize(args[0])[:80]
    description = sanitize(args[1])
    tags = [t.lstrip("#") for t in args[2:]]
    project_id = load_project_id()
    body = {
        "title": title,
        "projectId": project_id,
        "content": f"📋 Pedido: {description}\n📁 cwd: {os.getcwd()}\n🕐 Início: {now()}\n---\nCheckpoints:",
        "tags": tags,
        "priority": 3,
    }
    r = api("POST", "/open/v1/task", body)
    write_state({"task_id": r["id"], "project_id": project_id, "title": title, "started": now()})
    print(r["id"])

elif cmd == "checkpoint":
    if len(args) < 1:
        raise SystemExit("usage: checkpoint <line>")
    st = read_state()
    if not st:
        sys.exit(0)  # nada ativo, no-op silencioso
    line = sanitize(args[0])
    # Get current task to preserve content
    task = api("GET", f"/open/v1/project/{st['project_id']}/task/{st['task_id']}")
    new_content = (task.get("content","") + f"\n- [{now()}] {line}")[:20000]
    api("POST", f"/open/v1/task/{st['task_id']}", {
        "id": st["task_id"],
        "projectId": st["project_id"],
        "content": new_content,
    })
    print("ok")

elif cmd == "done":
    summary = sanitize(args[0]) if args else "Concluído."
    st = read_state()
    if not st:
        sys.exit(0)  # nada ativo
    task = api("GET", f"/open/v1/project/{st['project_id']}/task/{st['task_id']}")
    final_content = (task.get("content","") + f"\n---\n✅ Concluído em {now()}\n{summary}")[:20000]
    api("POST", f"/open/v1/task/{st['task_id']}", {
        "id": st["task_id"],
        "projectId": st["project_id"],
        "content": final_content,
    })
    api("POST", f"/open/v1/project/{st['project_id']}/task/{st['task_id']}/complete")
    clear_state()
    print("done")

elif cmd == "id":
    st = read_state()
    print(st["task_id"] if st else "")

else:
    raise SystemExit(f"unknown cmd: {cmd}")
PYEOF
