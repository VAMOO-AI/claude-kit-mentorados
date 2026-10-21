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
        validar(name, idx, s)
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
    tl = {"name": name, "fps": FPS, "total": cut, "letterbox": film.get("letterbox"), "motionBlur": motion_blur(film), "scenes": out}
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
