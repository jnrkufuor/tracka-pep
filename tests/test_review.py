"""Pep's reviews: headline, moments, tips tied to a moment, a skill area and a drill."""

from __future__ import annotations

from fastapi.testclient import TestClient
from test_player_api import complete_profile, headers, signup, upload

import pep.pipeline
from pep.api.app import app
from pep.coach.llm import AreaTip, CoachNotes, NoteMoment
from pep.coach.merge import label_moment
from pep.players import review, training
from pep.worker import Worker

RESULT = {
    "status": "READY",
    "summary": "You checked your shoulder more. Look before passing back.",
    "headline": "You looked around more",
    "coachSource": "gemini",
    "moments": [
        {
            "atSeconds": 4.0,
            "kind": "GOOD",
            "title": "Turned and played forward",
            "area": "scanning",
            "text": "You checked twice.",
        },
        {
            "atSeconds": 9.5,
            "kind": "WORK_ON",
            "title": "Passed back under pressure",
            "area": "scanning",
            "text": "You didn't look.",
        },
        {
            "atSeconds": 12.0,
            "kind": "WORK_ON",
            "area": "close_control",
            "text": "Heavy touch: the ball ran away.",
        },
    ],
    "tips": [
        {"area": "scanning", "title": "Look before you get the ball", "text": "A quick look shows the space."}
    ],
}


def test_review_tells_a_story_and_ties_tips_to_moments_and_drills():
    r = review.review(RESULT, kit=["ball", "wall"])
    assert r["headline"]["title"] == "You looked around more"
    assert [m["title"] for m in r["wentWell"]] == ["Turned and played forward"]
    assert r["workOn"][1]["title"] == "Keeping the ball close"  # no title: the area's name
    scan, close = r["tips"]
    assert scan["atSeconds"] == 9.5  # linked to the matching WORK_ON moment
    assert scan["drill"]["id"] == "scanning_rondo"  # made for scanning; friends aren't kit
    assert close["title"] == "Keep the ball closer"  # a rule tip: the AI didn't cover this area
    assert scan["group"] == "Reading the game" and close["drill"]["id"] == "cone_dribble"
    assert r["note"] == "You looked around more. 2 tips inside."
    assert "score" not in str(r["tips"]).lower()  # tips are words and drills, never numbers


def test_drills_fit_the_kit():
    assert review.pick_drill("passing_forward", ["ball"]) is None  # wall passes need a wall
    assert review.pick_drill("passing_forward", ["ball", "wall"])["id"] == "wall_passes"


def test_not_ready_has_no_review_and_rules_notes_still_read_well():
    assert review.review({"status": "FAILED"}) is None
    r = review.review({"status": "READY", "moments": [{"atSeconds": 1, "kind": "GOOD", "text": "Nice."}]})
    assert r["headline"]["title"] == "Good moment" and r["note"] == "1 thing went well."
    assert label_moment(3.0, "GOOD", "Top speed here: 25.1 km/h.").area == "top_speed"


def test_latest_review_leads_the_training_plan():
    videos = [{"id": "a", "clip_type": "match", "result": RESULT}]
    prefer = review.recent_work_on(videos)
    assert prefer == ["scanning", "close_control"]
    areas = {
        "groups": [
            {
                "name": "x",
                "items": [
                    {
                        "id": "top_speed",
                        "name": "Top speed",
                        "state": "measured",
                        "key": True,
                        "band": "Below average",
                    },
                    {
                        "id": "scanning",
                        "name": "Looking around",
                        "state": "coming_later",
                        "key": False,
                        "band": None,
                    },
                ],
            }
        ]
    }
    assert training.focus_areas(areas, prefer=prefer)[0]["id"] == "scanning"


def test_api_returns_reviews_and_tips_only_for_the_owner(blank_video, fake_perceiver, monkeypatch):
    notes = CoachNotes(
        headline="Quick off the mark",
        summary="Good burst. Keep the ball closer.",
        moments=[
            NoteMoment(
                at_seconds=0.5, kind="WORK_ON", title="Ball ran away", area="close_control", text="Too far."
            )
        ],
        area_tips=[
            AreaTip(area="close_control", title="Keep the ball closer", text="Small touches.", at_seconds=0.5)
        ],
    )
    monkeypatch.setattr(pep.pipeline, "watch", lambda video, ctx: notes)
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, consent=True)
        vid = upload(client, h, blank_video, "Sunday match")
        Worker(perceiver=fake_perceiver).run(drain=True)
        v = client.get(f"/v1/videos/{vid}", headers=headers(h)).json()
        assert v["review"]["headline"]["title"] == "Quick off the mark"
        assert v["review"]["tips"][0]["drill"]["id"] == "cone_dribble"  # cones can be shoes
        assert client.get("/v1/videos", headers=headers(h)).json()[0]["reviewNote"].endswith("1 tip inside.")
        tips = client.get("/v1/tips", headers=headers(h)).json()
        assert tips[0]["videoId"] == vid and tips[0]["videoTitle"] == "Sunday match"

        other = signup(client, "someone-else@example.com")
        assert client.get("/v1/tips", headers=headers(other)).json() == []
