#!/usr/bin/env python3
"""Trilha de cinema + SFX + narração mixados num WAV por formato: public/mix-<formato>.wav

Opcional ao lado do track.py (que serve o Reel guiado pela música). Este serve o Film: lê
src/tl-<formato>.json, a mesma fonte de tempo do vídeo. Determinístico (seed fixa).

Camadas:
- pad de cordas (Am F C G; Am Am F E nas cenas de energia 0) e ostinato + taikos que crescem
  com o `energy` da cena (0 tenso · 1 calmo · 2 andando · 3 cheio);
- `mark` da cena: braam/finale = respiro + riser + braam + impacto; hit/drop = riser + impacto;
  pulse = batimento no lugar da percussão durante a cena;
- SFX da marca: um por transição (BY_TRANSITION), os que cada cena declara em src/sons.mjs (lidos
  pelo Node em scripts/sons.mjs, nos mesmos tempos da animação) e os `cues` livres do film.json.
  Som com `impacto` entra pelo pico: o pico do WAV (medido, RMS de 10 ms) cai no quadro pedido;
  sem ele, o som começa no quadro;
- narração com RMS normalizado, ducking ≈ −8 dB na música e reverb por FFT nos buses.
Fala sem WAV é pulada com aviso (storyboard antes da voz).

Uso: track_cinema.py master|reel [--from S --to S]   (trecho → out/prova-audio-<formato>.wav)
     track_cinema.py master|reel --eventos            (só lista os SFX das cenas e dos cues em JSON: início,
                                                       nome, ganho e amostra do pico; sem gerar o mix)
"""
import json, pathlib, re, subprocess, sys, wave
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
SR, FPS = 48000, 30
BEAT = 0.5           # 120 BPM
BAR = BEAT * 4
rng = np.random.default_rng(11)

name = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "master"
TLP = ROOT / f"src/tl-{name}.json"
TL = json.loads(TLP.read_text(encoding="utf-8"))
SC = TL["scenes"]
DUR = TL["total"] / FPS
N = int((DUR + 0.5) * SR)


def buf():
    return np.zeros((N, 2))


MUS, FX, SFX, VO = buf(), buf(), buf(), np.zeros(N)


def add(b, sig, t, gain=1.0, pan=0.0):
    i = int(round(t * SR))
    if i >= N or len(sig) == 0:
        return
    if i < 0:
        sig = sig[-i:]; i = 0
    sig = sig[: N - i]
    if sig.ndim == 1:
        b[i:i + len(sig), 0] += sig * gain * (1 - max(0.0, pan))
        b[i:i + len(sig), 1] += sig * gain * (1 + min(0.0, pan))
    else:
        b[i:i + len(sig)] += sig * gain


def tt(sec):
    return np.arange(int(sec * SR)) / SR


def env(n, a, d):
    t = np.arange(n) / SR
    return np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / d)


def smooth(x, sec):
    k = max(1, int(sec * SR))
    c = np.cumsum(np.concatenate([[0], x]))
    y = (c[k:] - c[:-k]) / k
    return np.concatenate([np.full(k - 1, y[0]), y])


def saw(freq, sec, harm=10, det=0.0, cutoff=None):
    t = tt(sec); s = np.zeros_like(t)
    for k in range(1, harm + 1):
        a = 1 / k
        if cutoff:
            a /= 1 + (k * freq / cutoff) ** 2
        s += a * np.sin(2 * np.pi * k * freq * (1 + det) * t + k * 0.7)
    return s


# ───────────── fonte de tempo (espelha bt/first do film-scenes.tsx) ─────────────
def T(scene, f):
    return (scene["cut"] + f) / FPS


def bt(s, i, frac=0.0):
    b = s["beats"][i] if i < len(s["beats"]) else 0
    e = s["ends"][i] if i < len(s["ends"]) else b + 30
    return round(b + frac * (e - b))


def first(s):
    return min(bt(s, 0) - 6, -8)


