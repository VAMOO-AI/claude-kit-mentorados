#!/usr/bin/env bash
# paridade.sh — o que este kit e o claude-config-team têm em comum ainda cobre o mesmo?
#
# Os dois kits compartilham hooks, scripts, skills e testes, e TODOS divergem no arquivo:
# aqui os hooks leem o payload por node (`hookjson.js`), lá por `jq`; as skills não têm o
# prefixo `vamoo-`; a instalação é plugin de um lado e `update.sh` do outro. Em 04/09/2026
# a divergência era 13/13 hooks, 16/16 skills e 13/13 testes — sem ninguém conseguir dizer
# o que era adaptação deliberada e o que era porte atrasado.
#
# Comparar bytes seria inútil (a divergência é o desenho). O que dá para comparar é
# COBERTURA: a lista de casos de cada suíte. Um caso é a descrição entre aspas de um
# `check`/`ok` — se um lado testa "heredoc não conta" e o outro não, é porte faltando,
# não estilo. `docs/paridade.md` registra a decisão item a item; este script mostra o
# estado de hoje.
#
# Uso:
# A lista de casos "sem par aqui" é ponto de partida, não dívida confirmada: as duas
# suítes descrevem o mesmo caso com palavras diferentes, e parte da cobertura do time é de
# fluxo que este kit não tem (db-query.sh, cofre de tokens). Quem lê decide, e registra a
# decisão em docs/paridade.md — o script não adivinha intenção.
#
# Uso:
#   bash scripts/paridade.sh              # relatório de cobertura (até 5 casos por suíte)
#   bash scripts/paridade.sh --detalhe    # lista todos os casos
#   bash scripts/paridade.sh --check      # sai 1 se alguma suíte do time não existe aqui
#   TEAM_REPO=<caminho> bash scripts/paridade.sh
#
#   bash scripts/paridade.sh --arquivos   # hash de skills e hooks que existem nos dois
#   bash scripts/paridade.sh --arquivos --json
#   bash scripts/paridade.sh --arquivos --kit <raiz> --time <raiz>
#
# --arquivos compara o conteúdo (sha256 do blob no HEAD) de plugin/skills/<x>/ com
# skills/<x>/ (ou skills/vamoo-<x>/ quando a pasta do time tem o prefixo) e de
# plugin/hooks/<arquivo> com hooks/<arquivo>. Lista o que divergiu e qual lado é mais
# novo pela data do último commit que tocou o arquivo. Arquivo fora do git não entra.
# Exceções em scripts/paridade.ignore. Sai 0 mesmo com divergência (o CI só avisa) e 2
# se o clone do time não estiver no disco.
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="${TEAM_REPO:-$HOME/WORKSPACES/claude-config-team}"
CHECK=0; DETALHE=0; ARQUIVOS=0; JSON=0
KIT_DIR=""; TIME_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --detalhe) DETALHE=1; shift ;;
    --arquivos) ARQUIVOS=1; shift ;;
    --json) JSON=1; shift ;;
    --kit) KIT_DIR="${2:-}"; shift 2 ;;
    --time) TIME_DIR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ "$ARQUIVOS" -eq 1 ]]; then
  KIT_DIR="${KIT_DIR:-$RAIZ}"
  TIME_DIR="${TIME_DIR:-$TEAM}"
  if [[ ! -d "$TIME_DIR" ]]; then
    echo "kit do time não encontrado em $TIME_DIR — clone-o ou aponte --time / TEAM_REPO." >&2
    exit 2
  fi
  exec python3 - "$KIT_DIR" "$TIME_DIR" "$RAIZ/scripts/paridade.ignore" "$JSON" <<'PY'
import fnmatch, hashlib, json, os, subprocess, sys

kit_root, time_root, ignore_path, want_json = sys.argv[1:]
want_json = want_json == "1"

def raiz_de(root, plugin_name, plain_name):
    plugin = os.path.join(root, "plugin", plugin_name)
    plain = os.path.join(root, plain_name)
    if os.path.isdir(plugin):
        return plugin
    if os.path.isdir(plain):
        return plain
    return None

