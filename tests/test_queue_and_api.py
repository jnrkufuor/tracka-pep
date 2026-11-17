"""The job queue, the HTTP API and the worker, end to end (with a fake perceiver)."""

from datetime import timedelta

import httpx
from fastapi.testclient import TestClient

from pep import callbacks, db
from pep.api.app import app
from pep.worker import Worker

AUTH = {"Authorization": "Bearer test-key"}
REQ = {
    "analysisId": "11111111-2222-4333-8444-555555555555",
    "videoUrl": "https://example.com/clip.mp4",
    "positions": ["ST"],
    "callbackUrl": "https://tracka.test/api/coach/results",
}


def test_enqueue_is_idempotent():
    a = db.enqueue(REQ, "tracka")
    b = db.enqueue(REQ, "tracka")
    assert a["id"] == b["id"]


def test_claim_gives_each_job_once_and_reclaims_expired_leases():
    db.enqueue(REQ, "tracka")
    job = db.claim("w1", lease_seconds=60)
    assert job and job["status"] == "RUNNING" and job["attempts"] == 1
    assert db.claim("w2", lease_seconds=60) is None  # already taken

    # Simulate worker w1 dying: its lease runs out, w2 takes over.
    with db.engine().begin() as c:
        c.execute(db.jobs.update().values(lease_until=db.now() - timedelta(seconds=1)))
    again = db.claim("w2", lease_seconds=60)
    assert again and again["worker"] == "w2" and again["attempts"] == 2
    assert not db.heartbeat(job["id"], "w1", 60)  # w1 finds out it lost the job


def test_retry_backs_off_then_gives_up():
    db.enqueue(REQ, "tracka")
    job = db.claim("w", 60)
    assert db.retry_later(job["id"], "w", "boom", attempts=1)
    queued = db.get_job(job["id"])
    assert queued["status"] == "QUEUED" and queued["run_after"] > db.now() + timedelta(seconds=25)
    assert not db.retry_later(job["id"], "w", "boom", attempts=3)


def test_api_auth_and_queueing():
    with TestClient(app) as client:
        assert client.post("/analyses", json=REQ).status_code == 401
        r = client.post("/analyses", json=REQ, headers=AUTH)
        assert r.status_code == 202 and r.json()["status"] == "QUEUED"
        assert client.get(f"/analyses/{REQ['analysisId']}", headers=AUTH).json()["status"] == "QUEUED"
        assert client.get("/healthz").json()["ok"]
        assert client.get("/readyz").status_code == 200
        assert "pep_jobs" in client.get("/metrics").text


def test_lab_upload_worker_and_signed_callback(blank_video, fake_perceiver):
    with TestClient(app) as client:
        with blank_video.open("rb") as f:
            r = client.post(
                "/lab/clips",
                files={"video": ("clip.mp4", f, "video/mp4")},
                data={
                    "request": '{"positions": ["RW"], "ageYears": 16, "playerHeightM": 1.75, "playerLabel": "Kofi"}'
                },
            )
        assert r.status_code == 202, r.text
        job_id = r.json()["id"]

        Worker(perceiver=fake_perceiver).run(drain=True)

        view = client.get(f"/lab/analyses/{job_id}").json()
        assert view["status"] == "READY", view
        result = view["result"]
        assert result["overallScore"] is not None
        # 300 px/s with a 200 px tall, 1.75 m player is ~2.5 m/s (the body-ruler estimate)
        assert 1.8 < result["metrics"]["top_speed_ms"] < 3.2
        assert view["player"] == "Kofi"

        assert (
            client.post(f"/lab/analyses/{job_id}/ratings", json={"rater": "Ama", "overall": 60}).status_code
            == 201
        )
        assert client.get("/lab/agreement").json()["n"] == 1
        assert client.get("/lab/health").json()["counts"]["READY"] == 1


def test_callback_is_signed_and_retried():
    db.enqueue(REQ, "tracka")
    job = db.claim("w", 60)
    db.finish(job["id"], "w", {"analysisId": REQ["analysisId"], "status": "READY"}, {}, None, callback=True)
    seen = {}

    def tracka(request: httpx.Request) -> httpx.Response:
        seen["ok"] = callbacks.verify(request.content, request.headers["X-Tracka-Signature"], "test-secret")
        return httpx.Response(503 if "first" not in seen else 200)

    client = httpx.Client(transport=httpx.MockTransport(tracka))
    seen_first = callbacks.deliver(db.callbacks_due()[0], client)
    assert seen["ok"] and not seen_first
    assert db.get_job(job["id"])["callback_status"] == "PENDING"
    seen["first"] = True
    with db.engine().begin() as c:  # pretend the backoff delay has passed
        c.execute(db.jobs.update().values(callback_next_at=db.now()))
    assert callbacks.deliver(db.callbacks_due()[0], client)
    assert db.get_job(job["id"])["callback_status"] == "SENT"
