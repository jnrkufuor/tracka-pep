"""Norms, skills, role fit and agreement maths."""

import pytest

from pep.contracts import Skill
from pep.evaluation import agreement
from pep.scoring.norms import age_band, standing
from pep.scoring.roles import overall, role_fits
from pep.scoring.skills import Context, score_skills


def test_age_bands():
    assert [age_band(a) for a in (11, 13, 15, 17, 25)] == ["u13", "u15", "u17", "u20", "senior"]


def test_faster_is_better_and_quicker_time_is_better():
    slow, fast = standing("top_speed_ms", 6.5, 16, "male"), standing("top_speed_ms", 8.5, 16, "male")
    assert fast.score > slow.score
    quick, plod = standing("sprint_30m_s", 4.2, 16, "male"), standing("sprint_30m_s", 4.8, 16, "male")
    assert quick.score > plod.score


def test_average_player_is_near_the_middle_and_scores_stay_in_range():
    mid = standing("top_speed_ms", 7.6, 16, "male")
    assert 45 <= mid.percentile <= 55
    assert (
        30
        <= standing("top_speed_ms", 1.0, 16, None).score
        <= standing("top_speed_ms", 20, 16, None).score
        <= 95
    )


def test_female_norms_are_scaled():
    assert standing("top_speed_ms", 7.0, 16, "female").score > standing("top_speed_ms", 7.0, 16, "male").score


def test_drill_result_wins_over_clip_estimate():
    m = {"sprint_30m_s": 4.3, "top_speed_ms": 7.0, "seconds_tracked": 10.0}
    skills = {
        s.skill.name: s.skill
        for s in score_skills(m, Context(age=16, clip_type="drill", method="homography"))
    }
    assert skills["Pace"].source == "drill" and skills["Pace"].confidence == "HIGH"
    assert "30 m in 4.30 s" in skills["Pace"].explanation


def test_confidence_drops_for_highlights_and_estimated_distances():
    m = {"top_speed_ms": 7.5, "seconds_tracked": 10.0}
    pace = score_skills(m, Context(age=16, clip_type="highlight", method="body"))[0].skill
    assert pace.confidence == "LOW"


def test_role_fit_and_overall():
    skills = [
        Skill(name="Pace", score=90, source="measured"),
        Skill(name="Acceleration", score=85, source="measured"),
        Skill(name="Dribbling", score=80, source="measured"),
        Skill(name="Agility", score=70, source="measured"),
    ]
    fits = {f.role: f for f in role_fits(skills)}
    assert fits["wide_winger"].coverage > 0.8
    assert fits["wide_winger"].score > fits["playmaker"].score
    assert overall(skills, list(fits.values()), ["RW"]) == fits["wide_winger"].score


def test_ai_observed_skills_count_half():
    measured = [
        Skill(name="Finishing", score=90, source="measured"),
        Skill(name="Acceleration", score=50, source="measured"),
    ]
    observed = [
        Skill(name="Finishing", score=90, source="ai_observed"),
        Skill(name="Acceleration", score=50, source="measured"),
    ]
    poacher = lambda skills: next(f for f in role_fits(skills) if f.role == "poacher").score  # noqa: E731
    assert poacher(observed) < poacher(measured)


def test_agreement_numbers():
    a = agreement([(70, 72), (60, 55), (80, 82), (50, 48)])
    assert a["n"] == 4 and a["mae"] == pytest.approx(2.75)
    assert a["spearman"] == pytest.approx(1.0)
