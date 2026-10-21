#!/usr/bin/env python3
"""film.json + duração real de cada fala (public/vo/<id>.wav) → src/tl-<formato>.json.

Cada cena: f = 0 no corte. A 1ª fala entra em `pre` frames, as seguintes depois de `gap`
(+ gaps[k] extra depois da fala k), e a cena termina `post` frames após a última fala; nunca
menos que `min`. A duração sobe para o próximo múltiplo de 15 (120 BPM a 30 fps): todo corte
cai na batida. Cena sem `in` herda a corrente do filme (`"current"` no film.json, padrão `whip`):
uma transição dominante na mesma direção; `in` explícito só onde a troca tem motivo.

Fala sem WAV ainda (storyboard antes da voz): a duração é estimada pelo texto do vo.json
(~14 caracteres/s) e o script avisa. Rode de novo depois do split-vo.py.

Leitura: o texto da tela (props, ou a lista `read` da cena, quando o autor declara só o que o
espectador precisa ler) pede 2,5 palavras/s + 0,5 s. A moldura de UI (sessão, arquivos, status,
painel ilustrativo, botão, palavra de fundo) não conta. Cena mais curta que isso ganha aviso de leitura curta; o
cálculo vai em `read` ({words, need, secs}) de cada cena da timeline, que o storyboard mostra.
Uso: build-timeline.py [master|reel ...]   (sem argumento: todos os formatos do film.json)
"""
import json, math, pathlib, sys, wave

ROOT = pathlib.Path(__file__).resolve().parent.parent
FPS, BEAT = 30, 15
CPS = 14  # estimativa sem WAV
CURRENT = "whip"  # corrente padrão (doutrina de motion, regra 6): repita a corrente, varie só com motivo
D = {"iris": 14, "ink": 16, "whip": 10, "whipUp": 10, "push": 12, "bars": 18, "glitch": 10, "panel": 18, "spin": 12, "echo": 12, "cut": 0}
FORMATS = ("master", "reel")
# Motion blur real (CameraMotionBlur) nas transições rápidas: opt-in no film.json. Cada quadro da
# troca vira `samples` renders somados, então o padrão é 8 e o teto é 16.
BLUR_PADRAO = {"samples": 8, "shutter": 180}


def motion_blur(film):
    v = film.get("motionBlur")
    if v in (None, False):
        return None
    if v is True:
        return dict(BLUR_PADRAO)
    if not isinstance(v, dict):
        sys.exit(f"!! motionBlur: use true, false ou {{\"samples\": 2–16, \"shutter\": 1–360}} (veio {v!r})")
    sobra = set(v) - {"samples", "shutter", "shutterAngle"}
    if sobra:
        sys.exit(f"!! motionBlur: chave desconhecida {', '.join(sorted(sobra))} (use samples e shutter)")
    mb = dict(BLUR_PADRAO)
    if "shutterAngle" in v:
        mb["shutter"] = v["shutterAngle"]  # o nome da prop do CameraMotionBlur também vale
    mb.update({k: v[k] for k in ("samples", "shutter") if k in v})
    num = lambda x: isinstance(x, (int, float)) and not isinstance(x, bool)
    if not (num(mb["samples"]) and float(mb["samples"]).is_integer() and 2 <= mb["samples"] <= 16):
        sys.exit(f"!! motionBlur.samples precisa ser inteiro de 2 a 16 (veio {mb['samples']!r})")
    if not (num(mb["shutter"]) and 1 <= mb["shutter"] <= 360):
        sys.exit(f"!! motionBlur.shutter precisa ser um número de 1 a 360 graus (veio {mb['shutter']!r})")
    mb["samples"] = int(mb["samples"])
    return mb


def paises():
    """Nomes do world-atlas do projeto (node_modules), ou None antes do npm ci."""
    p = ROOT / "node_modules/world-atlas/countries-110m.json"
    if not p.is_file():
        return None
    geo = json.loads(p.read_text(encoding="utf-8"))["objects"]["countries"]["geometries"]
    return {g.get("properties", {}).get("name") for g in geo}


