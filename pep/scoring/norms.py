"""
Comparing a measurement with players of the same age: z-scores and percentiles.

"8.1 m/s top speed" means nothing to a 14-year-old or a scout until you say
compared with whom. We compare with players in the same age band:

    z = (value - mean) / sd                 how many standard deviations from typical
    percentile = Phi(z) * 100               share of players you'd beat, if values are
                                            roughly normally distributed (Phi = normal CDF)

For "lower is better" measures (sprint times) we flip the sign of z.
For counts with a long tail (keepy-ups) we compare logarithms instead.

Then a percentile becomes a 30-95 score: from a phone clip we can't honestly
say anyone is a 5 or a 100, so we don't (the same rule Tracka's built-in
coach uses).
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from functools import cache
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data" / "norms.json"
LOWEST, HIGHEST = 30, 95


@cache
def norms() -> dict:
    return json.loads(DATA.read_text())


def age_band(age: int | None) -> str:
    if age is None:
        return "u17"  # Tracka's core users; a missing age lowers confidence elsewhere
    if age < 13:
        return "u13"
    if age < 15:
        return "u15"
    if age < 17:
        return "u17"
    if age < 20:
        return "u20"
    return "senior"


def normal_cdf(z: float) -> float:
    """Phi(z) via the error function: the share of a normal distribution below z."""
    return 0.5 * (1.0 + math.erf(z / math.sqrt(2.0)))


@dataclass(frozen=True)
class Standing:
    metric: str
    value: float
    z: float
    percentile: float  # 0-100
    score: int  # 30-95
    band: str


def percentile_to_score(p: float) -> int:
    return int(round(LOWEST + (HIGHEST - LOWEST) * p / 100.0))


def standing(metric: str, value: float | None, age: int | None, sex: str | None) -> Standing | None:
    spec = norms()["metrics"].get(metric)
    if spec is None or value is None or not math.isfinite(value):
        return None
    band = age_band(age)
    mean, sd = spec["bands"][band]
    if sex == "female":
        mean *= spec.get("female_scale", 1.0)
    if spec.get("log"):
        z = (math.log1p(max(value, 0.0)) - math.log1p(mean)) / sd
    else:
        z = (value - mean) / sd
    z *= spec["direction"]
    z = max(-3.5, min(3.5, z))  # beyond 3.5 sd is more likely a measuring error than a prodigy
    p = normal_cdf(z) * 100
    return Standing(metric, value, z, p, percentile_to_score(p), band)
