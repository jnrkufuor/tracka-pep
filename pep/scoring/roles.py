"""
Role fit: how well a player's skills match what a role needs.

Scouts don't search for "a 71". They search for "a ball-playing centre-back"
or "a direct winger". Each role (pep/data/roles.json) weights skills
differently: a winger's pace matters more than a holding midfielder's.

    role_fit = sum(w_i * s_i * trust_i) / sum(w_i * trust_i)     over skills we have
    coverage = sum(w_i over skills we have) / sum(all w_i)

trust is 1 for measured/drill skills and 0.5 for skills the AI coach only
observed. Coverage tells the scout how much of the role we actually saw:
a role fit of 80 with coverage 0.3 is a hint, not a verdict.

The overall score Tracka shows is the best role fit among the roles for the
player's own positions (if we saw enough of it), else the mean of all skills.
"""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path

from ..contracts import Confidence, RoleFit, Skill

DATA = Path(__file__).resolve().parent.parent / "data" / "roles.json"
TRUST = {"measured": 1.0, "drill": 1.0, "ai_observed": 0.5, None: 1.0}
MIN_COVERAGE = 0.35


@cache
def roles() -> dict[str, dict]:
    return json.loads(DATA.read_text())["roles"]


def role_fits(skills: list[Skill]) -> list[RoleFit]:
    by_name = {s.name: s for s in skills}
    out = []
    for key, role in roles().items():
        weights: dict[str, float] = role["weights"]
        num = den = seen = 0.0
        for name, w in weights.items():
            s = by_name.get(name)
            if s is None:
                continue
            trust = TRUST[s.source]
            num += w * s.score * trust
            den += w * trust
            seen += w
        if den == 0:
            continue
        out.append(
            RoleFit(
                role=key,
                label=role["label"],
                score=round(num / den),
                coverage=round(seen / sum(weights.values()), 2),
            )
        )
    return sorted(out, key=lambda r: (-(r.coverage >= MIN_COVERAGE), -r.score))


def overall(skills: list[Skill], fits: list[RoleFit], positions: list[str]) -> int | None:
    if not skills:
        return None
    wanted = {p.upper() for p in positions}
    mine = [f for f in fits if f.coverage >= MIN_COVERAGE and wanted & set(roles()[f.role]["positions"])]
    if mine:
        return max(f.score for f in mine)
    measured = [s.score for s in skills if s.source != "ai_observed"] or [s.score for s in skills]
    return round(sum(measured) / len(measured))


def overall_confidence(skills: list[Skill], fits: list[RoleFit], positions: list[str]) -> Confidence:
    """The typical (median) confidence of the measured skills, capped at LOW if we saw little of the role."""
    rank = {"LOW": 0, "MEDIUM": 1, "HIGH": 2}
    levels = sorted(rank[s.confidence or "LOW"] for s in skills if s.source != "ai_observed")
    if not levels:
        return "LOW"
    typical = levels[len(levels) // 2]
    wanted = {p.upper() for p in positions}
    mine = [f for f in fits if wanted & set(roles()[f.role]["positions"])]
    if positions and (not mine or max(f.coverage for f in mine) < 0.5):
        typical = 0
    return ("LOW", "MEDIUM", "HIGH")[typical]
