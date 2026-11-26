"""
The HTTP API (FastAPI) and the Pep Lab web UI.

Three audiences, three groups of routes:

  Tracka (machine to machine, Bearer token)
    POST /analyses              queue a clip (the contract in contracts.py)
    GET  /analyses/{analysisId} check on it

  Pep Lab (people: you, coaches, scouts; HTTP Basic password)
    /lab/...                    upload clips, see results, rate clips, health

  Operations (load balancers, monitoring)
    GET /healthz                "the process is alive"   (liveness)
    GET /readyz                 "and can reach the DB"   (readiness)
    GET /metrics                Prometheus metrics

FastAPI builds on Python type hints: declare a parameter as a pydantic
model and FastAPI parses and validates the JSON body for you, returns a
clear 422 error if it's wrong, and documents it at /docs automatically.
"""

from __future__ import annotations

import json
import secrets
import tempfile
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from statistics import median

from fastapi import (
    BackgroundTasks,
    Depends,
    FastAPI,
    File,
    Form,
    Header,
    HTTPException,
    Request,
    Response,
    UploadFile,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.staticfiles import StaticFiles
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from pydantic import BaseModel, Field

from .. import MODEL_VERSION, db
from ..config import ROOT, settings
from ..contracts import POSITIONS, AnalysisRequest
from ..drills.runner import drill_catalogue
from ..errors import setup_error_tracking
from ..log import get_logger, setup_logging
from ..scoring.roles import roles
from ..storage import LocalStorage, storage, verify_local

log = get_logger(__name__)
WEB = ROOT / "web"
MAX_UPLOAD_BYTES = 300 * 1024 * 1024

# ---------------------------------------------------------------- metrics
# The "RED" method: Rate, Errors, Duration for every endpoint, plus queue gauges.
REQUESTS = Counter("pep_http_requests_total", "HTTP requests", ["route", "method", "status"])
LATENCY = Histogram("pep_http_request_seconds", "HTTP request duration", ["route"])
QUEUE = Gauge("pep_jobs", "Jobs by status", ["status"])
OLDEST = Gauge("pep_oldest_queued_seconds", "Age of the oldest queued job")


DEV_DEFAULTS = {"jwt_secret": "dev-jwt-secret-change-me-please-32b", "api_key": "dev-key"}


def _refuse_unsafe_prod_settings() -> None:
    """
    Fail fast (handbook chapter 10): in production, refuse to start with a
    development secret. Anyone could sign a login token with the default
    JWT secret and act as any player. A crash at deploy time is caught by the
    health check and the old version keeps running; a silent start is not.
    """
    s = settings()
    if s.env != "prod":
        return
    bad = [k for k, v in DEV_DEFAULTS.items() if getattr(s, k) == v]
    if not s.lab_password:
        bad.append("lab_password")
    if bad:
        raise RuntimeError(f"Refusing to start in prod with development settings: {', '.join(bad)}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Runs once at start-up (before `yield`) and once at shutdown (after)."""
    setup_logging()
    _refuse_unsafe_prod_settings()
    setup_error_tracking()  # off unless PEP_SENTRY_DSN is set: pep/errors.py
    db.engine()  # create tables, fail fast if the DB is unreachable
    if settings().inline_worker:
        from ..worker import start_inline_worker

        app.state.worker = start_inline_worker()
    log.info("api.start", version=MODEL_VERSION, env=settings().env)
    yield
    if getattr(app.state, "worker", None):
        app.state.worker.stop()


app = FastAPI(title="Pep: Tracka AI coach", version=MODEL_VERSION, lifespan=lifespan)

# CORS: browsers block a web page from calling an API on another origin unless the
# API says it's allowed. The Flutter web app is served from its own domain
# (Cloudflare Pages), so we list it here. Phones' native apps aren't browsers: CORS
# doesn't apply to them.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings().cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["x-request-id"],
)

# The player app's API (accounts, profile, videos, coach): pep/players/routes.py
# (imported after `app` exists, because routes import kick_workers)
from ..players.routes import router as player_router  # noqa: E402

app.include_router(player_router)

# Web pages for people without the app (a guardian opening /g/4F7K): pep/players/pages.py
from ..players.pages import router as pages_router  # noqa: E402

app.include_router(pages_router)

# Staff moderation of Pitchside (Lab › Safety): pep/players/moderation.py
from ..players.moderation import router as moderation_router  # noqa: E402

app.include_router(moderation_router)

# Staff view of app crash reports (Lab › App errors): pep/players/app_errors.py
from ..players.app_errors import lab_router as app_errors_lab  # noqa: E402

app.include_router(app_errors_lab)


@app.middleware("http")
async def observe(request: Request, call_next):
    """Times every request, counts it, and tags its logs with a request id."""
    import structlog

    request_id = request.headers.get("x-request-id") or uuid.uuid4().hex[:12]
    structlog.contextvars.bind_contextvars(request_id=request_id)
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        response.headers["x-request-id"] = request_id
        return response
    finally:
        route = request.scope.get("route")
        path = getattr(
            route, "path", "unmatched"
        )  # "/analyses/{analysis_id}", not every id: keeps metrics small
        LATENCY.labels(path).observe(time.perf_counter() - start)
        REQUESTS.labels(path, request.method, str(status)).inc()
        structlog.contextvars.clear_contextvars()


# ---------------------------------------------------------------- auth


def tracka_auth(authorization: str | None = Header(None)) -> None:
    expected = f"Bearer {settings().api_key}"
    if not authorization or not secrets.compare_digest(authorization, expected):
        raise HTTPException(401, "Missing or wrong API key")


basic = HTTPBasic(auto_error=False)


def lab_auth(creds: HTTPBasicCredentials | None = Depends(basic)) -> None:
    password = settings().lab_password
    if not password:
        return  # no password set: dev mode
    if creds is None or not secrets.compare_digest(creds.password, password):
        raise HTTPException(
            401, "Pep Lab password needed", headers={"WWW-Authenticate": 'Basic realm="Pep Lab"'}
        )


# ---------------------------------------------------------------- operations


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True, "version": MODEL_VERSION}


