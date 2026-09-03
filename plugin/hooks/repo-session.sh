#!/usr/bin/env bash
# Registro leve de sessões ativas por repositório — é a base do block-parallel-clone-switch.
#
# Uso: repo-session.sh touch   (SessionStart / UserPromptSubmit / PostToolUse)
#      repo-session.sh end     (SessionEnd)
# Marker: ~/.claude/.cache/repo-sessions/<sha1-do-toplevel>/<session_id>
# Sessão "ativa" = marker com mtime recente (quem decide a janela é o hook de bloqueio).
#
# Lê o JSON do hook via node (sem depender de jq). Falha-aberta: qualquer erro => exit 0.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
mode="${1:-touch}"
info="$(cat | node "$H" session_id cwd)"
sid="$(printf '%s\n' "$info" | sed -n 1p)"
cwd="$(printf '%s\n' "$info" | sed '1d')"
[ -z "$sid" ] && exit 0
[ -z "$cwd" ] && cwd="$PWD"
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[ -z "$root" ] && exit 0
h=$(printf '%s' "$root" | shasum 2>/dev/null | awk '{print $1}')
[ -z "$h" ] && exit 0
d="$HOME/.claude/.cache/repo-sessions/$h"
case "$mode" in
  end)
    rm -f "$d/$sid" 2>/dev/null
    ;;
  *)
    mkdir -p "$d" 2>/dev/null
    printf '%s\n' "$root" > "$d/.root" 2>/dev/null
    touch "$d/$sid" 2>/dev/null
    # Poda 1x/dia e em TODOS os repos. Rodar um `find` a cada chamada só na pasta do
    # repo atual deixava repo que você parou de abrir sem limpeza nunca — 1.144 markers
    # acumulados em 6 semanas numa máquina do time. Marker morto = sem toque há 24h;
    # pasta cujo .root não é reescrito há 30 dias é repo abandonado e sai inteira.
    base="$HOME/.claude/.cache/repo-sessions"
    hoje=$(date +%Y%m%d)
    # `read < arquivo 2>/dev/null` ainda reclama no stderr quando o arquivo não existe —
    # a redireção de entrada falha antes de a de erro valer. Daí o teste explícito.
    ultima=""; [ -f "$base/.poda" ] && read -r ultima < "$base/.poda"
    if [ "$ultima" != "$hoje" ]; then
      printf '%s\n' "$hoje" > "$base/.poda" 2>/dev/null
      find "$base" -mindepth 2 -maxdepth 2 -name .root -mtime +30 2>/dev/null \
        | while IFS= read -r r; do rm -rf "${r%/.root}"; done
      find "$base" -mindepth 2 -type f ! -name .root -mmin +1440 -delete 2>/dev/null
    fi
    ;;
esac
exit 0
