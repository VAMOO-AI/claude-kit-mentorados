#!/usr/bin/env python3
"""film.json + duração real de cada fala (public/vo/<id>.wav) → src/tl-<formato>.json.

Cada cena: f = 0 no corte. A 1ª fala entra em `pre` frames, as seguintes depois de `gap`
(+ gaps[k] extra depois da fala k), e a cena termina `post` frames após a última fala; nunca
menos que `min`. A duração sobe para o próximo múltiplo de 15 (120 BPM a 30 fps): todo corte
cai na batida. Cena sem `in` ganha a próxima transição do ciclo, sem repetir a anterior.

Fala sem WAV ainda (storyboard antes da voz): a duração é estimada pelo texto do vo.json
(~14 caracteres/s) e o script avisa. Rode de novo depois do split-vo.py.
Uso: build-timeline.py [master|reel ...]   (sem argumento: todos os formatos do film.json)
"""
import json, math, pathlib, sys, wave

ROOT = pathlib.Path(__file__).resolve().parent.parent
FPS, BEAT = 30, 15
CPS = 14  # estimativa sem WAV
CYCLE = ["whip", "push", "spin", "whipUp", "glitch", "whip", "push", "iris"]
D = {"iris": 14, "ink": 16, "whip": 10, "whipUp": 10, "push": 12, "bars": 18, "glitch": 10, "panel": 18, "spin": 12, "cut": 0}
FORMATS = ("master", "reel")


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


def build(name, spec, film, txt):
    out, cut, last_in, k, faltas = [], 0, None, 0, []
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
            while CYCLE[k % len(CYCLE)] == last_in:
                k += 1
            tin = CYCLE[k % len(CYCLE)]; k += 1
        if tin not in D:
            sys.exit(f"!! {name} cena {idx} ({s['type']}): transição '{tin}' não existe ({', '.join(D)})")
        out.append({"id": f"{s['type']}-{idx}", "type": s["type"], "cut": cut, "in": tin, "d": s.get("d", D[tin]),
                    "len": length, "beats": beats, "ends": ends, "vo": s.get("vo", []),
                    "mark": s.get("mark"), "energy": s.get("energy"), "origin": s.get("origin"),
                    "cues": s.get("cues", []), "props": s.get("props", {})})
        last_in = tin
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


def main():
    film = json.loads((ROOT / "film.json").read_text())
    txt = texts()
    for name in sys.argv[1:] or [f for f in FORMATS if f in film]:
        build(name, film[name], film, txt)


if __name__ == "__main__":
    main()
