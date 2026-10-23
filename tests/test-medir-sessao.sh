#!/usr/bin/env bash
# O medir-sessao.py é o número que a harness-check pede antes de cortar MCP ou skill.
# Dois jeitos de ele mentir, os dois achados no porte para o kit dos mentorados (#200):
#
#   - `--comparar` ignorava o `--cwd` e punha lado a lado superfícies de diretórios
#     diferentes, onde o CLAUDE.md e o .context de cada projeto entram na conta;
#   - transcript sem a lista de tools saía `tools=0`, que lê como "zero tools" quando o
#     certo é "não registrado".
#
# O HOME é temporário: o script lê ~/.claude/projects.
#
# Uso: bash tests/test-medir-sessao.sh [caminho-do-medir-sessao.py]
set -uo pipefail
PY="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/medir-sessao.py}"
[ -f "$PY" ] || { echo "medir-sessao.py não encontrado: $PY"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 ausente"; exit 2; }

falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
check() { if [ "$2" = ok ]; then ok "$1"; else falha "$1"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/medir-sessao.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
P="$HOME/.claude/projects"

sessao() { # <projeto> <id> <entrypoint> <cwd> <com-tools:1|0> <mtime>
  local d="$P/$1" f="$P/$1/$2.jsonl"
  mkdir -p "$d"
  printf '{"type":"user","entrypoint":"%s","cwd":"%s","version":"2.1.280"}\n' "$3" "$4" > "$f"
  if [ "$5" = 1 ]; then
    printf '{"type":"attachment","attachment":{"type":"deferred_tools","names":["mcp__alfa__um","mcp__alfa__dois","mcp__beta__tres"]}}\n' >> "$f"
  fi
  printf '{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":20000,"cache_read_input_tokens":0}}}\n' >> "$f"
  touch -t "$6" "$f"
}

# Mais recente primeiro: o terminal em /proj/b é a sessão mais nova de todas.
sessao b aaaaaaaa-0000-0000-0000-000000000001 cli            /proj/b 0 202609230900
sessao a aaaaaaaa-0000-0000-0000-000000000002 cli            /proj/a 0 202609230800
sessao a aaaaaaaa-0000-0000-0000-000000000003 claude-desktop /proj/a 1 202609230700
sessao c aaaaaaaa-0000-0000-0000-000000000004 claude-vscode  /proj/c 0 202609230600

echo "== --comparar respeita o --cwd =="
out="$(python3 "$PY" --comparar --cwd /proj/a 2>&1)"
check "mostra o terminal de /proj/a"           "$(printf '%s' "$out" | grep -Eq '^aaaaaaaa +cli ' && printf '%s' "$out" | grep >/dev/null '/proj/a' && echo ok || echo fail)"
check "não traz o terminal de /proj/b"         "$(printf '%s' "$out" | grep >/dev/null '/proj/b' && echo fail || echo ok)"
check "sem aviso de diretórios diferentes"     "$(printf '%s' "$out" | grep >/dev/null 'diretórios diferentes' && echo fail || echo ok)"

echo "== sem --cwd, diretórios diferentes avisam =="
out="$(python3 "$PY" --comparar 2>&1)"
check "avisa que os diretórios diferem"        "$(printf '%s' "$out" | grep >/dev/null 'diretórios diferentes' && echo ok || echo fail)"

echo "== --comparar com uma superfície só avisa =="
out="$(python3 "$PY" --comparar --cwd /proj/b 2>&1)"
check "diz que só achou uma superfície"        "$(printf '%s' "$out" | grep >/dev/null 'só uma superfície' && echo ok || echo fail)"

echo "== entrypoint fora da lista conhecida também aparece =="
out="$(python3 "$PY" --comparar --cwd /proj/c 2>&1)"
check "a sessão do vscode é mostrada"          "$(printf '%s' "$out" | grep -Eq '^aaaaaaaa +claude-vscode ' && echo ok || echo fail)"

echo "== --comparar num diretório sem sessão =="
out="$(python3 "$PY" --comparar --cwd /proj/nada 2>&1)"; rc=$?
check "sai com erro e nomeia o diretório"      "$([ "$rc" != 0 ] && printf '%s' "$out" | grep >/dev/null '/proj/nada' && echo ok || echo fail)"

echo "== lista de tools ausente não é zero =="
out="$(python3 "$PY" aaaaaaaa-0000-0000-0000-000000000002 2>&1)"
check "sem lista registrada: tools=?"          "$(printf '%s' "$out" | grep -Eq 'tools= *\?' && echo ok || echo fail)"
check "e não tools=0"                          "$(printf '%s' "$out" | grep -Eq 'tools= *0 ' && echo fail || echo ok)"
out="$(python3 "$PY" aaaaaaaa-0000-0000-0000-000000000003 2>&1)"
check "com lista: conta as 3 tools"            "$(printf '%s' "$out" | grep -Eq 'tools= *3 ' && echo ok || echo fail)"
check "e os 2 servidores"                      "$(printf '%s' "$out" | grep -Eq 'servidores= *2 ' && echo ok || echo fail)"
check "nascimento vem do usage"                "$(printf '%s' "$out" | grep -Eq 'nascimento= *20010' && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