@app.get("/readyz")
def readyz() -> dict:
    try:
        db.ping()
    except Exception as exc:
        raise HTTPException(503, f"database unreachable: {type(exc).__name__}") from exc
    return {"ok": True}


@app.get("/metrics")
def metrics() -> Response:
    counts = db.status_counts()
    for status in ("QUEUED", "RUNNING", "READY", "FAILED"):
        QUEUE.labels(status).set(counts.get(status, 0))
    OLDEST.set(db.oldest_queued_seconds())
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


# ---------------------------------------------------------------- Tracka


def kick_workers() -> None:
    """Wake the GPU workers (fire and forget: if it fails, the scheduled drain picks the job up)."""
    s = settings()
    if not s.kick_url:
        return
    import httpx

    try:
        httpx.post(s.kick_url, params={"token": s.kick_token}, timeout=10)
    except httpx.HTTPError as exc:
        log.warning("kick.failed", error=str(exc))


@app.post("/analyses", status_code=202, dependencies=[Depends(tracka_auth)])
def create_analysis(req: AnalysisRequest, background: BackgroundTasks) -> dict:
    """Queue a clip. Answers immediately; the result arrives later at callbackUrl."""
    if not req.video_url.startswith(("https://", "http://")):
        raise HTTPException(422, "videoUrl must be an http(s) URL")
    job = db.enqueue(req.to_wire(), source="tracka")
    background.add_task(kick_workers)  # runs after the response is sent
    return {"analysisId": req.analysis_id, "jobId": job["id"], "status": job["status"]}


@app.get("/analyses/{analysis_id}", dependencies=[Depends(tracka_auth)])
def get_analysis(analysis_id: str) -> dict:
    job = db.get_by_analysis(analysis_id)
    if job is None:
        raise HTTPException(404, "No such analysis")
    return {"analysisId": analysis_id, "status": job["status"], "result": job["result"]}


# ---------------------------------------------------------------- Pep Lab


