# Trilha determinística a partir de src/timeline.json — mesma fonte de tempo do vídeo.
# Batida sintetizada (kick, hat, clap, baixo, pad) + SFX da marca por transição e por cue.
# Rodar: <python com numpy> scripts/track.py  →  public/track.wav
import json, os, wave, numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TL = json.load(open(os.path.join(ROOT, "src/timeline.json")))
CUT = {sc["id"]: sc["cut"] for sc in TL["scenes"]}
MU = TL.get("music", {})
SR = 48000; FPS = TL["fps"]; DUR = TL["total"] / FPS
BEAT = 60 / MU.get("bpm", 120)
N = int(SR * DUR); L = np.zeros(N); R = np.zeros(N)
rng = np.random.default_rng(7)

def fr(f): return f / FPS
def add(sig, at, gain=1.0, pan=0.0):
    i = int(at * SR)
    if i >= N or i < 0: return
    sig = sig[: N - i]
    L[i:i+len(sig)] += sig * gain * (1 - max(0, pan))
    R[i:i+len(sig)] += sig * gain * (1 + min(0, pan))
def env(n, a, d):
    t = np.arange(n) / SR; return np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / d)
def noise(n): return rng.standard_normal(n)
def kick(g=1.0):
    n = int(0.45 * SR); t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t * 28); ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env(n, 0.002, 0.16) * g
def hat():
    n = int(0.06 * SR); return np.diff(noise(n + 1)) * env(n, 0.001, 0.015) * 0.25
def clap():
    n = int(0.25 * SR); x = np.convolve(noise(n), np.ones(6) / 6, "same")
    return (x * 0.6 + np.sin(2 * np.pi * 190 * np.arange(n) / SR) * 0.3) * env(n, 0.002, 0.07)
def bass(freq, dur):
    n = int(dur * SR); t = np.arange(n) / SR
    return (np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(4 * np.pi * freq * t)) * env(n, 0.005, dur * 0.5) * 0.55
def pad(freqs, dur, g=0.12):
    n = int(dur * SR); t = np.arange(n) / SR; s = np.zeros(n)
    for fq in freqs:
        for det in (-0.3, 0.3): s += np.sin(2 * np.pi * (fq + det) * t)
    return s / (len(freqs) * 2) * np.minimum(1, t / (dur * 0.6)) * np.minimum(1, (dur - t) / 0.4) * g

# Am F C G — uma por compasso
ROOTS = [55.0, 43.65, 65.41, 49.0]
CHORDS = [[110, 130.81, 164.81], [87.31, 110, 130.81], [130.81, 164.81, 196], [98, 123.47, 146.83]]
BAR = BEAT * 4

def groove(a, b, dense=False):
    t = a; k = 0
    while t < b - 1e-6:
        add(kick(), t, 0.9); add(hat(), t + BEAT / 2, 0.8, pan=0.3)
        if dense:
            add(hat(), t + BEAT / 4, 0.45, pan=-0.3); add(hat(), t + 3 * BEAT / 4, 0.45, pan=-0.3)
        if k % 2 == 1: add(clap(), t, 0.45)
        bar = int(t // BAR) % 4
        add(bass(ROOTS[bar], BEAT / 2 * 0.95), t); add(bass(ROOTS[bar], BEAT / 2 * 0.95), t + BEAT / 2, 0.7)
        if abs(t % BAR) < 1e-6 or abs(t % BAR - BAR) < 1e-6: add(pad(CHORDS[bar], BAR, 0.09), t)
        t += BEAT; k += 1

def at_scene(ref):  # "voce" ou "voce+14" → segundos
    sid, _, off = ref.partition("+")
    return fr(CUT[sid] + (int(off) if off else 0))

# Estrutura: intro só com pad → groove → (pausa + riser) → drop denso → outro com pad
start = at_scene(MU.get("groove_from", TL["scenes"][1]["id"]))
outro = at_scene(MU.get("outro_from", TL["scenes"][-1]["id"]))
drop = at_scene(MU["drop_at"]) if MU.get("drop_at") else None
add(pad(CHORDS[0], start + 0.1, 0.22), 0.0)
if drop:
    brk = MU.get("break_beats", 2) * BEAT
    groove(start, drop - brk)
    nb = int(brk * SR); tt = np.arange(nb) / SR
    add(np.convolve(noise(nb), np.ones(4) / 4, "same") * (tt / brk) ** 2 * 0.35, drop - brk)
    add(pad(CHORDS[3], brk, 0.12), drop - brk)
    add(kick(1.4), drop); groove(drop, outro, dense=True)
else:
    groove(start, outro)
add(kick(1.2), outro); add(pad(CHORDS[0], DUR - outro, 0.24), outro)

def load(name):
    w = wave.open(os.path.join(ROOT, f"public/sfx/{name}.wav")); d = w.readframes(w.getnframes())
    x = np.frombuffer(d, dtype=np.int16).astype(float) / 32768
    return x.reshape(-1, w.getnchannels()).mean(axis=1)
SFX = {}
def sfx(name):
    if name not in SFX: SFX[name] = load(name)
    return SFX[name]

# SFX automático por tipo de transição (começa com a transição)
BY_TYPE = {"iris": [("soft-whoosh", 0.6), ("dry-pop", 0.5)], "ink": [("soft-whoosh", 0.6), ("soft-chime", 0.7)],
           "whip": [("soft-whoosh", 0.8)], "whipUp": [("soft-whoosh", 0.8)], "push": [("soft-whoosh", 0.6)],
           "bars": [("paper-tap", 0.7), ("soft-whoosh", 0.5)], "glitch": [("soft-click", 0.5)] * 1,
           "panel": [("soft-whoosh", 0.8)], "spin": [("soft-whoosh", 0.8)], "cut": []}
for sc in TL["scenes"][1:]:
    t0 = fr(sc["cut"] - sc.get("d", 0) / 2)
    for name, g in BY_TYPE.get(sc.get("in", "cut"), []): add(sfx(name), t0, g)
    if sc.get("in") == "glitch":
        for i in range(1, 5): add(sfx("soft-click"), t0 + i * 0.05, 0.5)

# Cues da peça: {"at": "cena+frames", "sfx": nome, "gain": 0.6, "repeat": n, "every": frames}
for c in TL.get("cues", []):
    t0 = at_scene(c["at"])
    for i in range(c.get("repeat", 1)):
        add(sfx(c["sfx"]), t0 + fr(i * c.get("every", 0)), c.get("gain", 0.6))

mix = np.stack([L, R], axis=1)
mix *= np.minimum(1, (DUR - np.arange(N) / SR) / 1.2)[:, None]
mix = np.tanh(mix * 1.1); mix = mix / np.max(np.abs(mix)) * 0.89
w = wave.open(os.path.join(ROOT, "public/track.wav"), "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
w.writeframes((mix * 32767).astype(np.int16).tobytes()); w.close()
print(f"track.wav ok — {DUR:.2f}s @ {MU.get('bpm', 120)} BPM")
