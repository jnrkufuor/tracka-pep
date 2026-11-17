"""
GPU workers on Modal (serverless GPUs, billed per second).

Why Modal for the heavy part: a GPU sitting idle all day is expensive; clips
arrive in bursts. Modal starts a GPU container when there's work and stops it
when there isn't, so you pay for seconds of compute, not hours of waiting.

How it plugs in: Modal workers read the SAME Postgres queue as everyone
else. Nothing in the API changes. Two triggers:
  * `drain` runs every 2 minutes (a safety net), and
  * `kick` is a web endpoint the API can call right after queueing a job, so
    clips start within seconds instead of waiting for the next tick.

Deploy (CI does this on every push to main):
    pip install modal && modal token new          # once
    modal secret create pep-secrets PEP_DATABASE_URL=... COACH_WEBHOOK_SECRET=... \
        GEMINI_API_KEY=... PEP_STORAGE=s3 PEP_S3_BUCKET=pep-clips PEP_S3_ENDPOINT=... \
        PEP_S3_ACCESS_KEY=... PEP_S3_SECRET_KEY=... PEP_KICK_TOKEN=...
    modal deploy deploy/modal_app.py

Costs: an L4 GPU is a good fit for YOLO26 (cheap, plenty fast). Check
Modal's current price list; docs/handbook/12-cost-privacy-next.md has a worked example.
"""

from __future__ import annotations

import os

import modal

app = modal.App("tracka-pep")

image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("ffmpeg", "libgl1", "libglib2.0-0")
    .pip_install_from_pyproject("pyproject.toml", optional_dependencies=["vision", "coach", "train"])
    .env({"PEP_MODELS_DIR": "/models", "PEP_ENV": "prod", "PEP_DEVICE": "cuda:0"})
    # Bake the weights into the image: no download on cold start.
    .run_commands(
        "mkdir -p /models && cd /models && python -c \"from ultralytics import YOLO; YOLO('yolo26s.pt'); YOLO('yolo26n-pose.pt')\""
    )
    .add_local_python_source("pep")
)

secrets = [modal.Secret.from_name("pep-secrets")]


@app.function(
    image=image,
    gpu="L4",
    secrets=secrets,
    timeout=60 * 30,  # one drain may process many clips
    max_containers=4,  # never more than 4 GPUs at once: a hard cap on spend
    schedule=modal.Period(minutes=2),
)
def drain() -> int:
    """Process queued jobs until the queue is empty, then exit (and stop paying)."""
    from pep import db
    from pep.log import setup_logging
    from pep.worker import Worker

    setup_logging()
    before = db.status_counts().get("QUEUED", 0)
    Worker().run(drain=True)
    return before


@app.function(image=image, secrets=secrets)
@modal.fastapi_endpoint(method="POST")
def kick(token: str = "") -> dict:
    """Called by the API after queueing: start draining now. Protected by a shared token."""
    if not token or token != os.environ.get("PEP_KICK_TOKEN"):
        return {"ok": False}
    drain.spawn()  # run in the background; answer immediately
    return {"ok": True}
