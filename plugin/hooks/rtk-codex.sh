#!/usr/bin/env bash
# PreToolUse(Bash) → RTK: reescreve o comando para a variante `rtk ...` (60-90% menos tokens).
#
# Por que não chamar `rtk hook claude` direto: o Codex entrega o comando de shell como
# ARRAY (["/bin/zsh","-lc","git status"]), enquanto o RTK fala o dialeto do Claude Code
# (command como string). Este shim traduz nos dois sentidos e devolve `updatedInput`
# no mesmo formato que o Codex mandou.
#
# NÃO emite permissionDecision: este hook roda DEPOIS de check-careful.sh/block-main-commit.sh
# e um "allow" aqui sobrescreveria o "ask" deles num comando destrutivo. Só reescreve.
#
# Fail-open em tudo: sem node, sem rtk, sem match → exit 0 e o comando original segue.
# Porte do kit do time (F5 do núcleo único, #241): lê e monta o payload por node, sem jq.
# O hook precisa de trust do Codex (aparece no TUI na 1ª vez) — sem isso ele é ignorado
# silenciosamente, mesmo aparecendo como "hook: PreToolUse" no output.
#
# Mesma regra do rtk-claude.sh (03/09/2026): saída que alimenta outro comando ou
# arquivo não é reescrita — o filtro do rtk corrompe o que o pipe recebe.
set -uo pipefail

# 0 quando o stdout do comando alimenta OUTRO comando ou um arquivo: `|` (o `||` não
# encadeia saída e fica de fora), `$(`, crase, xargs, ou `>` para arquivo — `2>&1`,
# `>&2` e `/dev/null` não são arquivo. Pipe dentro de aspas conta como pipe: o falso
# positivo custa alguns tokens; o falso negativo custou uma auditoria.
saida_consumida() {
  local c="$1" resto
  resto=${c//"||"/}
  case "$resto" in *'|'*) return 0 ;; esac
  case "$c" in *'$('*|*'`'*|*xargs*) return 0 ;; esac
  case "$c" in *'>'*)
    resto=$(printf '%s' "$c" | sed -E 's/[0-9]*>&[0-9-]+//g; s/&?[0-9]*>>?[[:space:]]*\/dev\/null//g')
    case "$resto" in *'>'*) return 0 ;; esac ;;
  esac
  return 1
}

payload=$(cat)
[ -z "$payload" ] && exit 0

command -v node >/dev/null 2>&1 || exit 0
command -v rtk  >/dev/null 2>&1 || exit 0

# Um node para a forma do .tool_input.command ("string" ou ["/bin/zsh","-lc","cmd"]), o cwd e
# o comando (o último item do array), um por linha; o comando pode ter quebra de linha.
info=$(printf '%s' "$payload" | node -e '
  let s = ""; process.stdin.on("data", (d) => { s += d; }).on("end", () => {
    let p; try { p = JSON.parse(s); } catch { return; }
    const c = p && p.tool_input && p.tool_input.command;
    const shape = Array.isArray(c) ? "array" : typeof c === "string" ? "string" : "";
    const cmd = Array.isArray(c) ? String(c[c.length - 1] ?? "") : (c || "");
    const cwd = [p.tool_input && p.tool_input.workdir, p.tool_input && p.tool_input.cwd, p.cwd]
      .find((x) => typeof x === "string" && x.length > 0) || "";
    process.stdout.write(shape + "\n" + cwd.replace(/\n/g, " ") + "\n" + cmd);
  });' 2>/dev/null)
shape="${info%%$'\n'*}"; info="${info#*$'\n'}"
cwd_payload="${info%%$'\n'*}"; cmd="${info#*$'\n'}"
case "$shape" in string|array) ;; *) exit 0 ;; esac
[ -z "$cmd" ] && exit 0

# já reescrito → não mexe
case "$cmd" in rtk\ *) exit 0 ;; esac

saida_consumida "$cmd" && exit 0

# `git push` (qualquer forma) nunca é reescrito, em NENHUM cwd. Todo padrão de force
# push do deny — Bash(git *push* … main/master …) — começa com `git `; reescrito para
# `rtk git push …` o deny não casa. A GUARDA destrutiva abaixo já pega push --force/-f,
# mas NÃO a forma `+ref` sem -f (`push origin +HEAD:main`): fora de worktree ela vazava
# um force push em main (provado ao vivo no claude-config-team, prova-hm 20/10/2026).
# push tem economia de token nula, então toda forma passa reto aqui.
# O prefixo antes do `git` é qualquer coisa sem separador (`([^;&|]*[[:space:]])?`), não só
# `sudo`: o deny casa depois de atribuição de env e dos wrappers (`command`, `timeout`, …),
# então `FOO=1 git push …`/`command git push …` também precisam passar reto (senão viram
# `rtk git push …` e escapam). Sobre-aproximar (não reescrever um `echo "git push"`) só custa
# o ~0 token de um push.
if printf '%s' "$cmd" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*([^;&|]*[[:space:]])?git[[:space:]]+([^;&|]*[[:space:]])?push([[:space:]]|$)'; then
  exit 0
