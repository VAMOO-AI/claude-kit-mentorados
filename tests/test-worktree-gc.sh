#!/usr/bin/env bash
# Prova de regressão do plugin/scripts/worktree-gc.sh.
#
# O script anterior aceitava "mergeada" por `gh pr list --state merged | length > 0`:
# bastava a branch ter tido UM PR mergeado um dia. Commit feito depois do merge, ainda
# sem push, contava como lixo — e `--apply` apagava worktree com trabalho novo. O
# conserto (vindo do kit do time) exige que o tip local esteja contido no head do PR
# mergeado; sem isso, fail-closed: mantém.
#
# Também cobre as outras duas travas que vieram juntas: env ignorado que difere do
# clone principal (invisível no `status`, some junto com o worktree) e worktree
# detached, que antes era pulado sempre e agora é lixo quando está limpo e o HEAD é
# trabalho já contido em origin/main. Até 28/09/2026 a trava do env só comparava o
# `.env.local` da raiz: `.npmrc` e `.env.local` de subpasta sumiam no --apply.
#
# Branch sem commit próprio é ancestral de origin/main por definição, e o `--apply`
# removia o worktree limpo de uma sessão recém-aberta (24/09/2026 — o mesmo defeito do
# warn-worktree-stale). Agora ela fica: o tip não passou do ponto de criação (1ª entrada
# do reflog) ou é commit da linha first-parent da main. Vale também para o detached no
# tip ou num commit antigo da main.
#
# Até 28/09/2026 a trava só olhava env: um `outputs/video.mp4` ignorado sumia no --apply
# e o porcelain saía vazio. Agora todo ignorado é keep, menos env igual ao do clone,
# symlink e cache/build da lista fechada (node_modules, .next...). O `--verificar <caminho>`
# aplica as mesmas travas a um worktree só, sem remover nada: é o que roda antes do
# ExitWorktree.
#
# O `gh` é falso (PATH): responde às duas formas de consulta — a antiga (`length`) e a
# nova (`headRefOid`) — para que o mesmo teste rode contra as duas versões do script.
#
# Uso: bash tests/test-worktree-gc.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/worktree-gc.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wtgc.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}
no_disco() { # <worktree> <por que não podia sumir>
  if [ -d "$WTS/$1" ]; then printf '  ok    %s continua no disco\n' "$1"
  else printf '  FALHA %s foi apagado: %s\n' "$1" "$2"; falhas=$((falhas+1)); fi
}

# --- fixture: origin bare + clone principal com main -------------------------------
ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"; WTS="$CLONE/.claude/worktrees"
# -b main + origin/HEAD: o gc descobre a branch padrão pelo origin/HEAD, e um bare sem -b
# apontaria para master (o default do git no runner), que aqui não existe.
git init -q --bare -b main "$ORIGIN"
git init -q "$CLONE"
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
G() { g -C "$CLONE" "$@"; }
# O .gitignore entra no PRIMEIRO commit, antes de qualquer worktree: a trava do .env.local
# só é alcançada se o arquivo estiver ignorado — untracked, ele já cai na trava de "sujo".
# Sem isto o teste passava só em máquina cujo gitignore global ignora .env.local (03/09/2026).
echo base > "$CLONE/base.txt"; printf '.env.local\n.npmrc\nbunfig.toml\n.bunfig.toml\nvendor/\noutputs/\nout/\nnode_modules/\n.next/\n.venv\n' > "$CLONE/.gitignore"
G add base.txt .gitignore; G commit -qm base
G branch -M main; G remote add origin "$ORIGIN"; G push -qu origin main
G remote set-head origin main
BASE="$(G rev-parse HEAD)"
echo "ENV=clone" > "$CLONE/.env.local"; echo "registry=clone" > "$CLONE/.npmrc"
echo "exact = true" > "$CLONE/bunfig.toml"; echo "exact = true" > "$CLONE/.bunfig.toml"
mkdir -p "$WTS"

novo_wt()    { G worktree add -q -b "$1" "$WTS/wt-$1" "${2:-origin/main}"; }
commit_em()  { g -C "$WTS/wt-$1" commit -q --allow-empty -m "$2"; }
# Push a cada merge: o gc abre com `fetch --prune`, e o origin/main do clone vira o do bare.
merge_main() { G merge -q --no-ff -m "merge $1" "$1"; G push -q origin main; }

# Sem commit próprio — criadas antes dos merges, para a main andar depois delas.
# nova: recém-criada de origin/main, limpa — a sessão ainda não escreveu nada
novo_wt nova
# sem-reflog: idem, com o reflog expirado — sobra a linha first-parent da main
novo_wt sem-reflog
G reflog expire --expire=now refs/heads/sem-reflog
# sincronizada: nasce aqui, puxa a base (ff) lá embaixo, e a main anda de novo depois
novo_wt sincronizada
# empilhada: criada de feat (que tem commit próprio), sem commit dela; feat é mergeada
novo_wt feat; commit_em feat f
G worktree add -q -b empilhada "$WTS/wt-empilhada" feat
merge_main feat

