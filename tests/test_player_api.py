"""The player app's API: accounts, profile, uploads, analysis, coach summary, privacy."""

from fastapi.testclient import TestClient

from pep.api.app import app
from pep.players import store
from pep.worker import Worker


def signup(client: TestClient, email: str = "kofi@example.com") -> dict:
    r = client.post("/v1/auth/signup", json={"email": email, "password": "goal-goal-goal"})
    assert r.status_code == 201, r.text
    return {"Authorization": f"Bearer {r.json()['accessToken']}"} | {"_refresh": r.json()["refreshToken"]}


def headers(h: dict) -> dict:
    return {k: v for k, v in h.items() if not k.startswith("_")}


def complete_profile(client: TestClient, h: dict, birth: str = "2008-03-01", consent: bool = False) -> dict:
    body = {
        "displayName": "Kofi Mensah",
        "birthDate": birth,
        "sex": "male",
        "heightM": 1.75,
        "positions": ["RW", "ST"],
        "region": "Ashanti",
        "foot": "right",
    }
    if consent:
        body |= {"guardianEmail": "parent@example.com", "guardianConsent": True}
    r = client.patch("/v1/me", json=body, headers=headers(h))
    assert r.status_code == 200, r.text
    return r.json()


def upload(client: TestClient, h: dict, video, title: str = "Sunday league") -> str:
    with video.open("rb") as f:
        r = client.post(
            "/v1/videos",
            files={"video": ("clip.mp4", f, "video/mp4")},
            data={"meta": f'{{"title": "{title}", "clipType": "match"}}'},
            headers=headers(h),
        )
    assert r.status_code == 202, r.text
    return r.json()["id"]


def test_signup_login_and_wrong_password():
    with TestClient(app) as client:
        signup(client)
        assert (
            client.post(
                "/v1/auth/signup", json={"email": "KOFI@example.com", "password": "another-pass"}
            ).status_code
            == 409
        )
        assert (
            client.post(
                "/v1/auth/login", json={"email": "kofi@example.com", "password": "wrong-password"}
            ).status_code
            == 401
        )
        ok = client.post("/v1/auth/login", json={"email": "kofi@example.com", "password": "goal-goal-goal"})
        assert ok.status_code == 200 and ok.json()["accessToken"]
        assert client.get("/v1/me").status_code == 401


def test_passwords_are_hashed_not_stored():
    with TestClient(app) as client:
        signup(client)
    user = store.user_by_email("kofi@example.com")
    assert (
        user and "goal-goal-goal" not in user["password_hash"] and user["password_hash"].startswith("scrypt$")
    )


def test_refresh_rotates_and_detects_reuse():
    with TestClient(app) as client:
        h = signup(client)
        first = h["_refresh"]
        r = client.post("/v1/auth/refresh", json={"refreshToken": first})
        assert r.status_code == 200
        second = r.json()["refreshToken"]
        # Using the old token again looks like theft: everything is revoked.
        assert client.post("/v1/auth/refresh", json={"refreshToken": first}).status_code == 401
        assert client.post("/v1/auth/refresh", json={"refreshToken": second}).status_code == 401


def test_profile_and_settings():
    with TestClient(app) as client:
        h = signup(client)
        me = client.get("/v1/me", headers=headers(h)).json()
        assert me["profileComplete"] is False and me["settings"]["units"] == "kmh"
        me = complete_profile(client, h, birth="2000-01-01")
        assert me["profileComplete"] and me["profile"]["age"] >= 18 and not me["needsGuardian"]
        me = client.patch("/v1/me", json={"settings": {"units": "mph"}}, headers=headers(h)).json()
        assert me["settings"]["units"] == "mph" and me["settings"]["coachNotes"] is True
        assert client.patch("/v1/me", json={"positions": ["XX"]}, headers=headers(h)).status_code == 422
        assert client.patch("/v1/me", json={"region": "Narnia"}, headers=headers(h)).status_code == 422


def test_uploads_need_profile_and_guardian_for_minors(blank_video):
    with TestClient(app) as client:
        h = signup(client)
        with blank_video.open("rb") as f:
            r = client.post("/v1/videos", files={"video": ("c.mp4", f, "video/mp4")}, headers=headers(h))
        assert r.status_code == 409  # profile not finished
        me = complete_profile(client, h, birth="2011-05-05")  # 15 years old
        assert me["needsGuardian"]
        with blank_video.open("rb") as f:
            r = client.post("/v1/videos", files={"video": ("c.mp4", f, "video/mp4")}, headers=headers(h))
        assert r.status_code == 403
        complete_profile(client, h, birth="2011-05-05", consent=True)
        upload(client, h, blank_video)


def test_upload_analyse_library_and_coach_summary(blank_video, fake_perceiver):
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, consent=True)
        ids = [upload(client, h, blank_video, f"Clip {i}") for i in range(3)]
        lib = client.get("/v1/videos", headers=headers(h)).json()
        assert [v["status"] for v in lib] == ["QUEUED"] * 3

        coach = client.get("/v1/coach", headers=headers(h)).json()
        assert coach["processing"] == 3 and coach["overallScore"] is None

        Worker(perceiver=fake_perceiver).run(drain=True)

        v = client.get(f"/v1/videos/{ids[0]}", headers=headers(h)).json()
        assert v["status"] == "READY" and v["analysis"]["overallScore"] is not None
        assert v["analysis"]["metrics"]["top_speed_ms"] > 1
        coach = client.get("/v1/coach", headers=headers(h)).json()
        assert coach["clipsAnalysed"] == 3 and coach["overallScore"] is not None
        assert coach["skills"] and coach["focus"] and coach["trend"]
        assert client.get("/v1/opportunities", headers=headers(h)).json() == {"comingSoon": True, "items": []}


def test_players_only_see_their_own_videos(blank_video):
    with TestClient(app) as client:
        a, b = signup(client, "a@example.com"), signup(client, "b@example.com")
        complete_profile(client, a, consent=True)
        vid = upload(client, a, blank_video)
        assert client.get(f"/v1/videos/{vid}", headers=headers(b)).status_code == 404
        assert client.delete(f"/v1/videos/{vid}", headers=headers(b)).status_code == 404
        assert client.get("/v1/videos", headers=headers(b)).json() == []


def test_rename_delete_video_and_account(blank_video):
    with TestClient(app) as client:
        h = signup(client)
        complete_profile(client, h, consent=True)
        vid = upload(client, h, blank_video)
        assert (
            client.patch(f"/v1/videos/{vid}", json={"title": "Best goal"}, headers=headers(h)).json()["title"]
            == "Best goal"
        )
        assert client.delete(f"/v1/videos/{vid}", headers=headers(h)).status_code == 204
        assert client.get("/v1/videos", headers=headers(h)).json() == []
        upload(client, h, blank_video)
        assert client.delete("/v1/me", headers=headers(h)).status_code == 204
        assert client.get("/v1/me", headers=headers(h)).status_code == 401
        assert store.user_by_email("kofi@example.com") is None