def arquivos(repo, root):
    # Só o que está no HEAD. Bytecode solto e arquivo não commitado não são
    # divergência entre os repositórios.
    achados = {}
    if not root or not os.path.isdir(root):
        return achados
    rel_root = os.path.relpath(root, repo).replace(os.sep, "/")
    if rel_root == ".":
        rel_root = ""
    proc = subprocess.run(
        ["git", "-C", repo, "ls-files", "-z", "--", rel_root or "."],
        capture_output=True,
    )
    if proc.returncode != 0:
        return achados
    prefixo = (rel_root + "/") if rel_root else ""
    for bruto in proc.stdout.split(b"\0"):
        if not bruto:
            continue
        rel_repo = bruto.decode("utf-8", "surrogateescape")
        if prefixo and not rel_repo.startswith(prefixo):
            continue
        rel = rel_repo[len(prefixo):] if prefixo else rel_repo
        if not rel:
            continue
        blob = subprocess.run(
            ["git", "-C", repo, "show", f"HEAD:{rel_repo}"],
            capture_output=True,
        )
        if blob.returncode != 0:
            continue
        achados[rel] = hashlib.sha256(blob.stdout).hexdigest()
    return achados

def padroes(path):
    if not os.path.isfile(path):
        return []
    saida = []
    with open(path, encoding="utf-8") as fh:
        for linha in fh:
            s = linha.split("#", 1)[0].strip()
            if s:
                saida.append(s)
    return saida

def ignorado(tipo, nome, rel, pats):
    candidatos = [f"{tipo}/{nome}/{rel}", f"{nome}/{rel}", rel, f"{tipo}/{nome}"]
    for pat in pats:
        for c in candidatos:
            if c and fnmatch.fnmatch(c, pat):
                return True
    return False

def commit(repo, rel):
    proc = subprocess.run(
        ["git", "-C", repo, "log", "-1", "--format=%cs %ct", "--", rel],
        capture_output=True, text=True,
    )
    linha = (proc.stdout or "").strip()
    if not linha or " " not in linha:
        return None, None
    dia, ts = linha.split(" ", 1)
    try:
        return dia, int(ts)
    except ValueError:
        return dia, None

def lado(sha, dia):
    if sha is None:
        return None
    return {"sha256": sha, "commit": dia}

def mais_novo(tem_kit, tem_time, ts_kit, ts_time):
    if tem_kit and not tem_time:
        return "kit"
    if tem_time and not tem_kit:
        return "time"
    if ts_kit is None and ts_time is None:
        return "desconhecido"
    if ts_kit is None:
        return "time"
    if ts_time is None:
        return "kit"
    if ts_kit > ts_time:
        return "kit"
    if ts_time > ts_kit:
        return "time"
    return "empate"

kit_skills = raiz_de(kit_root, "skills", "skills")
time_skills = raiz_de(time_root, "skills", "skills")
kit_hooks = raiz_de(kit_root, "hooks", "hooks")
time_hooks = raiz_de(time_root, "hooks", "hooks")
if kit_skills is None and kit_hooks is None:
    print(f"layout de skills/hooks não reconhecido em {kit_root}", file=sys.stderr)
    sys.exit(2)
if time_skills is None and time_hooks is None:
    print(f"layout de skills/hooks não reconhecido em {time_root}", file=sys.stderr)
    sys.exit(2)

pats = padroes(ignore_path)
iguais = 0
ignorados = 0
so_num_lado = []
divergencias = []