# anc: mergeada de verdade (ancestral de origin/main)
novo_wt anc; commit_em anc anc; merge_main anc
OID_ANC="$(G rev-parse anc)"

# pr-ok: squash-mergeada — o PR aponta para o tip local
novo_wt pr-ok; commit_em pr-ok pr
OID_PR="$(G rev-parse pr-ok)"

# pr-after: PR mergeado no commit X, mas há um commit Y DEPOIS, sem push
novo_wt pr-after; commit_em pr-after X
OID_AFTER="$(G rev-parse pr-after)"
commit_em pr-after Y

# env: mergeada de verdade e limpa, mas com .env.local diferente do clone — só a trava
# do .env.local a segura (o `worktree remove` apaga arquivo ignorado sem reclamar)
novo_wt env; commit_em env e; merge_main env
echo "ENV=outro" > "$WTS/wt-env/.env.local"
# env-npmrc e env-aninhado: a mesma trava para o .npmrc e para um .env.local de subpasta,
# que nem existe no clone principal. E a anc leva uma cópia igual do .env.local do clone:
# env igual não segura ninguém.
novo_wt env-npmrc; commit_em env-npmrc n; merge_main env-npmrc
echo "registry=outro" > "$WTS/wt-env-npmrc/.npmrc"
novo_wt env-aninhado; commit_em env-aninhado a; merge_main env-aninhado
mkdir -p "$WTS/wt-env-aninhado/apps/x"; echo "ENV=sub" > "$WTS/wt-env-aninhado/apps/x/.env.local"
cp "$CLONE/.env.local" "$WTS/wt-anc/.env.local"
# env-bunfig, env-npmrc-sub e env-repo: o bunfig.toml de projeto (sem ponto) diferente, um
# .npmrc de subpasta e um repo aninhado ignorado — o remove apagaria até o .git dele
novo_wt env-bunfig; commit_em env-bunfig b; merge_main env-bunfig
echo "exact = false" > "$WTS/wt-env-bunfig/bunfig.toml"
novo_wt env-npmrc-sub; commit_em env-npmrc-sub s; merge_main env-npmrc-sub
# env-bunfigdot: o .bunfig.toml (com ponto, o global do Bun copiado para o projeto) diferente
novo_wt env-bunfigdot; commit_em env-bunfigdot bd; merge_main env-bunfigdot
echo "exact = false" > "$WTS/wt-env-bunfigdot/.bunfig.toml"
mkdir -p "$WTS/wt-env-npmrc-sub/apps/y"; echo "registry=sub" > "$WTS/wt-env-npmrc-sub/apps/y/.npmrc"
novo_wt env-repo; commit_em env-repo r; merge_main env-repo
git init -q "$WTS/wt-env-repo/vendor/lib"

# ign-*: mergeadas e limpas, cada uma com um tipo de ignorado. `outputs/` é trabalho (o
# remove o apagaria calado); node_modules/.next são cache; o .venv é symlink para o clone
# principal (o padrão `.venv` vai sem barra: `.venv/` não casa symlink)
novo_wt ign-outputs; commit_em ign-outputs o; merge_main ign-outputs
mkdir -p "$WTS/wt-ign-outputs/outputs"; echo mp4 > "$WTS/wt-ign-outputs/outputs/video.mp4"
# ign-out: `out/` não é cache — ferramenta de render (Remotion) grava o arquivo final ali
novo_wt ign-out; commit_em ign-out r; merge_main ign-out
mkdir -p "$WTS/wt-ign-out/out"; echo mp4 > "$WTS/wt-ign-out/out/video.mp4"
novo_wt ign-cache; commit_em ign-cache c; merge_main ign-cache
mkdir -p "$WTS/wt-ign-cache/node_modules" "$WTS/wt-ign-cache/apps/web/.next"
echo x > "$WTS/wt-ign-cache/node_modules/x"; echo x > "$WTS/wt-ign-cache/apps/web/.next/x"
novo_wt ign-venv; commit_em ign-venv v; merge_main ign-venv
mkdir -p "$CLONE/.venv"; echo alvo > "$CLONE/.venv/marca"
ln -s "$CLONE/.venv" "$WTS/wt-ign-venv/.venv"

# dirty: mergeada de verdade, mas suja
novo_wt dirty; commit_em dirty d; merge_main dirty
echo x > "$WTS/wt-dirty/sujo.txt"

g -C "$WTS/wt-sincronizada" merge -q --ff-only origin/main
G commit -q --allow-empty -m "main andou"; G push -q origin main

