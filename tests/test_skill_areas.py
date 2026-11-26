"""Skill areas (Me tab): bands, plain-words averages, confidence, trends and position-specific items."""

from __future__ import annotations

from pep.players.skill_areas import band_for, confidence_for, say, skill_areas, trend_for


def clip(metrics: dict, status: str = "READY") -> dict:
    return {"status": status, "result": {"metrics": metrics}}


def find(out: dict, item_id: str) -> dict:
    return next(i for g in out["groups"] for i in g["items"] if i["id"] == item_id)


def test_band_cut_offs():
    assert band_for(10) == "below"
    assert band_for(45) == "average"
    assert band_for(70) == "above"
    assert band_for(85) == "strong"
    assert band_for(97) == "standout"


def test_confidence_timed_tests_earn_trust_faster():
    assert confidence_for("sprint_30m_s", 1) == "medium"
    assert confidence_for("sprint_30m_s", 2) == "high"
    assert confidence_for("head_checks_per_min", 1) == "low"
    assert confidence_for("head_checks_per_min", 3) == "medium"
    assert confidence_for("head_checks_per_min", 4) == "high"


def test_trend_compares_newer_half_with_older_half():
    assert trend_for([80]) == "new"
    assert trend_for([80, 82, 60, 58]) == "growing"
    assert trend_for([50, 52, 70, 72]) == "dipping"
    assert trend_for([60, 61, 59, 60]) == "steady"


def test_average_is_said_in_plain_words():
    assert say("10 m in {v:.2f} s", 1.923) == "10 m in 1.92 s"
    assert say("{kmh} km/h", 7.5) == "27.0 km/h"
    assert say("moving {pct}% of the time", 0.47) == "moving 47% of the time"


def test_no_clips_means_nothing_is_rated():
    out = skill_areas([], ["CM"], 16, "male")
    assert out["ageGroup"] == "U17" and out["measured"] == 0
    items = [i for g in out["groups"] for i in g["items"]]
    assert all(i["band"] is None for i in items)
    assert find(out, "scanning")["state"] == "not_seen" and find(out, "scanning")["howToMeasure"]
    assert find(out, "half_turn")["state"] == "coming_later"
    assert find(out, "coachable")["state"] == "cant_see"


def test_measured_item_gets_band_average_confidence_trend():
    # newest first: a fast 10 m split twice (timed test), better than before
    videos = [
        clip({"split_10m_s": 1.70}),
        clip({"split_10m_s": 1.72}),
        clip({"split_10m_s": 1.90}),
        clip({"split_10m_s": 1.92}),
    ]
    item = find(skill_areas(videos, ["CM"], 16, "male"), "short_speed")
    assert item["state"] == "measured" and item["band"] in ("above", "strong", "standout")
    assert item["average"].startswith("10 m in 1.7")
    assert item["confidence"] == "high" and item["trend"] == "growing" and item["measurements"] == 4
    assert item["howToMeasure"] is None


def test_unfinished_clips_are_ignored():
    item = find(skill_areas([clip({"split_10m_s": 1.7}, status="RUNNING")], ["CM"], 16, None), "short_speed")
    assert item["state"] == "not_seen"


def test_position_decides_key_skills_and_goalkeeping_group():
    cm = skill_areas([], ["CM"], 16, None)
    gk = skill_areas([], ["GK"], 16, None)
    assert find(cm, "scanning")["key"] and not find(cm, "ready")["key"]
    assert "Goalkeeping" not in [g["name"] for g in cm["groups"]]
    assert "Goalkeeping" in [g["name"] for g in gk["groups"]] and find(gk, "ready")["key"]
    # key skills come first in their group
    skills = next(g for g in cm["groups"] if g["name"] == "Reading the game")["items"]
    assert skills[0]["key"]