def registrar(tipo, nome, nome_time, rel, sha_kit, sha_time, rel_kit, rel_time):
    global iguais, ignorados
    if ignorado(tipo, nome, rel, pats):
        ignorados += 1
        return
    tem_kit = sha_kit is not None
    tem_time = sha_time is not None
    if tem_kit and tem_time and sha_kit == sha_time:
        iguais += 1
        return
    dia_kit, ts_kit = commit(kit_root, rel_kit) if tem_kit else (None, None)
    dia_time, ts_time = commit(time_root, rel_time) if tem_time else (None, None)
    item = {
        "tipo": tipo,
        "nome": nome,
        "arquivo": rel,
        "kit": lado(sha_kit, dia_kit),
        "time": lado(sha_time, dia_time),
        "mais_novo": mais_novo(tem_kit, tem_time, ts_kit, ts_time),
    }
    if nome_time != nome:
        item["nome_time"] = nome_time
    divergencias.append(item)

def comparar_arvores(tipo, nome, nome_time, root_kit, root_time, prefixo_kit, prefixo_time):
    ak = arquivos(kit_root, root_kit)
    at = arquivos(time_root, root_time)
    for rel in sorted(set(ak) | set(at)):
        registrar(
            tipo, nome, nome_time, rel,
            ak.get(rel), at.get(rel),
            f"{prefixo_kit}/{rel}" if prefixo_kit else rel,
            f"{prefixo_time}/{rel}" if prefixo_time else rel,
        )

pares_time = set()
if kit_skills and time_skills:
    nomes_kit = sorted(d for d in os.listdir(kit_skills) if os.path.isdir(os.path.join(kit_skills, d)))
    for nome in nomes_kit:
        if os.path.isdir(os.path.join(time_skills, nome)):
            nome_time = nome
        elif os.path.isdir(os.path.join(time_skills, f"vamoo-{nome}")):
            nome_time = f"vamoo-{nome}"
        else:
            so_num_lado.append(f"skill/{nome}")
            continue
        pares_time.add(nome_time)
        comparar_arvores(
            "skill", nome, nome_time,
            os.path.join(kit_skills, nome), os.path.join(time_skills, nome_time),
            os.path.relpath(os.path.join(kit_skills, nome), kit_root).replace(os.sep, "/"),
            os.path.relpath(os.path.join(time_skills, nome_time), time_root).replace(os.sep, "/"),
        )
    for nome in sorted(os.listdir(time_skills)):
        if not os.path.isdir(os.path.join(time_skills, nome)) or nome in pares_time:
            continue
        so_num_lado.append(f"skill/{nome}")

if kit_hooks and time_hooks:
    hk = arquivos(kit_root, kit_hooks)
    ht = arquivos(time_root, time_hooks)
    pref_k = os.path.relpath(kit_hooks, kit_root).replace(os.sep, "/")
    pref_t = os.path.relpath(time_hooks, time_root).replace(os.sep, "/")
    for nome in sorted(set(hk) | set(ht)):
        if nome not in hk or nome not in ht:
            if nome in hk:
                so_num_lado.append(f"hook/{nome}")
            else:
                so_num_lado.append(f"hook/{nome}")
            continue
        registrar(
            "hook", nome, nome, nome,
            hk[nome], ht[nome],
            f"{pref_k}/{nome}", f"{pref_t}/{nome}",
        )
elif kit_hooks:
    for nome in sorted(arquivos(kit_root, kit_hooks)):
        so_num_lado.append(f"hook/{nome}")
elif time_hooks:
    for nome in sorted(arquivos(time_root, time_hooks)):
        so_num_lado.append(f"hook/{nome}")

divergencias.sort(key=lambda i: (i["tipo"], i["nome"], i["arquivo"]))
so_num_lado.sort()
relatorio = {
    "kit": kit_root,
    "time": time_root,
    "iguais": iguais,
    "ignorados": ignorados,
    "so_num_lado": so_num_lado,
    "divergencias": divergencias,
}