# det: detached no tip da main, limpo — checkout da base, não trabalho
G worktree add -q --detach "$WTS/wt-det" origin/main
# det-velho: detached num commit antigo da linha first-parent da main
G worktree add -q --detach "$WTS/wt-det-velho" "$BASE"
# det-mergeado: detached num commit que entrou na main por merge commit — esse é lixo
G worktree add -q --detach "$WTS/wt-det-mergeado" "$OID_ANC"
# det-env: o mesmo commit mergeado, mas com .env.local diferente do clone — fica, e diz qual
G worktree add -q --detach "$WTS/wt-det-env" "$OID_ANC"
echo "ENV=det" > "$WTS/wt-det-env/.env.local"
# det-ign: o mesmo, com um ignorado de trabalho em vez de env
G worktree add -q --detach "$WTS/wt-det-ign" "$OID_ANC"
mkdir -p "$WTS/wt-det-ign/outputs"; echo mp4 > "$WTS/wt-det-ign/outputs/video.mp4"

# det-squash*: detached num commit que só existe no head de um PR squash-mergeado — nenhum
# ancestral de origin/main. Só o PR prova: MERGED, na main, com head == HEAD.
sq() { G commit-tree -p "$BASE" -m "$1" "$(G rev-parse "$BASE^{tree}")"; }
OID_SQ="$(sq squash)"; OID_SQH="$(sq squash-head)"; OID_SQB="$(sq squash-base)"; OID_SQA="$(sq squash-aberto)"
for s in "$OID_SQ:det-squash" "$OID_SQH:det-squash-head" "$OID_SQB:det-squash-base" "$OID_SQA:det-squash-aberto"; do
  G worktree add -q --detach "$WTS/wt-${s#*:}" "${s%%:*}"
done
pulls() { # <merged_at|null> <head.sha> <base.ref>
  printf '[{"number":9,"merged_at":%s,"head":{"sha":"%s"},"base":{"ref":"%s"}}]\n' "$1" "$2" "$3"
}
M='"2026-09-28T00:00:00Z"'
J_SQ="$(pulls "$M" "$OID_SQ" main)"; J_SQH="$(pulls "$M" "$OID_SQ" main)"
J_SQB="$(pulls "$M" "$OID_SQB" feat)"; J_SQA="$(pulls null "$OID_SQA" main)"

# rest-*: squash-mergeadas que só a API REST prova (a conta do gh não enxerga o repo)
novo_wt rest-ok; commit_em rest-ok r1
OID_REST="$(G rev-parse rest-ok)"
novo_wt rest-depois; commit_em rest-depois x
OID_REST_X="$(G rev-parse rest-depois)"; commit_em rest-depois y
J_REST="$(pulls "$M" "$OID_REST" main)"; J_REST_X="$(pulls "$M" "$OID_REST_X" main)"

# --- gh falso: quem tem PR mergeado, e em qual head ----------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<GH
#!/usr/bin/env bash
case "\$1" in auth) exit 0 ;; repo) [ -n "\${FAKE_DEF:-}" ] && echo "\$FAKE_DEF"; exit 0 ;; esac
if [ "\$1" = api ]; then
  case "\$2" in
    */commits/$OID_SQ/pulls)  echo '$J_SQ' ;;
    */commits/$OID_SQH/pulls) echo '$J_SQH' ;;
    */commits/$OID_SQB/pulls) echo '$J_SQB' ;;
    */commits/$OID_SQA/pulls) echo '$J_SQA' ;;
    *) echo '[]' ;;
  esac
  exit 0
fi
br=""; forma=""
while [ \$# -gt 0 ]; do
  case "\$1" in --head) br="\$2"; shift ;; --json) forma="\$2"; shift ;; esac
  shift
done
oid=""
case "\$br" in pr-ok) oid="$OID_PR" ;; pr-after) oid="$OID_AFTER" ;; esac
case "\$forma" in
  headRefOid) printf '%s\n' "\$oid" ;;
  number)     [ -n "\$oid" ] && echo 1 || echo 0 ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

run() { (cd "$CLONE" && PATH="$TMP/bin:$PATH" bash "$SCRIPT" "$@" 2>&1); }