@app.get("/lab/meta", dependencies=[Depends(lab_auth)])
def lab_meta() -> dict:
    return {
        "version": MODEL_VERSION,
        "positions": POSITIONS,
        "roles": {k: {"label": v["label"], "positions": v["positions"]} for k, v in roles().items()},
        "drills": drill_catalogue(),
        "coach": settings().coach_provider if settings().gemini_api_key else "rules",
    }


@app.post("/lab/clips", status_code=202, dependencies=[Depends(lab_auth)])
async def lab_upload(
    background: BackgroundTasks,
    video: UploadFile = File(...),
    request: str = Form("{}", description="JSON with optional AnalysisRequest fields"),
) -> dict:
    """Upload a clip from the Lab and queue it."""
    job_id = str(uuid.uuid4())
    key = f"clips/{job_id}{Path(video.filename or 'clip.mp4').suffix.lower() or '.mp4'}"
    with tempfile.NamedTemporaryFile(suffix=".mp4") as tmp:
        size = 0
        while chunk := await video.read(1 << 20):  # the walrus operator: assign and test in one go
            size += len(chunk)
            if size > MAX_UPLOAD_BYTES:
                raise HTTPException(413, "Clip is larger than 300 MB")
            tmp.write(chunk)
        tmp.flush()
        storage().put(key, Path(tmp.name), video.content_type or "video/mp4")

    try:
        extra = json.loads(request or "{}")
        fields = AnalysisRequest.model_validate({**extra, "analysisId": job_id, "videoUrl": key})
    except ValueError as exc:  # bad JSON, or a field that fails validation
        raise HTTPException(422, f"Bad request fields: {exc}") from None
    job = db.enqueue(fields.to_wire(), source="lab", video_key=key)
    background.add_task(kick_workers)
    return {"id": job["id"], "status": job["status"]}


def best_role(fits: list[dict], positions: list[str]) -> str | None:
    """The best-fitting role among the player's own positions (else the best overall)."""
    wanted = {p.upper() for p in positions}
    mine = [f for f in fits if f.get("coverage", 0) >= 0.35 and wanted & set(roles()[f["role"]]["positions"])]
    pick = mine or fits
    return max(pick, key=lambda f: f["score"])["label"] if pick else None


def _lab_view(job: dict, full: bool = False) -> dict:
    r = job.get("result") or {}
    req = job.get("request") or {}
    view = {
        "id": job["id"],
        "analysisId": job["analysis_id"],
        "source": job["source"],
        "status": job["status"],
        "createdAt": job["created_at"].isoformat() if job.get("created_at") else None,
        "player": req.get("playerLabel") or "Unnamed player",
        "positions": req.get("positions", []),
        "clipType": req.get("clipType", "match"),
        "overallScore": r.get("overallScore"),
        "confidence": r.get("confidence"),
        "topRole": best_role(r.get("roleFit") or [], req.get("positions", [])),
        # role -> fit score, only for roles Pep saw enough of (what the scout filter ranks by)
        "roles": {f["role"]: f["score"] for f in r.get("roleFit") or [] if f.get("coverage", 0) >= 0.35},
        "error": r.get("error") or job.get("error"),
        "attempts": job.get("attempts"),
    }
    if full:
        view |= {
            "request": req,
            "result": r,
            "timings": job.get("timings"),
            "videoUrl": storage().url(job["video_key"]) if job.get("video_key") else req.get("videoUrl"),
            "overlayUrl": storage().url(job["overlay_key"]) if job.get("overlay_key") else None,
            "callback": {
                "status": job.get("callback_status"),
                "attempts": job.get("callback_attempts"),
                "error": job.get("callback_error"),
            },
            "ratings": db.list_ratings(job["id"]),
        }
    return view


@app.get("/lab/analyses", dependencies=[Depends(lab_auth)])
def lab_list(limit: int = 100, source: str | None = None) -> list[dict]:
    return [_lab_view(j) for j in db.list_jobs(min(limit, 500), source)]


@app.get("/lab/analyses/{job_id}", dependencies=[Depends(lab_auth)])
def lab_get(job_id: str) -> dict:
    job = db.get_job(job_id)
    if job is None:
        raise HTTPException(404, "No such analysis")
    return _lab_view(job, full=True)