def validar(name, idx, s):
    """Props que quebram a cena em silêncio viram erro aqui, com o motivo."""
    p, onde = s.get("props") or {}, f"{name} cena {idx} ({s['type']})"
    if s["type"] == "map":
        rota = p.get("route") or []
        distintas = {tuple(r.get("at") or ()) for r in rota if isinstance(r, dict)}
        if len(rota) > 6:
            sys.exit(f"!! {onde}: route tem {len(rota)} paradas; o máximo é 6")
        if not p.get("region") and len(distintas) < 2:
            sys.exit(f"!! {onde}: sem region, route precisa de 2 a 6 paradas em lugares diferentes")
        nomes = paises() if p.get("region") else None
        if nomes is not None and p["region"] not in nomes:
            sys.exit(f"!! {onde}: a região {p['region']!r} não existe no Natural Earth (use o nome em inglês, ex.: \"Brazil\")")
    if s["type"] == "morph":
        n = len(p.get("states") or [])
        if not 1 <= n <= 8:
            sys.exit(f"!! {onde}: states precisa de 1 a 8 estados (veio {n})")
WPS, PAD = 2.5, 0.5  # leitura: palavras por segundo + respiro da cena
# Props que não são leitura: arquivo, tipo, cor, a moldura de UI (sessão, arquivos, status, painel ilustrativo) e os
# controles de movimento (clímax do numbers, zoom ambiente).
NOT_TEXT = {"kind", "photo", "logo", "mark", "bg", "symbol", "session", "files", "working", "motif", "ui", "button", "done", "word",
            "focus", "breathe", "color", "region", "shape"}


def texts():
    p = ROOT / "vo.json"
    return {l["id"]: l["text"] for l in json.loads(p.read_text())["lines"]} if p.exists() else {}


def vo_frames(i, txt, faltas):
    p = ROOT / f"public/vo/{i}.wav"
    if p.exists():
        w = wave.open(str(p))
        return math.ceil(w.getnframes() / w.getframerate() * FPS)
    faltas.append(i)
    return math.ceil(len(txt.get(i, "")) / CPS * FPS) or 30


def reads(s):
    """O que o espectador precisa ler na cena, um item por leitura: a lista `read` da cena ou o texto das props."""
    def walk(v, key=None):
        if key in NOT_TEXT:
            return []
        if isinstance(v, str):
            t = v.replace("*", "").strip()
            return [t] if t else []
        if isinstance(v, dict):
            n = v.get("v", v.get("value"))
            if isinstance(n, (int, float)) and not isinstance(n, bool):  # número que conta + rótulo = uma leitura
                return [f"{v.get('prefix', '')}{n}{v.get('suffix', '')} {v.get('label', '')}".strip()]
            return [t for k, x in v.items() for t in walk(x, k)]
        if isinstance(v, list):
            if v and all(isinstance(x, str) for x in v):  # palavras ou linhas de uma frase: uma leitura só
                t = " ".join(x.replace("*", "").strip() for x in v).strip()
                return [t] if t else []
            return [t for x in v for t in walk(x)]
        return []
    r = s.get("read")
    return walk([r] if isinstance(r, str) else r) if r is not None else walk(s.get("props", {}))


def read_need(items):
    """(palavras, segundos): 2,5 palavras/s + 0,5 s."""
    words = sum(len(t.split()) for t in items)
    return words, round(words / WPS + PAD, 1)


def check_line_fracs(name, idx, s):
    """`lineFracs` do statement: um por linha, em [0, 1], em ordem, a partir do `frac` do grupo e antes do `frac` do
    próximo grupo da mesma fala (senão a linha entra por cima do grupo seguinte)."""
    groups = (s.get("props") or {}).get("groups") or []
    for gi, g in enumerate(groups):
        lf = g.get("lineFracs")
        if lf is None:
            continue
        onde = f"!! {name} cena {idx} ({s['type']}) grupo {gi}: lineFracs {lf}"
        if not isinstance(lf, list) or len(lf) != len(g.get("lines", [])) or not all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in lf):
            sys.exit(f"{onde} precisa de um número por linha ({len(g.get('lines', []))})")
        if any(not 0 <= x <= 1 for x in lf):
            sys.exit(f"{onde} fora de [0, 1]")
        if any(b < a for a, b in zip(lf, lf[1:])):
            sys.exit(f"{onde} fora de ordem")
        base = g.get("frac", 0)
        if any(x < base for x in lf):
            sys.exit(f"{onde} começa antes do frac do grupo ({base})")
        prox = next((h for h in groups[gi + 1:] if h.get("beat") == g.get("beat")), None)
        if prox is not None and any(x >= prox.get("frac", 0) for x in lf):
            sys.exit(f"{onde} chega no frac do próximo grupo da mesma fala ({prox.get('frac', 0)}): a linha entraria por cima dele")