echo "== dry-run: quem é lixo e quem não é =="
OUT="$(run)"
check 'removeria: .*wt-anc '            "branch ancestral de origin/main é candidata"            "$OUT"
check 'removeria: .*wt-pr-ok '          "squash-mergeada com tip == head do PR é candidata"      "$OUT"
check 'wt-pr-after .*NÃO mergeada'      "commit DEPOIS do PR mergeado mantém o worktree"         "$OUT"
refute 'removeria: .*wt-pr-after'       "wt-pr-after nunca aparece como candidato"               "$OUT"
check 'wt-env .*\.env\.local difere'    ".env.local divergente segura o worktree mergeado"       "$OUT"
check 'wt-env-npmrc .*\.npmrc difere'   ".npmrc divergente segura o worktree mergeado"           "$OUT"
check 'wt-env-aninhado .*apps/x/\.env\.local difere' ".env.local de subpasta segura o worktree mergeado" "$OUT"
refute 'removeria: .*wt-env-(npmrc|aninhado) ' "nenhum dos dois aparece como candidato"         "$OUT"
check 'wt-env-bunfig .*bunfig\.toml difere'     "bunfig.toml de projeto divergente segura o worktree"     "$OUT"
check 'wt-env-npmrc-sub .*apps/y/\.npmrc difere' ".npmrc de subpasta segura o worktree"                   "$OUT"
check 'wt-env-repo .*repo aninhado ignorado: vendor/lib/' "repo aninhado ignorado segura o worktree, com o caminho" "$OUT"
refute 'removeria: .*wt-env-(bunfig|npmrc-sub|repo) ' "nenhum dos três aparece como candidato"          "$OUT"
check 'wt-env-bunfigdot .*\.bunfig\.toml difere' ".bunfig.toml (com ponto) divergente segura o worktree" "$OUT"
refute 'removeria: .*wt-env-bunfigdot '         "wt-env-bunfigdot não aparece como candidato"          "$OUT"
check 'wt-dirty .*SUJO'                 "worktree mergeado e sujo é mantido"                     "$OUT"
check 'removeria: .*wt-det-mergeado .*detached' "detached limpo num commit mergeado é lixo"      "$OUT"
check 'wt-det-env .*\.env\.local difere' "detached mergeado com .env.local divergente: fica e diz o arquivo" "$OUT"

check 'wt-ign-outputs .*ignorado.*outputs/' "outputs/ ignorado segura o worktree mergeado, com o caminho" "$OUT"
check 'removeria: .*wt-ign-cache '      "node_modules/ e apps/web/.next/ são cache: candidato"   "$OUT"
check 'removeria: .*wt-ign-venv '       "symlink .venv para o clone: candidato"                  "$OUT"
check 'wt-det-ign .*ignorado.*outputs/' "detached mergeado com outputs/ ignorado: fica"          "$OUT"
refute 'removeria: .*wt-(ign-outputs|det-ign) ' "nenhum dos dois aparece como candidato"         "$OUT"
check 'wt-ign-out .*apagaria: out/' "out/ ignorado (render) segura o worktree mergeado" "$OUT"
refute 'removeria: .*wt-ign-out '       "wt-ign-out não aparece como candidato"                  "$OUT"

echo "== --verificar: um worktree só, sem remover =="
verif() { # <esperado-exit> <regex> <descrição> <args...>
  local ex="$1" re="$2" d="$3" out rc; shift 3
  out="$(run "$@")"; rc=$?
  if [ "$rc" = "$ex" ] && printf '%s' "$out" | grep -qE "$re"; then printf '  ok    %s\n' "$d"
  else printf '  FALHA %s (exit %s, esperado %s; saída: %s)\n' "$d" "$rc" "$ex" "$(printf '%s' "$out" | tail -n 2 | tr '\n' ' ')"; falhas=$((falhas+1)); fi
}
verif 1 'keep: .*wt-ign-outputs .*outputs/'  "outputs/ ignorado: exit 1 e o caminho"   --verificar "$WTS/wt-ign-outputs"
verif 1 'keep: .*wt-ign-out .*apagaria: out/' "out/video.mp4 ignorado: exit 1 e o caminho" --verificar "$WTS/wt-ign-out"
verif 0 'pode remover: .*wt-ign-cache'       "só cache: exit 0"                         --verificar "$WTS/wt-ign-cache"
verif 0 'pode remover: .*wt-ign-venv'        "symlink: exit 0"                          --verificar "$WTS/wt-ign-venv"
verif 0 'pode remover: .*wt-anc'             "env igual ao do clone: exit 0"            --verificar "$WTS/wt-anc"
verif 1 'keep: .*wt-env .*\.env\.local difere' "env diferente: exit 1 e o arquivo"      --verificar "$WTS/wt-env"
verif 1 'keep: .*wt-env-bunfigdot .*\.bunfig\.toml difere' ".bunfig.toml diferente: exit 1" --verificar "$WTS/wt-env-bunfigdot"
verif 1 'keep: .*wt-env-repo .*repo aninhado ignorado: vendor/lib/' "repo aninhado: exit 1" --verificar "$WTS/wt-env-repo"
verif 1 'keep: .*wt-dirty .*SUJO'            "sujo: exit 1"                             --verificar "$WTS/wt-dirty"
verif 1 'keep: .*wt-pr-after .*NÃO mergeada' "commit depois do PR: exit 1"              --verificar "$WTS/wt-pr-after"
verif 0 'pode remover: .*wt-nova'            "sem commit próprio: nada a perder, exit 0" --verificar "$WTS/wt-nova"
verif 1 'keep: .*wt-det-ign .*outputs/'      "detached com outputs/: exit 1"            --verificar "$WTS/wt-det-ign"
verif 0 'pode remover: .*wt-det-mergeado'    "detached limpo e mergeado: exit 0"        --verificar "$WTS/wt-det-mergeado"
verif 2 'clone principal'                    "o clone principal: exit 2"                --verificar "$CLONE"
verif 2 'não é worktree'                     "pasta fora do repo: exit 2"               --verificar "$TMP/bin"
verif 2 'verificar'                          "--verificar com --apply: exit 2"          --verificar "$WTS/wt-anc" --apply
verif 2 'verificar'                          "--verificar sem caminho: exit 2"          --verificar
OUTV="$(cd "$WTS/wt-ign-outputs" && PATH="$TMP/bin:$PATH" bash "$SCRIPT" --verificar . 2>&1)"
check 'keep: .*wt-ign-outputs'               "de dentro do próprio worktree também avalia"  "$OUTV"
no_disco wt-ign-cache "o --verificar não remove nada"
no_disco wt-anc       "o --verificar não remove nada"