class RatingIn(BaseModel):
    rater: str = Field(min_length=1, max_length=80)
    overall: int = Field(ge=0, le=100)
    role: str | None = None
    skills: dict[str, int] = Field(default_factory=dict)
    notes: str | None = Field(None, max_length=1000)


@app.post("/lab/analyses/{job_id}/ratings", status_code=201, dependencies=[Depends(lab_auth)])
def lab_rate(job_id: str, rating: RatingIn) -> dict:
    if db.get_job(job_id) is None:
        raise HTTPException(404, "No such analysis")
    rid = db.add_rating(job_id, rating.rater, rating.overall, rating.role, rating.skills, rating.notes)
    return {"id": rid}


@app.get("/lab/agreement", dependencies=[Depends(lab_auth)])
def lab_agreement() -> dict:
    """How closely Pep agrees with scouts: the number that tells you if the model is any good."""
    from ..evaluation import agreement

    pairs = []
    for r in db.list_ratings():
        job = db.get_job(r["job_id"])
        score = ((job or {}).get("result") or {}).get("overallScore")
        if score is not None:
            pairs.append((score, r["overall"]))
    return agreement(pairs)


@app.get("/lab/health", dependencies=[Depends(lab_auth)])
def lab_health() -> dict:
    """The SRE view: is the queue keeping up, how long do jobs take, what's failing."""
    recent = db.recent_finished(24)
    waits = [(j["started_at"] - j["created_at"]).total_seconds() for j in recent if j.get("started_at")]
    totals = [
        float((j.get("timings") or {}).get("total", 0))
        for j in recent
        if (j.get("timings") or {}).get("total")
    ]
    stages: dict[str, list[float]] = {}
    for j in recent:
        for k, v in (j.get("timings") or {}).items():
            stages.setdefault(k, []).append(float(v))

    def pct(xs: list[float], q: float) -> float | None:
        if not xs:
            return None
        xs = sorted(xs)
        return round(xs[min(len(xs) - 1, int(q * len(xs)))], 2)

    return {
        "version": MODEL_VERSION,
        "counts": db.status_counts(),
        "oldestQueuedSeconds": round(db.oldest_queued_seconds(), 1),
        "last24h": {
            "finished": len(recent),
            "failed": sum(j["status"] == "FAILED" for j in recent),
            "callbacksGaveUp": sum(j.get("callback_status") == "GAVE_UP" for j in recent),
            "waitP50": pct(waits, 0.5),
            "waitP95": pct(waits, 0.95),
            "runP50": pct(totals, 0.5),
            "runP95": pct(totals, 0.95),
            "stagesMedian": {k: round(median(v), 2) for k, v in stages.items()},
        },
    }


@app.get("/files/{key:path}")
def signed_file(key: str, exp: int = 0, sig: str = ""):
    """Local-disk storage only: serves a file if its link was signed by us (storage.url)."""
    if not isinstance(storage(), LocalStorage) or not verify_local(key, exp, sig):
        raise HTTPException(403, "link expired or invalid")
    return lab_file(key)


@app.get("/lab/files/{key:path}", dependencies=[Depends(lab_auth)])
def lab_file(key: str):
    st = storage()
    if isinstance(st, LocalStorage):
        try:
            path = st.local_path(key)
        except ValueError:
            raise HTTPException(400, "bad key") from None
        if not path.exists():
            raise HTTPException(404, "not found")
        return FileResponse(path)  # supports Range requests, so video seeking works
    return RedirectResponse(st.url(key))


# ---------------------------------------------------------------- the web UI

app.mount("/assets", StaticFiles(directory=WEB / "assets"), name="assets")


@app.get("/", include_in_schema=False, dependencies=[Depends(lab_auth)])
def index() -> FileResponse:
    return FileResponse(WEB / "index.html")


for _name in ("app.js", "app.css", "manifest.webmanifest"):

    def _static(name: str = _name) -> FileResponse:
        return FileResponse(WEB / name)

    app.add_api_route(f"/{_name}", _static, include_in_schema=False)
