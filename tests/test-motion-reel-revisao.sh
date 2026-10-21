#!/usr/bin/env bash
# Revisão de motion, glossário reverso e "por que isso se move" da motion-reel (lote 8 do plano de
# motion, itens 3, 7 e a linha do C2 do item 8):
#   1. o passo 7 (QA) do SKILL.md traz as quatro perguntas da folha de transição, a tabela
#      Antes | Depois | Por quê com veredito Bloqueia/Aprova, a ordem de correção e o revisar.sh faixa;
#   2. o vocabulario.md tem o glossário reverso (nome do efeito → onde está), e todo nome em crase
#      da coluna "Onde está" existe no código do template; as lacunas e o "nunca ease-in" que não
#      vale aqui estão declarados;
#   3. o checklist do storyboard (briefing-motion.md) e o resumo dele no passo 1 do SKILL.md
#      perguntam por que cada coisa se move.
#
# Uso: bash tests/test-motion-reel-revisao.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SK="$RAIZ/plugin/skills/motion-reel"
SRC="$SK/assets/template/src"
PY="$(command -v python3)" || { echo "python3 ausente"; exit 2; }
[ -d "$SRC" ] || { echo "template não encontrado em $SRC"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-revisao.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

"$PY" - "$SK" "$SRC" > "$TMP/r.log" 2>&1 <<'PY'
import pathlib, re, sys
sk, src = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
skill = (sk / "SKILL.md").read_text(encoding="utf-8")
voc = (sk / "references/vocabulario.md").read_text(encoding="utf-8")
brief = (sk / "references/briefing-motion.md").read_text(encoding="utf-8")
codigo = "\n".join(p.read_text(encoding="utf-8") for p in src.glob("*.tsx"))

def r(chave, ok, extra=""):
    print(chave, "ok" if ok else "fail", extra)

# 1. passo 7 do SKILL.md
i7, i8 = skill.find("7. **QA:**"), skill.find("8. **Entrega:**")
p7 = re.sub(r"\s+", " ", skill[i7:i8]) if 0 <= i7 < i8 else ""
r("p7", bool(p7))
r("perguntas", all(q in p7 for q in ("dois estados", "para de repente", "cresce do ponto certo", "sincronia")))
r("tabela", "| Antes | Depois | Por quê |" in p7)
r("veredito", "**Bloqueia**" in p7 and "**Aprova**" in p7)
r("ordem", re.search(r"apagar.*reduzir.*trocar a curva.*corrigir a origem.*polir", p7, re.S) is not None)
r("faixa", "revisar.sh faixa" in p7)
r("checklist-da-folha", "Checklist da folha" in p7)

# 2. glossário reverso
m = re.search(r"^## Glossário reverso.*?(?=^## )", voc, re.S | re.M)
g = m.group(0) if m else ""
gs = re.sub(r"\s+", " ", g)
r("glossario", bool(g))
linhas = [l for l in g.splitlines() if l.startswith("| ") and not l.startswith("| Efeito") and not l.startswith("|---")]
r("linhas", len(linhas) >= 12, f"({len(linhas)} linhas)")
faltam = []
for l in linhas:
    cols = [c.strip() for c in l.strip("|").split("|")]
    if len(cols) < 2:
        faltam.append(l); continue
    for nome in re.findall(r"`([^`]+)`", cols[1]):
        ident = nome.rstrip("()").strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", ident):
            continue
        if not re.search(r"\b%s\b" % re.escape(ident), codigo):
            faltam.append(ident)
r("nomes-existem", not faltam, " ".join(faltam))
for efeito in ("stagger", "mask reveal", "line drawing", "number ticker", "match cut", "typewriter", "ripple", "anticipation"):
    r("efeito:" + efeito.replace(" ", "_"), any(l.lower().startswith("| " + efeito) for l in linhas))
r("lacunas", all(k in gs for k in ("before/after slider", "parallax", "follow-through", "squash & stretch", "skeleton")))
r("ease-in", "`EXIT`" in gs and "ease-in" in gs)
r("credito", "Emil Kowalski" in gs and "MIT" in gs)

# 3. por que isso se move
ck = brief[brief.find("### Checklist do storyboard"):brief.find("## 4.")]
r("c2-briefing", "Por que isso se move" in ck)
i1, i2 = skill.find("1. **Briefing"), skill.find("2. **Marca.**")
r("c2-skill", "por que cada coisa se move" in skill[i1:i2])
PY
desc() { case "$1" in
  p7) echo "o SKILL.md tem os passos 7 (QA) e 8 (Entrega)";;
  perguntas) echo "passo 7: as quatro perguntas (dois estados, curva que para, origem da escala, sincronia)";;
  tabela) echo "passo 7: achados na tabela Antes | Depois | Por quê";;
  veredito) echo "passo 7: veredito Bloqueia ou Aprova";;
  ordem) echo "passo 7: ordem de correção (apagar, reduzir, trocar a curva, corrigir a origem, polir)";;
  faixa) echo "passo 7: cita o revisar.sh faixa";;
  checklist-da-folha) echo "passo 7: aponta o Checklist da folha da doutrina em vez de repetir";;
  glossario) echo "vocabulario.md tem a seção Glossário reverso";;
  linhas) echo "o glossário tem pelo menos 12 efeitos";;
  nomes-existem) echo "todo nome em crase da coluna Onde está existe no template";;
  efeito:*) e="${1#efeito:}"; echo "o glossário tem ${e//_/ }";;
  lacunas) echo "lacunas declaradas (before/after slider, parallax, follow-through, squash & stretch, skeleton)";;
  ease-in) echo "registra que o \"nunca ease-in\" não vale aqui (EXIT)";;
  credito) echo "crédito do Emil Kowalski (MIT)";;
  c2-briefing) echo "checklist do storyboard: Por que isso se move";;
  c2-skill) echo "passo 1 do SKILL.md: por que cada coisa se move";;
  *) echo "$1";;
esac; }
while read -r chave res extra; do
  [ -n "$chave" ] || continue
  check "$(desc "$chave")${extra:+ $extra}" "$res"
done < "$TMP/r.log"
/usr/bin/grep -q " ok\| fail" "$TMP/r.log" || { cat "$TMP/r.log"; falhas=$((falhas+1)); }

echo
if [ "$falhas" = 0 ]; then echo "tudo ok"; else echo "$falhas falha(s)"; fi
[ "$falhas" = 0 ]