echo "== detached squash: HEAD == head de PR MERGED na main (commits/{sha}/pulls) =="
verif 0 'pode remover: .*wt-det-squash$'     "detached no head de PR mergeado na main: exit 0"  --verificar "$WTS/wt-det-squash"
verif 1 'keep: .*wt-det-squash-head .*detached' "PR mergeado com head diferente do HEAD: exit 1" --verificar "$WTS/wt-det-squash-head"
verif 1 'keep: .*wt-det-squash-base .*detached' "PR mergeado noutra base: exit 1"               --verificar "$WTS/wt-det-squash-base"
verif 1 'keep: .*wt-det-squash-aberto .*detached' "PR fechado sem merge: exit 1"                --verificar "$WTS/wt-det-squash-aberto"
verif 1 'keep: .*wt-det-squash .*sem gh nem token' "sem gh nem token: exit 1 e diz por quê"     --no-gh --verificar "$WTS/wt-det-squash"
check  'removeria: .*wt-det-squash '         "dry-run: detached no head de PR mergeado é candidato"  "$OUT"
refute 'removeria: .*wt-det-squash-(head|base|aberto) ' "os outros três não aparecem como candidatos" "$OUT"

echo "== API REST: a conta do gh não enxerga o repo =="
# O gh falha em tudo e anota que foi chamado; o curl anota argv e stdin à parte, para
# provar que o token vai pelo stdin e nunca pela linha de comando nem pela saída.
mkdir -p "$TMP/bin-rest"
cat > "$TMP/bin-rest/gh" <<GH
#!/usr/bin/env bash
echo "\$*" >> "$TMP/gh-chamado"
exit 1
GH
cat > "$TMP/bin-rest/curl" <<CURL
#!/usr/bin/env bash
echo "\$*" >> "$TMP/curl-argv"
cat >> "$TMP/curl-stdin"
case "\$*" in
  *"head=dono:rest-ok"*)          echo '$J_REST' ;;
  *"head=dono:rest-depois"*)      echo '$J_REST_X' ;;
  *"/commits/$OID_SQ/pulls"*)     echo '$J_SQ' ;;
  *"/pulls"*)                     echo '[]' ;;
  *) echo '{"message":"Not Found"}'; exit 22 ;;
esac
CURL
chmod +x "$TMP/bin-rest/gh" "$TMP/bin-rest/curl"
G config git-sync.repo dono/x; G config git-sync.tokenVar T3_TOKEN_TESTE
TOKEN="segredo-t3-$$"
runrest() { (cd "$CLONE" && env -u GH_TOKEN -u GITHUB_TOKEN GIT_SYNC_TOKENS_FILE="$TMP/nao-existe" \
  T3_TOKEN_TESTE="$TOKEN" PATH="$TMP/bin-rest:$PATH" bash "$SCRIPT" "$@" 2>&1); }