if want_json:
    json.dump(relatorio, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
else:
    print(f"paridade de arquivos")
    print(f"kit:  {kit_root}")
    print(f"time: {time_root}")
    print(f"iguais: {iguais}    ignorados: {ignorados}    divergiram: {len(divergencias)}")
    for item in divergencias:
        caminho = f"{item['tipo']}/{item['nome']}/{item['arquivo']}" if item["tipo"] == "skill" else f"hook/{item['arquivo']}"
        def quando(lado_):
            if lado_ is None:
                return "ausente"
            return lado_["commit"] or "sem commit"
        print(f"divergiu  {caminho}  mais novo: {item['mais_novo']}  (kit {quando(item['kit'])}, time {quando(item['time'])})")
    if so_num_lado:
        print("só num lado (não entra na comparação de hash): " + ", ".join(so_num_lado))
sys.exit(0)
PY
fi

if [ ! -d "$TEAM" ]; then
  echo "kit do time não encontrado em $TEAM — clone-o ou aponte TEAM_REPO." >&2
  exit 2
fi

# casos <arquivo>: uma linha por caso testado (a descrição do check/ok), normalizada —
# sem o prefixo `vamoo-` das skills, que só existe no time.
#
# O extrator precisa estar ANCORADO no início da linha. A versão anterior era
# `grep -oE '(check|ok|...)[^"]*"[^"]+"'`, que casava qualquer linha de shell com a
# substring "ok"/"check" seguida de aspas — e o relatório passou a acusar 47 casos
# "sem par" chamados ` ]; then bash \`, `"$c"` e `" de "`. Relatório que mente assim
# ninguém lê, e ele existe justamente para a divergência entre os kits não voltar a 100%.
#
# Onde fica a descrição depende do helper, e as duas famílias existem nos dois repos:
#   check "descrição" ...            check bloqueia "descrição" "comando"
#   check 'regex-esperado' "descrição" "$OUT"        → a 1ª entre ASPAS DUPLAS
#   espera_rc 0 "$rc" "descrição"    contem "$arq" "agulha" "descrição"  → a ÚLTIMA
# Argumento que é valor (`"$rc"`, `"$(...)"`) ou não tem letra nenhuma não é descrição:
# pula para o próximo candidato em vez de derrubar o caso.
casos() {
  [ -f "$1" ] || return 0
  awk '
    function aceita(s) {
      if (s == "") return 0
      if (s ~ /^\$/) return 0        # "$rc", "$OUT": valor, não descrição
      if (s ~ /\$\(/) return 0       # "$(...)": comando
      if (s !~ /[A-Za-z]/) return 0  # "0", "]; then": fragmento de shell
      return 1
    }
    function descricao(linha, qual,   n, p, i, ultimo) {
      n = split(linha, p, "\"")      # conteúdo entre aspas duplas = campos pares
      ultimo = ""
      for (i = 2; i <= n - 1; i += 2) {
        if (!aceita(p[i])) continue
        if (qual == "primeiro") return p[i]
        ultimo = p[i]
      }
      return (qual == "primeiro") ? "" : ultimo
    }
    # A linha que DEFINE o helper não é caso — e ela cita o próprio nome.
    /^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*\(\)/ { next }
    {
      # Começo de comando: início da linha, ou depois de ";" / "&&" / "||" — há suíte
      # que escreve `linhas 700; check "" "700 linhas: faixa 600" "$(run s1)"`. E só
      # contam os argumentos DEPOIS do helper: senão uma linha como
      # `grep -qF "# gatilho: $g" ... && ok "..."` doaria o texto do grep como caso.
      if (match($0, /(^|;|&&|\|\|)[[:space:]]*(check|ok)[[:space:]]+/)) {
        d = descricao(substr($0, RSTART + RLENGTH), "primeiro")
        if (d != "") print d
        next
      }
      if (match($0, /(^|;|&&|\|\|)[[:space:]]*(espera_rc|contem|nao_contem)[[:space:]]+/)) {
        d = descricao(substr($0, RSTART + RLENGTH), "ultimo")
        if (d != "") print d
        next
      }
    }
  ' "$1" 2>/dev/null \
    | sed -E 's/vamoo-//g; s/plugin\///g; s/[[:space:]]+/ /g' \
    | sort -u
}

# casos_lote <arquivo>... — a união dos casos de VÁRIOS arquivos, numa ordem só.
# `casos` já sai ordenado, mas concatenar dois arquivos ordenados devolve duas corridas
# ordenadas, não um fluxo ordenado — e o `comm` lá embaixo aceita isso calado e responde
# lixo. Por isso o `sort -u` final.
casos_lote() {
  local f
  for f in "$@"; do casos "$f"; done | sort -u
}

# par <teste-daqui> <teste(s)-do-time>
# O lado do time aceita MAIS DE UM arquivo, separados por vírgula: a divisão em arquivos
# não é a mesma dos dois lados. Aqui `test-skills-projeto.sh` cobre o scan e o hook num
# arquivo só; lá são `test-skills-projeto-scan.sh` e `test-warn-skills-projeto.sh`. Com o
# par resolvido por nome EXATO, declarar `test-skills-projeto.sh|test-skills-projeto.sh`
# imprimia "só aqui" para sempre — inclusive DEPOIS do porte pronto, que é o mesmo
# relatório-que-mente que o extrator ancorado acabou de consertar.
declare_pares() {
  cat <<'PARES'
test-block-cd-leitura-relativa.sh|test-block-cd-leitura-relativa.sh
test-block-delete-branch.sh|test-block-delete-branch.sh
test-block-main-commit.sh|test-block-main-commit.sh
test-block-parallel-clone-switch.sh|test-block-parallel-clone-switch.sh
test-check-careful.sh|test-check-careful.sh
test-git-sync-cleanup.sh|test-git-sync-cleanup.sh
test-git-sync-conta.sh|test-git-sync-conta.sh
test-git-sync-aviso-push.sh|test-git-sync-aviso-push.sh
test-git-sync-mural.sh|test-git-sync-mural.sh
test-git-sync-voltar-main.sh|test-git-sync-voltar-main.sh
test-hitl-loop.sh|test-hitl-loop.sh
test-hooks-boot.sh|test-settings-boot.sh
test-kit-setup-subagentes.sh|test-update-subagentes.sh
test-memoria-indice.sh|test-memoria-indice.sh
test-memoria-link.sh|test-memoria-link.sh
test-lint-modificados.sh|test-lint-modificados.sh
test-merge-settings.sh|test-merge-settings.sh
test-path-rules.sh|test-path-rules.sh
test-pre-bash.sh|test-pre-bash.sh
test-pressure-isolamento.sh|test-pressure-isolamento.sh
test-pre-prompt.sh|test-pre-prompt.sh
test-precompact.sh|test-precompact.sh
test-session-size-guard.sh|test-session-size-guard.sh
test-simular-conversa.sh|test-simular-conversa.sh
test-skill-descriptions.sh|test-skill-descriptions.sh
test-skill-sem-injecao.sh|test-skill-sem-injecao.sh
test-skill-spec.sh|test-skill-spec.sh
test-skills-projeto.sh|test-skills-projeto-scan.sh,test-warn-skills-projeto.sh
test-warn-branch-worktree.sh|test-warn-branch-behind.sh,test-warn-worktree-stale.sh
test-warn-sem-node.sh|test-warn-sem-jq.sh
test-worktree-gc.sh|test-worktree-gc.sh
PARES
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ausentes=0; divergentes=0; ilegiveis=0
printf '%-38s %5s %5s  %s\n' "suíte" "aqui" "time" "cobertura"
while IFS='|' read -r meu dele; do
  [ -n "$meu" ] || continue
  [ -n "$dele" ] || continue
  a="$RAIZ/tests/$meu"
  IFS=',' read -r -a nomes_time <<< "$dele"
  bs=(); faltam_la=(); tem_la=0
  for d in "${nomes_time[@]}"; do
    bs+=("$TEAM/tests/$d")
    if [ -f "$TEAM/tests/$d" ]; then tem_la=$((tem_la+1)); else faltam_la+=("$d"); fi
  done
  # Sem o rótulo, `37 42 ok` não deixa ver que o lado direito são dois arquivos.
  rotulo="$meu"; [ "${#bs[@]}" -gt 1 ] && rotulo="$meu (${#bs[@]} no time)"
  if [ ! -f "$a" ] && [ "$tem_la" -eq 0 ]; then continue; fi
  if [ ! -f "$a" ]; then printf '%-38s %5s %5s  SÓ NO TIME — suíte inteira sem par\n' "$rotulo" "-" "$(casos_lote "${bs[@]}" | wc -l | tr -d ' ')"; ausentes=$((ausentes+1)); continue; fi
  if [ "$tem_la" -eq 0 ]; then printf '%-38s %5s %5s  só aqui\n' "$rotulo" "$(casos "$a" | wc -l | tr -d ' ')" "-"; continue; fi
  # Meia união é a mesma mentira de antes com outra cara: comparar contra a metade que
  # chegou imprimiria "ok" escondendo o arquivo que ainda falta lá.
  if [ "$tem_la" -ne "${#bs[@]}" ]; then
    printf '%-38s %5s %5s  porte do time PELA METADE — falta(m) lá: %s\n' \
      "$rotulo" "$(casos "$a" | wc -l | tr -d ' ')" "$(casos_lote "${bs[@]}" | wc -l | tr -d ' ')" "${faltam_la[*]}"
    divergentes=$((divergentes+1)); continue
  fi
  casos "$a" > "$TMP/a"; casos_lote "${bs[@]}" > "$TMP/b"
  na=$(wc -l < "$TMP/a" | tr -d ' '); nb=$(wc -l < "$TMP/b" | tr -d ' ')
  # Suíte que não usa check/ok (só printf, como a de descriptions) não tem caso para
  # extrair. Isso é diferente de suíte em dia, e no formato antigo saía como "0 0 ok" —
  # indistinguível de uma que regrediu a zero caso.
  if [ "$na" -eq 0 ] && [ "$nb" -eq 0 ]; then
    printf '%-38s %5s %5s  sem casos legíveis (não usa check/ok — nada a comparar)\n' "$rotulo" 0 0
    ilegiveis=$((ilegiveis+1)); continue
  fi
  faltando=$(comm -13 "$TMP/a" "$TMP/b" | wc -l | tr -d ' ')
  if [ "$faltando" -eq 0 ]; then printf '%-38s %5s %5s  ok\n' "$rotulo" "$na" "$nb"
  else
    printf '%-38s %5s %5s  %s caso(s) do time sem par textual\n' "$rotulo" "$na" "$nb" "$faltando"
    if [ "$DETALHE" -eq 1 ]; then comm -13 "$TMP/a" "$TMP/b" | sed 's/^/      · /'
    else comm -13 "$TMP/a" "$TMP/b" | head -5 | sed 's/^/      · /'
         [ "$faltando" -gt 5 ] && printf '      … e mais %s (--detalhe)\n' "$((faltando - 5))"; fi
    divergentes=$((divergentes+1))
  fi
done < <(declare_pares)

echo
[ "$ilegiveis" -gt 0 ] && echo "$ilegiveis suíte(s) sem caso legível — a comparação de cobertura não alcança essas."
if [ "$ausentes" -eq 0 ] && [ "$divergentes" -eq 0 ]; then
  echo "cobertura em dia com o kit do time."
else
  [ "$ausentes"    -gt 0 ] && echo "$ausentes suíte(s) do time não existem aqui — porte, ou registre em docs/paridade.md por que não se aplica."
  [ "$divergentes" -gt 0 ] && echo "$divergentes suíte(s) com caso do time sem par TEXTUAL — leia antes de portar: a mesma prova pode estar escrita com outras palavras, e parte é fluxo que este kit não tem."
  echo "A decisão item a item mora em docs/paridade.md."
  { [ "$CHECK" -eq 1 ] && [ "$ausentes" -gt 0 ]; } && exit 1
fi
exit 0
