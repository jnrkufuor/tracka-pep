"""
Measuring whether Pep is any good: agreement with human scouts.

You can't improve what you don't measure. Every model change should be
judged against the same yardstick, and for Pep that yardstick is "does it
agree with experienced scouts who watched the same clip?".

  MAE       mean absolute error: on average, how many points apart are Pep
            and the scout. Easy to explain ("within 6 points").
  Spearman  rank correlation (-1..1): if scouts rank player A above player B,
            does Pep too? For scouting, ranking is what matters most.
  within10  share of clips where Pep is within 10 points of the scout.

Also worth knowing: scouts disagree with *each other*. Have two scouts rate
the same clips and compute these numbers between them: that's the best
Pep can realistically hope for ("human-level agreement").
"""

from __future__ import annotations

import numpy as np


def ranks(x: np.ndarray) -> np.ndarray:
    """Ranks with ties averaged (1, 2.5, 2.5, 4...)."""
    order = x.argsort()
    r = np.empty(len(x))
    r[order] = np.arange(1, len(x) + 1)
    for v in np.unique(x):
        same = x == v
        r[same] = r[same].mean()
    return r


def spearman(a: np.ndarray, b: np.ndarray) -> float | None:
    if len(a) < 3 or np.std(a) == 0 or np.std(b) == 0:
        return None
    return float(np.corrcoef(ranks(a), ranks(b))[0, 1])


def agreement(pairs: list[tuple[float, float]]) -> dict:
    """pairs: (pep score, scout score)."""
    if not pairs:
        return {"n": 0, "mae": None, "spearman": None, "within10": None}
    a = np.array([p[0] for p in pairs], dtype=float)
    b = np.array([p[1] for p in pairs], dtype=float)
    return {
        "n": len(pairs),
        "mae": round(float(np.mean(np.abs(a - b))), 2),
        "bias": round(float(np.mean(a - b)), 2),  # positive: Pep scores higher than scouts
        "spearman": None if (s := spearman(a, b)) is None else round(s, 3),
        "within10": round(float(np.mean(np.abs(a - b) <= 10)), 3),
    }