verifrest() { # <esperado-exit> <regex> <descrição> <args...>
  local ex="$1" re="$2" d="$3" out rc; shift 3
  out="$(runrest "$@")"; rc=$?
  if [ "$rc" = "$ex" ] && printf '%s' "$out" | grep -qE "$re"; then printf '  ok    %s\n' "$d"
  else printf '  FALHA %s (exit %s, esperado %s; saída: %s)\n' "$d" "$rc" "$ex" "$(printf '%s' "$out" | tail -n 2 | tr '\n' ' ')"; falhas=$((falhas+1)); fi
  RESTOUT="${RESTOUT:-}$out"
}
verifrest 0 'pode remover: .*wt-rest-ok'        "gh cego + API diz MERGED com head == tip: exit 0"   --verificar "$WTS/wt-rest-ok"
verifrest 1 'keep: .*wt-rest-depois .*NÃO mergeada' "API: commit depois do head do PR: exit 1"      --verificar "$WTS/wt-rest-depois"
verifrest 0 'pode remover: .*wt-det-squash$'    "detached squash provado pela API: exit 0"          --verificar "$WTS/wt-det-squash"
verifrest 1 'keep: .*wt-pr-ok .*NÃO mergeada'   "API sem PR para a branch: exit 1"                  --verificar "$WTS/wt-pr-ok"
refute "$TOKEN" "o token não aparece na saída"                                   "$RESTOUT"
refute "$TOKEN" "o token não vai no argv do curl"                                "$(cat "$TMP/curl-argv" 2>/dev/null)"
check  "Bearer $TOKEN" "o token vai pelo stdin do curl"                          "$(cat "$TMP/curl-stdin" 2>/dev/null)"
check  'base=main' "a consulta da API filtra a base na branch padrão"            "$(cat "$TMP/curl-argv" 2>/dev/null)"
rm -f "$TMP/gh-chamado"
verifrest 0 'pode remover: .*wt-rest-ok'        "--no-gh: prova pela API"                           --no-gh --verificar "$WTS/wt-rest-ok"
[ -e "$TMP/gh-chamado" ] && { printf '  FALHA --no-gh chamou o gh: %s\n' "$(cat "$TMP/gh-chamado")"; falhas=$((falhas+1)); } || printf '  ok    --no-gh nunca chama o gh\n'
G config git-sync.noGh true
verifrest 0 'pode remover: .*wt-rest-ok'        "git config git-sync.noGh true: prova pela API"     --verificar "$WTS/wt-rest-ok"
[ -e "$TMP/gh-chamado" ] && { printf '  FALHA git-sync.noGh chamou o gh\n'; falhas=$((falhas+1)); } || printf '  ok    git-sync.noGh nunca chama o gh\n'
G config --unset git-sync.noGh
OUTR="$(cd "$CLONE" && env -u GH_TOKEN -u GITHUB_TOKEN -u T3_TOKEN_TESTE GIT_SYNC_TOKENS_FILE="$TMP/nao-existe" PATH="$TMP/bin-rest:$PATH" bash "$SCRIPT" --verificar "$WTS/wt-rest-ok" 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '  ok    gh cego e sem token: exit 1\n' || { printf '  FALHA gh cego e sem token: exit %s\n' "$rc"; falhas=$((falhas+1)); }
check 'keep: .*wt-rest-ok .*NÃO mergeada' "gh cego e sem token: keep" "$OUTR"
G config --unset git-sync.repo; G config --unset git-sync.tokenVar

echo "== sem commit próprio: sessão recém-aberta, não branch mergeada =="
check  'wt-nova .*sem commit próprio'               "nova de origin/main, limpa: mantida"                        "$OUT"
check  'wt-sem-reflog .*sem commit próprio'         "nova com o reflog expirado (linha first-parent): mantida"   "$OUT"
check  'wt-sincronizada .*sem commit próprio'       "nova que só puxou a base (ff), com a main andando: mantida" "$OUT"
check  'wt-empilhada .*sem commit próprio'          "empilhada numa branch que depois foi mergeada: mantida"     "$OUT"
check  'wt-det .*detached sem commit próprio'       "detached no tip da main: mantido"                           "$OUT"
check  'wt-det-velho .*detached sem commit próprio' "detached num commit antigo da main: mantido"                 "$OUT"
refute 'removeria: .*wt-(nova|sem-reflog|sincronizada|empilhada|det|det-velho) ' "nenhum deles aparece como candidato" "$OUT"

