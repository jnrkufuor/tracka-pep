"""
Every setting Pep reads, in one place.

Settings come from environment variables (or a `.env` file locally). That is
the "12-factor app" rule: the same code and the same Docker image run on your
laptop, on Render and on Modal; only the environment changes. Secrets (API
keys, database passwords) never go in the code or in git.

pydantic-settings reads the variables, converts types ("8" -> 8,
"true" -> True) and fails loudly at start-up if something is malformed. Fail
at boot, not at 2am on the first request.

Every variable is prefixed PEP_ except the few Tracka already uses
(COACH_API_KEY, COACH_WEBHOOK_SECRET) so the two services share names.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

ROOT = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    # env_ignore_empty: a setting left blank (an empty box in Render) means "use
    # the default", instead of crashing on start-up for lists like cors_origins.
    model_config = SettingsConfigDict(
        env_file=".env", env_prefix="PEP_", extra="ignore", env_ignore_empty=True
    )

    # ---- service
    env: Literal["dev", "test", "prod"] = "dev"
    log_level: str = "INFO"
    # Where this service can be reached (used to build links to uploaded clips in dev).
    public_url: str = "http://localhost:8000"

    # ---- security
    # Tracka sends `Authorization: Bearer <COACH_API_KEY>`; we check it.
    api_key: str = Field("dev-key", validation_alias=AliasChoices("COACH_API_KEY", "PEP_API_KEY"))
    # We sign callbacks with this; Tracka checks the signature. Same name both sides.
    webhook_secret: str = Field(
        "dev-secret", validation_alias=AliasChoices("COACH_WEBHOOK_SECRET", "PEP_WEBHOOK_SECRET")
    )
    # Signs players' login tokens (JWT). Long and random in production; changing it logs everyone out.
    jwt_secret: str = "dev-jwt-secret-change-me-please-32b"
    access_token_minutes: int = 30
    refresh_token_days: int = 60
    # Browser origins allowed to call the player API (the Flutter web app). "*" is fine in dev.
    cors_origins: list[str] = ["*"]
    # Password for the Pep Lab web UI (HTTP Basic, user "lab"). Empty = no password (dev only).
    lab_password: str = ""
    # Error tracking (Sentry, or anything that speaks its protocol, like GlitchTip).
    # Empty = off: errors still go to the logs. See pep/errors.py and docs/RUNBOOK.md.
    sentry_dsn: str = ""
    # Shown on the public pages (/delete-account, /child-safety) and in the store listings.
    support_email: str = "support@tracka.app"

    # ---- data
    # SQLite needs no setup, which is perfect locally. In production use Postgres:
    # postgresql+psycopg://user:pass@host:5432/pep
    database_url: str = f"sqlite:///{ROOT / 'var' / 'pep.db'}"
    # "local" keeps files on disk; "s3" means any S3-compatible store (Cloudflare R2, AWS S3, MinIO).
    storage: Literal["local", "s3"] = "local"
    storage_dir: Path = ROOT / "var" / "files"
    s3_bucket: str = ""
    s3_endpoint: str = ""  # R2: https://<account>.r2.cloudflarestorage.com
    s3_access_key: str = ""
    s3_secret_key: str = ""
    s3_region: str = "auto"

    # ---- worker
    # Run a worker thread inside the API process: one command does everything locally.
    # In production keep it off and run real workers (Render worker, Modal GPU).
    inline_worker: bool = False
    worker_poll_seconds: float = 2.0
    # A claimed job is "leased" for this long. If the worker dies, the lease runs out
    # and another worker picks the job up. The worker renews it while it works.
    # Optional: a URL to POST after queueing a job, to wake GPU workers at once
    # (the Modal `kick` endpoint). Without it, workers find jobs on their next poll.
    kick_url: str = ""
    kick_token: str = ""
    job_lease_seconds: int = 300
    job_max_attempts: int = 3
    job_timeout_seconds: int = 900
    callback_max_attempts: int = 6

    # ---- vision
    detector_model: str = "yolo26s.pt"  # n (fastest) / s / m / l / x (most accurate)
    pose_model: str = "yolo26n-pose.pt"
    tracker: str = "bytetrack.yaml"  # or botsort.yaml (adds re-identification)
    samples_per_second: float = 10.0  # frames analysed per second of video
    max_side: int = 1280  # frames are shrunk so their longest side is this many pixels
    device: str = ""  # "" lets Ultralytics choose; "cuda:0", "cpu", "mps"
    models_dir: Path = ROOT / "var" / "models"

    # ---- texts (SMS): PLACEHOLDER until a provider is chosen (pep/players/sms.py)
    sms_provider: Literal["log"] = "log"
    sms_webhook_secret: str = ""  # replies like "YES 4F7K" come in at /v1/sms/inbound with this
    # While texts can't reach guardians, under-18s can tick "they've already said yes".
    guardian_self_confirm: bool = True
    # Where guardians and card links open (the public web address of this API for now).
    web_url: str = ""

    # ---- push (Firebase Cloud Messaging): pep/players/push.py, docs/PUSH_SETUP.md
    fcm_service_account: str = ""  # the service account JSON, as text
    fcm_project_id: str = ""

    # ---- AI coach (language model that watches the clip and writes feedback)
    coach_provider: Literal["gemini", "none"] = "gemini"
    gemini_api_key: str = Field("", validation_alias=AliasChoices("GEMINI_API_KEY", "PEP_GEMINI_API_KEY"))
    coach_model: str = "gemini-3.8-flash"
    coach_timeout_seconds: int = 120

    # ---- scoring
    # A model trained on scout ratings (training/train_scorer.py). Optional: without
    # it Pep scores with the norms in pep/data/norms.json.
    learned_scorer_path: Path = ROOT / "var" / "models" / "scorer.joblib"

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")


@lru_cache
def settings() -> Settings:
    """One Settings object for the whole process (lru_cache makes it a cheap singleton)."""
    s = Settings()
    if s.is_sqlite:
        Path(s.database_url.removeprefix("sqlite:///")).parent.mkdir(parents=True, exist_ok=True)
    s.storage_dir.mkdir(parents=True, exist_ok=True)
    s.models_dir.mkdir(parents=True, exist_ok=True)
    return s
