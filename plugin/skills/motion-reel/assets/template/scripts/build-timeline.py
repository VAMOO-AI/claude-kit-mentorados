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
WPS, PAD = 2.5, 0.5  # leitura: palavras por segundo + respiro da cena
# Props que não são leitura: arquivo, tipo, cor e a moldura de UI (sessão, arquivos, status, painel ilustrativo).
NOT_TEXT = {"kind", "photo", "logo", "mark", "bg", "symbol", "session", "files", "working", "motif", "ui", "button", "done", "word"}


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


def build(name, spec, film, txt):
    out, cut, faltas, curtas = [], 0, [], []
    current = film.get("current", CURRENT)
    if current not in D or current == "cut":
        sys.exit(f"!! {name}: corrente '{current}' não existe ({', '.join(t for t in D if t != 'cut')})")
    for idx, s in enumerate(spec):
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
    tl = {"name": name, "fps": FPS, "total": cut, "letterbox": film.get("letterbox"), "scenes": out}
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