echo "== --apply: o que sobrevive =="
OUT="$(run --apply)"
check 'removido: .*wt-anc'              "apply remove a ancestral"                               "$OUT"
check 'removido: .*wt-det-mergeado'     "apply remove o detached num commit mergeado"            "$OUT"
no_disco wt-pr-after     "commit sem push"
no_disco wt-env          ".env.local divergente"
no_disco wt-env-npmrc    ".npmrc divergente"
no_disco wt-env-aninhado "apps/x/.env.local só no worktree"
no_disco wt-det-env      ".env.local divergente num detached"
no_disco wt-env-bunfig   "bunfig.toml divergente"
no_disco wt-env-npmrc-sub "apps/y/.npmrc só no worktree"
no_disco wt-env-repo     "repo aninhado ignorado"
no_disco wt-dirty        "estava sujo"
no_disco wt-ign-outputs  "outputs/video.mp4 ignorado"
no_disco wt-ign-out      "out/video.mp4 ignorado"
no_disco wt-det-ign      "outputs/video.mp4 ignorado num detached"
check 'removido: .*wt-ign-cache'        "apply remove o que só tem cache"                        "$OUT"
check 'removido: .*wt-ign-venv'         "apply remove o que só tem o symlink"                    "$OUT"
[ -f "$CLONE/.venv/marca" ] && printf '  ok    alvo do symlink .venv intacto\n' || { printf '  FALHA alvo do symlink .venv apagado\n'; falhas=$((falhas+1)); }
no_disco wt-nova        "branch sem commit próprio"
no_disco wt-sem-reflog   "branch sem commit próprio"
no_disco wt-sincronizada "branch sem commit próprio"
no_disco wt-empilhada    "branch sem commit próprio"
no_disco wt-det          "detached sem commit próprio"
no_disco wt-det-velho    "detached sem commit próprio"
G branch --list pr-after | grep -q pr-after && printf '  ok    branch pr-after preservada\n' || { printf '  FALHA branch pr-after deletada\n'; falhas=$((falhas+1)); }
G branch --list nova | grep -q nova && printf '  ok    branch nova preservada\n' || { printf '  FALHA branch nova deletada\n'; falhas=$((falhas+1)); }
check 'removido: .*wt-det-squash '       "apply remove o detached no head de PR mergeado"         "$OUT"
no_disco wt-det-squash-head  "PR mergeado com head diferente"
no_disco wt-det-squash-base  "PR mergeado noutra base"
no_disco wt-det-squash-aberto "PR fechado sem merge"

echo "== branch padrão master: sem origin/main nenhum =="
ORIGIN_M="$TMP/origin-m.git"; CLONE_M="$TMP/clone-m"; WTS_M="$CLONE_M/.claude/worktrees"
git init -q --bare -b master "$ORIGIN_M"
git init -q -b master "$CLONE_M"
GM() { g -C "$CLONE_M" "$@"; }
echo base > "$CLONE_M/base.txt"; GM add base.txt; GM commit -qm base
GM remote add origin "$ORIGIN_M"; GM push -qu origin master; GM remote set-head origin master
mkdir -p "$WTS_M"
GM worktree add -q -b feat-m "$WTS_M/wt-feat-m" origin/master
g -C "$WTS_M/wt-feat-m" commit -q --allow-empty -m m
GM merge -q --no-ff -m "merge feat-m" feat-m; GM push -q origin master
GM worktree add -q -b solta-m "$WTS_M/wt-solta-m" origin/master
g -C "$WTS_M/wt-solta-m" commit -q --allow-empty -m s
runm() { (cd "$CLONE_M" && PATH="$TMP/bin:$PATH" "$@" bash "$SCRIPT" ${ARGS[@]+"${ARGS[@]}"} 2>&1); }
verifm() { # <esperado-exit> <regex> <descrição> <prefixo env...> -- <args...>
  local ex="$1" re="$2" d="$3" out rc pre=(); shift 3
  while [ "$1" != -- ]; do pre+=("$1"); shift; done; shift
  ARGS=("$@"); out="$(runm env ${pre[@]+"${pre[@]}"})"; rc=$?
  if [ "$rc" = "$ex" ] && printf '%s' "$out" | grep -qE "$re"; then printf '  ok    %s\n' "$d"
  else printf '  FALHA %s (exit %s, esperado %s; saída: %s)\n' "$d" "$rc" "$ex" "$(printf '%s' "$out" | tail -n 2 | tr '\n' ' ')"; falhas=$((falhas+1)); fi
}
verifm 0 'pode remover: .*wt-feat-m'       "mergeada em origin/master (origin/HEAD): exit 0"  -- --verificar "$WTS_M/wt-feat-m"
verifm 1 'keep: .*wt-solta-m .*NÃO mergeada' "não mergeada em master: exit 1"                 -- --verificar "$WTS_M/wt-solta-m"
ARGS=(); OUTM="$(runm env)"
check  'removeria: .*wt-feat-m '           "dry-run em repo master: a mergeada é candidata"      "$OUTM"
refute 'removeria: .*wt-solta-m '          "dry-run em repo master: a não mergeada fica"         "$OUTM"
refute 'sem gh nem token'                  "gh que responde 'nenhum PR': a negativa sai sem o sufixo" "$OUTM$(ARGS=(--verificar "$WTS_M/wt-solta-m"); runm env)"