def build(name, spec, film, txt):
    out, cut, faltas, curtas = [], 0, [], []
    current = film.get("current", CURRENT)
    if current not in D or current == "cut":
        if current == "cut":
            sys.exit(f"!! {name}: `cut` é transição (corte seco), mas não vale como corrente; use {', '.join(t for t in D if t != 'cut')}")
        sys.exit(f"!! {name}: corrente '{current}' não existe ({', '.join(t for t in D if t != 'cut')})")
    for idx, s in enumerate(spec):
        validar(name, idx, s)
        check_line_fracs(name, idx, s)
        pre, gap, post = s.get("pre", 6), s.get("gap", 8), s.get("post", 8)
        extra = s.get("gaps", [])
        beats, ends, t = [], [], pre
        for j, v in enumerate(s.get("vo", [])):
            n = vo_frames(v, txt, faltas)
            beats.append(t); ends.append(t + n)
            t += n + gap + (extra[j] if j < len(extra) else 0)
        length = (ends[-1] + post) if ends else 0
        length = max(length, s.get("min", 45))
        length = math.ceil(length / BEAT) * BEAT
        tin = s.get("in")
        if idx == 0:
            tin = "cut"
        elif tin is None:
            tin = current
        if tin not in D:
            sys.exit(f"!! {name} cena {idx} ({s['type']}): transição '{tin}' não existe ({', '.join(D)})")
        out.append({"id": f"{s['type']}-{idx}", "type": s["type"], "cut": cut, "in": tin, "d": s.get("d", D[tin]),
                    "len": length, "beats": beats, "ends": ends, "vo": s.get("vo", []),
                    "mark": s.get("mark"), "energy": s.get("energy"), "origin": s.get("origin"),
                    "cues": s.get("cues", []), "props": s.get("props", {})})
        words, need = read_need(reads(s))
        out[-1]["read"] = {"words": words, "need": need, "secs": round(length / FPS, 1)}
        if need > length / FPS:
            curtas.append(f"{out[-1]['id']} ({words} palavras pedem {need:.1f}s, a cena dura {length / FPS:.1f}s)")
        cut += length
    # energia herdada: cena sem "energy" repete a anterior (0 tenso · 1 calmo · 2 andando · 3 cheio)
    e = 1
    for sc in out:
        e = sc["energy"] if sc["energy"] is not None else e
        sc["energy"] = e
    tl = {"name": name, "fps": FPS, "total": cut, "letterbox": film.get("letterbox"), "motionBlur": motion_blur(film), "scenes": out}
    (ROOT / f"src/tl-{name}.json").write_text(json.dumps(tl, ensure_ascii=False, indent=1) + "\n")
    print(f"{name}: {len(out)} cenas, {cut} frames = {cut / FPS:.1f}s ({int(cut / FPS // 60)}:{int(cut / FPS % 60):02d})")
    if faltas:
        print(f"  aviso: {len(faltas)} fala(s) sem WAV, duração estimada pelo texto: {' '.join(sorted(set(faltas)))}")
    if curtas:
        print(f"  aviso: leitura curta (2,5 palavras/s + 0,5 s): {'; '.join(curtas)}."
              " Alongue a cena (min/post), corte texto ou declare em `read` só o que precisa ser lido.")


def main():
    film = json.loads((ROOT / "film.json").read_text())
    txt = texts()
    for name in sys.argv[1:] or [f for f in FORMATS if f in film]:
        build(name, film[name], film, txt)


if __name__ == "__main__":
    main()