# ───────────── pad de cordas ─────────────
NOTE = {"A": 110.0, "F": 87.31, "C": 130.81, "G": 98.0, "E": 82.41, "D": 73.42}
CHORD = {"Am": ["A", 1, 1.189, 1.498], "F": ["F", 1, 1.26, 1.498], "C": ["C", 1, 1.26, 1.498],
         "G": ["G", 1, 1.26, 1.498], "E": ["E", 1, 1.26, 1.498], "Dm": ["D", 1, 1.189, 1.498]}
PROG = ["Am", "F", "C", "G"]
TENSE = ["Am", "Am", "F", "E"]

energy_at = np.zeros(int(DUR / BAR) + 2, dtype=int)
for s in SC:
    a, b = int(s["cut"] / FPS // BAR), int((s["cut"] + s["len"]) / FPS // BAR)
    energy_at[a:b + 1] = max(0, min(3, int(s["energy"])))


def chord_for_bar(k):
    e = energy_at[min(k, len(energy_at) - 1)]
    prog = TENSE if e == 0 else PROG
    return prog[(k // 2) % 4]


SEG = BAR * 2
for k in range(int(DUR / SEG) + 1):
    t0 = k * SEG
    root, *ratios = CHORD[chord_for_bar(int(t0 / BAR))]
    e = energy_at[min(int(t0 / BAR), len(energy_at) - 1)]
    sec = SEG + 1.0
    s = np.zeros(int(sec * SR))
    for r in ratios:
        for det in (-0.0018, 0.0021):
            s += saw(NOTE[root] * 2 * r, sec, harm=8, det=det, cutoff=[500, 900, 1300, 1700][e])
    s += 0.8 * saw(NOTE[root], sec, harm=4, cutoff=300)  # baixo do acorde
    n = len(s); fade = int(0.5 * SR)
    w = np.ones(n); w[:fade] = np.linspace(0, 1, fade); w[-fade:] = np.linspace(1, 0, fade)
    lfo = 1 + 0.08 * np.sin(2 * np.pi * 0.15 * tt(sec) + k)
    add(MUS, s * w * lfo / 9, t0 - 0.25, gain=[0.55, 0.6, 0.5, 0.55][e])


# ───────────── ostinato + percussão por energia ─────────────
def pluck(freq, dur=0.16):
    return saw(freq, dur, harm=6, cutoff=1400) * env(int(dur * SR), 0.003, 0.07)


def taiko(g=1.0):
    n = int(0.6 * SR); t = np.arange(n) / SR
    f = 42 + 30 * np.exp(-t * 18)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, 0.22)
    nz = smooth(rng.standard_normal(n), 0.0006) * env(n, 0.001, 0.03) * 0.5
    return (body + nz) * g


def tick():
    n = int(0.03 * SR)
    return np.sin(2 * np.pi * 2400 * np.arange(n) / SR) * env(n, 0.0005, 0.006) * 0.5


def hat():
    n = int(0.05 * SR)
    return np.diff(rng.standard_normal(n + 1)) * env(n, 0.0005, 0.012) * 0.25


def clap():
    n = int(0.22 * SR)
    return smooth(rng.standard_normal(n), 0.0002) * env(n, 0.002, 0.06) * 0.6


def heartbeat():
    a = taiko(0.6)
    out = np.zeros(int(0.9 * SR)); out[: len(a)] += a
    i = int(0.24 * SR); out[i:i + len(a)] += a[: len(out) - i] * 0.7
    return out


PULSE = [s for s in SC if s.get("mark") == "pulse"]
in_pulse = lambda t: any(T(s, 0) <= t < T(s, s["len"]) for s in PULSE)
SILENT = [(T(s, 0) - 0.42, T(s, 0)) for s in SC if s.get("mark") in ("braam", "finale")]  # respiro antes do braam

for b in range(int(DUR / BEAT)):
    t = b * BEAT
    k = int(t / BAR)
    e = energy_at[min(k, len(energy_at) - 1)]
    beat_in_bar = b % 4
    root = NOTE[CHORD[chord_for_bar(k)][0]]
    if in_pulse(t):
        if beat_in_bar in (0, 2):
            add(MUS, heartbeat(), t, 0.55)
        continue
    if e == 0:
        add(MUS, tick(), t, 0.22, pan=0.25 if b % 2 else -0.25)
        if beat_in_bar == 0:
            add(MUS, taiko(0.35), t, 0.6)
    elif e == 1:
        if beat_in_bar == 0:
            add(MUS, taiko(0.7), t, 0.8)
        for sub in range(2):
            add(MUS, pluck(root * 2), t + sub * BEAT / 2, 0.12, pan=-0.2)
    elif e == 2:
        if beat_in_bar in (0, 2):
            add(MUS, taiko(1.0), t, 0.85)
        for sub in range(2):
            add(MUS, pluck(root * (2 if sub == 0 else 4)), t + sub * BEAT / 2, 0.16, pan=-0.25 if sub else 0.25)
        add(MUS, hat(), t + BEAT / 2, 0.35, pan=0.4)
    else:
        add(MUS, taiko(1.1), t, 0.9)
        if beat_in_bar in (1, 3):
            add(MUS, clap(), t, 0.35)
        for sub in range(4):
            add(MUS, pluck(root * (2 if sub % 2 == 0 else 4)), t + sub * BEAT / 4, 0.15, pan=-0.3 if sub % 2 else 0.3)
            add(MUS, hat(), t + sub * BEAT / 4, 0.18 if sub % 2 else 0.1, pan=0.45)


# ───────────── braam, risers, impactos ─────────────
def braam(sec=4.0):
    n = int(sec * SR); t = np.arange(n) / SR
    s = np.zeros(n)
    for fq, g in ((55, 1.0), (110, 0.8), (82.41, 0.6), (130.81, 0.45), (164.81, 0.3)):
        for det in (-0.004, 0.0, 0.005):
            s += g * saw(fq, sec, harm=24, det=det, cutoff=900)
    bright = np.interp(t, [0, 0.12, 1.2, sec], [0.2, 1, 0.5, 0.2])
    s = np.tanh(s * 0.35 * bright) * env(n, 0.04, 1.6)
    sub = np.sin(2 * np.pi * np.cumsum(np.interp(t, [0, 2.5], [48, 30])) / SR) * env(n, 0.01, 1.4)
    return s * 0.9 + sub * 0.9


def riser(sec):
    n = int(sec * SR); t = np.arange(n) / SR
    nz = rng.standard_normal(n)
    hi = nz - smooth(nz, 0.0015)                      # ruído agudo (passa-alta grosso)
    sweep = np.sin(2 * np.pi * np.cumsum(np.interp(t, [0, sec], [180, 1400])) / SR) * 0.25
    return (hi * 0.5 + sweep) * (t / sec) ** 2.2


def impact(big=1.0):
    n = int(2.2 * SR); t = np.arange(n) / SR
    f = np.interp(t, [0, 1.4], [85, 28])
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, 0.7)
    nz = smooth(rng.standard_normal(n), 0.0012) * env(n, 0.001, 0.09) * 1.4
    return (sub + nz) * big


def glitch_burst():
    n = int(0.28 * SR)
    x = rng.standard_normal(n)
    x = np.repeat(x[::40], 40)[:n] * np.sign(np.sin(2 * np.pi * 37 * np.arange(n) / SR))
    return x * env(n, 0.001, 0.1) * 0.45


def load_wav(path):
    w = wave.open(str(path)); d = w.readframes(w.getnframes())
    x = np.frombuffer(d, dtype=np.int16).astype(float) / 32768
    if w.getnchannels() > 1:
        x = x.reshape(-1, w.getnchannels()).mean(axis=1)
    if w.getframerate() != SR:
        x = np.interp(np.arange(0, len(x), w.getframerate() / SR), np.arange(len(x)), x)
    return x


_sfx = {}
def sfx(nm):
    if nm not in _sfx:
        p = ROOT / f"public/sfx/{nm}.wav"
        if not p.exists():
            sys.exit(f"!! SFX '{nm}' não existe em public/sfx/")
        _sfx[nm] = load_wav(p)
    return _sfx[nm]


EVENTOS = []  # SFX com nome (mark, cenas e cues), para o --eventos
_pico = {}
def pico(nm):
    """Segundos do início do WAV até o pico (maior RMS em janela de 10 ms): o ponto de impacto."""
    if nm not in _pico:
        x = sfx(nm)
        n = max(1, int(0.01 * SR))
        _pico[nm] = int(np.argmax(np.convolve(x ** 2, np.ones(n) / n, mode="same"))) / SR if len(x) else 0.0
    return _pico[nm]


for s in SC:
    m = s.get("mark")
    t0 = T(s, 0)
    if m in ("braam", "finale"):
        add(FX, riser(2.2), t0 - 2.62, 0.55)
        add(FX, braam(4.5 if m == "braam" else 5.5), t0, 0.85)
        add(FX, impact(1.2), t0, 0.7)
    elif m in ("hit", "drop"):
        add(FX, riser(1.4 if m == "hit" else 2.0), t0 - (1.4 if m == "hit" else 2.0), 0.4 if m == "hit" else 0.55)
        add(FX, impact(1.0 if m == "hit" else 1.3), t0, 0.75)
        add(SFX, sfx("low-hit"), t0 - pico("low-hit"), 0.6)  # o golpe no quadro do corte
        EVENTOS.append({"t": int(round((t0 - pico("low-hit")) * SR)), "sfx": "low-hit", "g": 0.6, "pico": int(round(t0 * SR))})

# ───────────── SFX por transição ─────────────
BY_TRANSITION = {"iris": [("soft-whoosh", 0.55), ("dry-pop", 0.4)], "ink": [("soft-whoosh", 0.55), ("soft-chime", 0.6)],
                 "whip": [("soft-whoosh", 0.7)], "whipUp": [("soft-whoosh", 0.7)], "push": [("soft-whoosh", 0.5)],
                 "bars": [("paper-tap", 0.6), ("soft-whoosh", 0.45)], "glitch": [], "panel": [("soft-whoosh", 0.7)],
                 "spin": [("soft-whoosh", 0.7)], "echo": [("soft-whoosh", 0.6), ("dry-pop", 0.2)], "cut": []}
for s in SC[1:]:
    ts = (s["cut"] - s["d"] / 2) / FPS
    for nm, g in BY_TRANSITION.get(s["in"], []):
        add(SFX, sfx(nm), ts, g)
    if s["in"] == "glitch":
        add(SFX, glitch_burst(), ts, 0.5)


# ───────────── SFX nos pontos das animações ─────────────
# Cada cena declara os sons dela em src/sons.mjs, nos mesmos tempos da animação (tempos.mjs); o
# scripts/sons.mjs devolve a lista da timeline inteira. Cena sem entrada lá fica só com o som da
# transição, ou ganha "cues" no film.json.
def at(s, f, nm, g=0.5, rep=1, every=0, impacto=False):
    d = pico(nm) if impacto else 0.0
    for r in range(rep):
        t = T(s, f + r * every) - d
        EVENTOS.append({"t": int(round(t * SR)), "sfx": nm, "g": g, "pico": int(round((t + pico(nm)) * SR))})
        add(SFX, sfx(nm), t, g)


def sons_das_cenas():
    try:
        r = subprocess.run(["node", str(ROOT / "scripts/sons.mjs"), str(TLP)], capture_output=True,
                           text=True, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        sys.exit("!! node não encontrado: os sons das cenas vêm de src/sons.mjs (instale o Node 18+)")
    if r.returncode:
        sys.exit("!! os sons das cenas (src/sons.mjs) não carregaram:\n" + r.stderr.strip()[-800:])
    return json.loads(r.stdout)


for x in sons_das_cenas():
    s = SC[x["cena"]]
    if "sintese" in x:                              # golpe sintetizado (impact), no bus de efeitos
        add(FX, impact(x["sintese"]), T(s, x["f"]), x["g"])
        continue
    at(s, x["f"], x["sfx"], x["g"], x.get("rep", 1), x.get("every", 0), x.get("impacto", False))

# "cues": [{"at": 12 | "first+6" | "b1" | "b0@0.5-4", "sfx": "dry-pop", "gain": 0.5, "repeat": 1,
#           "every": 0, "impacto": false}]  (impacto: true → o pico do som cai no quadro)
CUE = re.compile(r"^(?:b(\d+)(?:@([\d.]+))?|first)([+-]\d+)?$")


def cue_frame(s, v):
    if isinstance(v, (int, float)):
        return int(v)
    m = CUE.match(str(v).replace(" ", ""))
    if not m:
        sys.exit(f"!! cue '{v}' em {s['id']}: use frame, 'first[+n]' ou 'b<fala>[@fração][+n]'")
    base = first(s) if m.group(1) is None else bt(s, int(m.group(1)), float(m.group(2) or 0))
    return base + int(m.group(3) or 0)


for s in SC:
    for c in s.get("cues", []):
        at(s, cue_frame(s, c["at"]), c["sfx"], c.get("gain", 0.5), c.get("repeat", 1), c.get("every", 0), c.get("impacto", False))

if "--eventos" in sys.argv:
    print(json.dumps(sorted(EVENTOS, key=lambda e: e["t"]), ensure_ascii=False))
    sys.exit(0)

# ───────────── narração ─────────────
TARGET = 10 ** (-19 / 20)
faltas = []
for s in SC:
    for i, vid in enumerate(s["vo"]):
        p = ROOT / f"public/vo/{vid}.wav"
        if not p.exists():
            faltas.append(vid); continue
        x = load_wav(p)
        x = x * (TARGET / (np.sqrt(np.mean(x ** 2)) + 1e-9))
        j = int(T(s, s["beats"][i]) * SR)
        if j < N:
            VO[j:j + len(x)] += x[: N - j]

# ───────────── ducking, reverb, mix ─────────────
act = (smooth(np.abs(VO), 0.02) > 0.01).astype(float)
act = np.minimum(1, smooth(act, 0.15) * 3)          # dilata ~150 ms
duck_env = smooth(act, 0.25)
duck_mus = 1 - 0.6 * duck_env                       # ≈ −8 dB sob a voz
duck_fx = 1 - 0.35 * duck_env
for a, b in SILENT:                                 # respiro antes do braam
    i, j = int(max(0, a) * SR), int(max(0, b) * SR)
    ramp = np.ones(N); ramp[i:j] = 0
    MUS *= smooth(ramp, 0.04)[:, None]


def reverb(x, sec=2.6, wet=0.35):
    n = int(sec * SR)
    ir = rng.standard_normal((n, 2)) * np.exp(-np.arange(n) / SR * 3.2)[:, None]
    ir = np.stack([smooth(ir[:, 0], 0.0004), smooth(ir[:, 1], 0.0004)], axis=1)
    ir /= np.sqrt((ir ** 2).sum(axis=0))
    out = np.zeros_like(x)
    blk = 1 << 19
    nfft = 1 << int(np.ceil(np.log2(blk + n)))
    IR = np.fft.rfft(ir, nfft, axis=0)
    for i in range(0, len(x), blk):
        seg = x[i:i + blk]
        y = np.fft.irfft(np.fft.rfft(seg, nfft, axis=0) * IR, nfft, axis=0)[: len(seg) + n]
        out[i:i + len(y)] += y[: len(out) - i]
    return x + wet * out


MUS = reverb(MUS, 2.2, 0.25)
FX = reverb(FX, 3.0, 0.5)
mix = MUS * duck_mus[:, None] * 0.9 + FX * duck_fx[:, None] * 0.9 + SFX * 0.55 + VO[:, None] * 1.0
mix *= np.clip((DUR + 0.5 - np.arange(N) / SR) / 1.5, 0, 1)[:, None]   # fade final de 1,5 s
mix = np.tanh(mix * 1.05)
mix = mix / (np.max(np.abs(mix)) + 1e-9) * 0.95

lo = float(sys.argv[sys.argv.index("--from") + 1]) if "--from" in sys.argv else 0
hi = float(sys.argv[sys.argv.index("--to") + 1]) if "--to" in sys.argv else DUR + 0.5
out = mix[int(lo * SR): int(hi * SR)]
dst = ROOT / (f"out/prova-audio-{name}.wav" if "--from" in sys.argv else f"public/mix-{name}.wav")
dst.parent.mkdir(parents=True, exist_ok=True)
w = wave.open(str(dst), "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
w.writeframes((out * 32767).astype(np.int16).tobytes()); w.close()
print(f"{dst.name}: {len(out) / SR:.1f}s" + (f" · sem voz ainda: {' '.join(faltas)}" if faltas else ""))