# gh logado (o auth status passa) mas cego para o repo, e sem token da API: ninguém perguntou
# pelo PR. Sem o sufixo, "NÃO mergeada" parecia negativa provada, e as skills só aceitam a
# prova à mão quando o motivo diz "sem gh nem token da API".
GM worktree add -q --detach "$WTS_M/wt-det-m" origin/master
g -C "$WTS_M/wt-det-m" commit -q --allow-empty -m d
mkdir -p "$TMP/bin-cego"
printf '#!/usr/bin/env bash\ncase "$1" in auth) exit 0 ;; esac\necho "gh: Could not resolve to a Repository" >&2; exit 1\n' > "$TMP/bin-cego/gh"
chmod +x "$TMP/bin-cego/gh"
runcego() { (cd "$CLONE_M" && env -u GH_TOKEN -u GITHUB_TOKEN GIT_SYNC_TOKENS_FILE="$TMP/nao-existe" \
  PATH="$TMP/bin-cego:$PATH" bash "$SCRIPT" "$@" 2>&1); }
OUTC="$(runcego --verificar "$WTS_M/wt-solta-m")"; rc=$?
[ "$rc" = 1 ] && check 'keep: .*wt-solta-m .*NÃO mergeada.*sem gh nem token da API' "gh cego e sem token, branch: keep com o sufixo" "$OUTC" \
  || { printf '  FALHA gh cego e sem token, branch: exit %s\n' "$rc"; falhas=$((falhas+1)); }
OUTC="$(runcego --verificar "$WTS_M/wt-det-m")"; rc=$?
[ "$rc" = 1 ] && check 'keep: .*wt-det-m .*detached.*sem gh nem token da API' "gh cego e sem token, detached: keep com o sufixo" "$OUTC" \
  || { printf '  FALHA gh cego e sem token, detached: exit %s\n' "$rc"; falhas=$((falhas+1)); }
OUTC="$(runcego)"
check 'wt-solta-m .*NÃO mergeada.*sem gh nem token da API' "gc com gh cego: a branch sai com o sufixo"   "$OUTC"
check 'wt-det-m .*detached.*sem gh nem token da API'       "gc com gh cego: o detached sai com o sufixo" "$OUTC"
refute 'removeria: .*wt-(solta|det)-m '                    "gc com gh cego: nada vira candidato"        "$OUTC"
# git >= 2.48 recria o origin/HEAD no fetch que o gc faz: sem isto o fallback nem roda
GM config remote.origin.followRemoteHEAD never
GM remote set-head origin -d
verifm 0 'pode remover: .*wt-feat-m'       "sem origin/HEAD, pelo 'git remote show origin': exit 0" -- --verificar "$WTS_M/wt-feat-m"
GM remote set-url origin "$TMP/nao-existe.git"
verifm 0 'pode remover: .*wt-feat-m'       "sem origin/HEAD nem remoto, pelo gh repo view: exit 0" FAKE_DEF=master -- --verificar "$WTS_M/wt-feat-m"
verifm 1 'keep: .*wt-feat-m .*branch padrão' "sem nada que diga a padrão: keep com o motivo"  -- --verificar "$WTS_M/wt-feat-m"
verifm 1 'keep: .*wt-feat-m .*branch padrão' "--no-gh também não pergunta ao gh"              FAKE_DEF=master -- --no-gh --verificar "$WTS_M/wt-feat-m"
ARGS=(--apply); OUTM="$(runm env)"; rcm=$?
[ "$rcm" != 0 ] && printf '  ok    gc sem branch padrão sai != 0\n' || { printf '  FALHA gc sem branch padrão saiu 0\n'; falhas=$((falhas+1)); }
check 'branch padrão' "gc sem branch padrão diz por quê" "$OUTM"
[ -d "$WTS_M/wt-feat-m" ] && printf '  ok    gc sem branch padrão não remove nada\n' || { printf '  FALHA gc sem branch padrão removeu wt-feat-m\n'; falhas=$((falhas+1)); }

# O --verificar atualiza as refs remotas (fetch --prune). Quem chama em série, como o
# aplicar.sh da limpeza-mac, busca uma vez por repo e pula o do gc com WORKTREE_GC_SKIP_FETCH=1.
echo "== WORKTREE_GC_SKIP_FETCH=1: o --verificar não busca =="
G push -q origin "$BASE:refs/heads/so-no-remoto"
G update-ref -d refs/remotes/origin/so-no-remoto 2>/dev/null
tem_ref() { G rev-parse -q --verify refs/remotes/origin/so-no-remoto >/dev/null && echo sim || echo nao; }
(cd "$CLONE" && WORKTREE_GC_SKIP_FETCH=1 PATH="$TMP/bin:$PATH" bash "$SCRIPT" --verificar "$WTS/wt-nova" >/dev/null 2>&1)
check '^nao$' "com a variável, a ref remota nova não chega"  "$(tem_ref)"
run --verificar "$WTS/wt-nova" >/dev/null
check '^sim$' "sem ela, o --verificar busca"                 "$(tem_ref)"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
