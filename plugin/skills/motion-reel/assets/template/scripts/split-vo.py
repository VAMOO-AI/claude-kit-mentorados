#!/usr/bin/env python3
"""Corta cada bloco de narração (out/vo-blocks/<bloco>.mp3) em 1 WAV por fala (public/vo/<id>.wav).

Escolhe N-1 cortes entre os silêncios do bloco por programação dinâmica: o corte k deve cair
perto da posição esperada pela proporção de caracteres, e silêncio mais longo pesa a favor.
Cada fala sai aparada (sem silêncio nas pontas, 40 ms de folga), 48 kHz mono.
Imprime a tabela fala → duração para conferência.
"""
import json, pathlib, subprocess, sys, wave
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
SR = 48000
TH = 10 ** (-38 / 20)  # limiar de silêncio


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def silences(x, min_len=0.18):
    win = int(0.02 * SR)
    n = len(x) // win
    rms = np.sqrt((x[: n * win].reshape(n, win) ** 2).mean(axis=1))
    quiet = rms < TH
    out, i = [], 0
    while i < n:
        if quiet[i]:
            j = i
            while j < n and quiet[j]:
                j += 1
            a, b = i * win / SR, j * win / SR
            if b - a >= min_len and a > 0.05:
                out.append((a, b))
            i = j
        else:
            i += 1
    return out


def choose(sil, expected, total):
    """DP: escolhe len(expected) silêncios em ordem, minimizando desvio da posição esperada."""
    K, M = len(expected), len(sil)
    if M < K:
        raise SystemExit(f"silêncios insuficientes: {M} < {K}")
    mid = [(a + b) / 2 for a, b in sil]
    ln = [b - a for a, b in sil]
    INF = 1e18
    cost = np.full((K, M), INF)
    back = np.zeros((K, M), dtype=int)
    def c(k, m):
        return ((mid[m] - expected[k]) / (0.08 * total)) ** 2 - 15.0 * ln[m]
    for m in range(M):
        cost[0, m] = c(0, m)
    for k in range(1, K):
        best, arg = INF, -1
        for m in range(M):
            if m > 0 and cost[k - 1, m - 1] < best:
                best, arg = cost[k - 1, m - 1], m - 1
            if arg >= 0:
                cost[k, m] = best + c(k, m)
                back[k, m] = arg
    m = int(np.argmin(cost[K - 1]))
    picks = [m]
    for k in range(K - 1, 0, -1):
        m = back[k, m]
        picks.append(m)
    return [sil[p] for p in reversed(picks)]


def trim(seg):
    idx = np.where(np.abs(seg) > TH)[0]
    if len(idx) == 0:
        return seg
    pad = int(0.04 * SR)
    return seg[max(0, idx[0] - pad): min(len(seg), idx[-1] + pad)]


def save(path, x):
    x = np.clip(x, -1, 1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def main():
    B = json.loads((ROOT / "blocks.json").read_text())
    L = {l["id"]: l["text"] for l in json.loads((ROOT / "vo.json").read_text())["lines"]}
    out = ROOT / "public/vo"; out.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[1:])
    report = {}
    for b, ids in B["blocks"].items():
        if only and b not in only:
            continue
        src = ROOT / f"out/vo-blocks/{b}.mp3"
        if not src.exists():
            print(f"falta {src}"); continue
        x = load(src)
        total = len(x) / SR
        chars = np.array([len(L[i]) + 6 for i in ids], dtype=float)  # +6 ≈ peso fixo por frase
        cum = np.cumsum(chars) / chars.sum()
        expected = [total * c for c in cum[:-1]]
        cuts = choose(silences(x), expected, total)
        edges = [0.0] + [(a + b) / 2 for a, b in cuts] + [total]
        for k, i in enumerate(ids):
            seg = trim(x[int(edges[k] * SR): int(edges[k + 1] * SR)])
            save(out / f"{i}.wav", seg)
            report[i] = round(len(seg) / SR, 2)
            gap = f"  silêncio {cuts[k][1]-cuts[k][0]:.2f}s" if k < len(cuts) else ""
            print(f"{b} {i:5s} {len(seg)/SR:5.2f}s  [{edges[k]:6.2f}–{edges[k+1]:6.2f}]{gap}  {L[i][:60]}")
    (ROOT / "out/vo-durations.json").write_text(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