fi

# GUARDA 2: sessão em worktree isolado não aceita `git` com prefixo.
#
# O harness recusa qualquer comando git de uma sessão isolada que ele não consiga
# provar que fica dentro do worktree — e ele só sabe ler `git` como PRIMEIRO token.
# Reescrever para `rtk git ...` esconde o git atrás do launcher, e a recusa sai
# como "runs rtk with a git command among its operands: what runs it … cannot be
# read here". O comando não roda: a economia de tokens do RTK custa a operação
# inteira. Aconteceu em 03/09/2026, num `git add` de um único arquivo.
#
# O cwd vem no payload do Claude Code; $PWD é a reserva para quem não manda.
# Casa os dois layouts em uso: `.claude/worktrees/` (harness) e `.claude-worktrees/`
# (worktree criado à mão no padrão do kit).
if printf '%s' "$cmd" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)?git([[:space:]]|$)'; then
  case "${cwd_payload:-$PWD}" in
    */.claude/worktrees/*|*/.claude-worktrees/*) exit 0 ;;
  esac
fi

# GUARDA: o Codex exige permissionDecision e um "allow" daqui sobrescreveria o "ask"
# do check-careful.sh. Então tudo que ele vigia passa reto, sem reescrita.
# (caso concreto: `cat .env` → o RTK viraria `rtk read .env` e furaria a proteção)
# Esta lista tem que ser SUPERSET dos gatilhos do check-careful — cada regra de lá
# tem um caso-espelho em tests/test-rtk-codex.sh que quebra se a guarda ficar atrás
# (foi assim que a regra de exfiltração de 30/08 ficou de fora até 31/08). Na F4 o
# check-careful ganhou o descarte local (checkout/switch/restore/stash), a listagem do
# ambiente, os segredos além do .env e o Remove-Item: entram aqui também.
if printf '%s' "$cmd" | grep -qiE '\brm[[:space:]]+-[a-zA-Z]*[rR]|\brm[[:space:]].*--recursive|remove-item|\b(ri|del|erase|rd|rmdir)[[:space:]].*-r|git[[:space:]]+push.*(--force|-f)|\b(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE)\b|supabase[[:space:]]+db[[:space:]]+reset|gh[[:space:]]+pr[[:space:]]+merge.*--admin|git[[:space:]]+add[[:space:]]+(-[a-zA-Z]*[Au]\b|--all\b|\.)|(CREATE|ALTER)[[:space:]]+TABLE|\.env([[:space:]]|$|\.)|[A-Za-z0-9_-]\.env\b|id_rsa|id_ed25519|id_ecdsa|\.pem\b|\.ssh[/\\]|\.aws[/\\]|\.netrc|\.npmrc|\.claude\.json|hosts\.yml|serviceAccountKey|SERVICE_ROLE|SERVICE_KEY|ANTHROPIC_API_KEY|git[[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+)*(checkout|switch|restore|stash)\b|(^|[;&|][[:space:]]*)(env|printenv|set|export|declare)([[:space:]]|$)|env:|getenvironmentvariables'; then
  exit 0
fi

novo=$(rtk hook check "$cmd" 2>/dev/null | head -1)
[ -z "$novo" ] && exit 0
[ "$novo" = "$cmd" ] && exit 0

# A mesma forma de entrada na saída: no array troca só o último item (o script do -lc).
printf '%s' "$payload" | NOVO="$novo" node -e '
  let s = ""; process.stdin.on("data", (d) => { s += d; }).on("end", () => {
    const p = JSON.parse(s), ti = Object.assign({}, p.tool_input), n = process.env.NOVO;
    ti.command = Array.isArray(ti.command) ? ti.command.slice(0, -1).concat([n]) : n;
    process.stdout.write(JSON.stringify({ hookSpecificOutput: {
      hookEventName: "PreToolUse", permissionDecision: "allow",
      permissionDecisionReason: "RTK auto-rewrite", updatedInput: ti } }));
  });' 2>/dev/null
exit 0
