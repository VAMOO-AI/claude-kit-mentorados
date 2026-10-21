"""Tempos das cenas avulsas para o som (track_cinema.py), sem numpy: espelha o src/tempos.mjs.

Mudou uma regra lá, mude aqui; o tests/test-motion-reel-galeria.sh compara os dois caso a caso.
"""

GAP_MORPH = 16
GAP_RANKING = 6


def bt(s, i, frac=0.0):
    """Frame local da fala i (frac 0 = início, 1 = fim); sem fala i, começo + 30 (bt do film-base.tsx)."""
    b = s["beats"][i] if i < len(s["beats"]) else 0
    e = s["ends"][i] if i < len(s["ends"]) else b + 30
    return round(b + frac * (e - b))


def first(s):
    return min(bt(s, 0) - 6, -8)


def falas(s):
    return [bt(s, k) for k in range(len(s["beats"]))]


def tempos_morph(n_estados, falas_, t0, step, loop):
    n = n_estados + (1 if loop and n_estados > 1 else 0)
    at = []
    for k in range(n):
        if k == 0:
            at.append(t0)
            continue
        alvo = falas_[k] - 4 if k < len(falas_) else at[k - 1] + step
        at.append(max(alvo, at[k - 1] + GAP_MORPH))
    return at


def tempos_ranking(n, falas_, t0, step):
    at = []
    for e in range(n):
        if e == 0:
            at.append(t0 + 6)
            continue
        alvo = falas_[e] - 4 if e < len(falas_) else at[e - 1] + step
        at.append(max(alvo, at[e - 1] + GAP_RANKING))
    return at


def prop(p, chave, padrao):
    """O valor da prop, com null do film.json valendo como ausente (o ?? das cenas)."""
    v = p.get(chave)
    return padrao if v is None else v


def troca_swap(s, p):
    """Frame da troca do swap: `at`, ou a 2ª fala − 6, ou 45 sem voz."""
    return prop(p, "at", bt(s, 1) - 6 if len(s["beats"]) > 1 else 45)
