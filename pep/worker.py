"""
The worker: takes jobs from the queue and analyses them.

    while not stopping:
        deliver any results waiting to go back to Tracka
        job = claim the next job (or sleep and try again)
        download the clip -> analyse -> save the result -> queue the callback

Things that make it production-grade rather than a script:

  * HEARTBEAT. A background thread extends the job's lease every minute, so
    a long analysis isn't mistaken for a dead worker. If the heartbeat finds
    the job was taken over, we stop.
  * GRACEFUL SHUTDOWN. Render, Modal and Kubernetes stop processes by
    sending SIGTERM, then SIGKILL some seconds later. On SIGTERM we finish
    (or hand back) the current job instead of dying mid-write.
  * RETRIES WITH BACKOFF for errors that might go away (network, a GPU
    hiccup); NO retries for clips that simply can't be read (CantReadClip):
    retrying those just wastes GPU money.
  * The model is loaded ONCE per process (loading YOLO takes seconds;
    analysing a frame takes milliseconds).

Run one with `pep worker`. Run several to go faster: the queue makes sure
each job goes to exactly one of them at a time.
"""

from __future__ import annotations

import os
import signal
import socket
import tempfile
import threading
import time
import traceback
from pathlib import Path

import httpx

from . import MODEL_VERSION, db
from .callbacks import deliver_due
from .config import settings
from .contracts import AnalysisRequest, CoachResult
from .log import get_logger
from .storage import storage

log = get_logger(__name__)

MAX_DOWNLOAD_BYTES = 400 * 1024 * 1024


class Worker:
    def __init__(self, perceiver=None) -> None:
        self.name = f"{socket.gethostname()}-{os.getpid()}"
        self.stopping = threading.Event()
        self._perceiver = perceiver

    @property
    def perceiver(self):
        if self._perceiver is None:
            from .vision.perception import YoloPerceiver

            self._perceiver = YoloPerceiver()
        return self._perceiver

    def run(self, drain: bool = False) -> None:
        """Process jobs until stopped (or, with drain=True, until the queue is empty)."""
        s = settings()
        if threading.current_thread() is threading.main_thread():
            signal.signal(signal.SIGTERM, lambda *_: self.stop())
            signal.signal(signal.SIGINT, lambda *_: self.stop())
        log.info("worker.start", worker=self.name, drain=drain)
        while not self.stopping.is_set():
            deliver_due()
            job = db.claim(self.name, s.job_lease_seconds)
            if job is None:
                if drain:
                    break
                self.stopping.wait(s.worker_poll_seconds)
                continue
            self.process(job)
        deliver_due()
        log.info("worker.stop", worker=self.name)

    def stop(self) -> None:
        log.info("worker.stopping", worker=self.name)
        self.stopping.set()

    def process(self, job: dict) -> None:
        from .pipeline import CantReadClip, analyse

        req = AnalysisRequest.model_validate(job["request"])
        log.info("job.start", job_id=job["id"], analysis_id=req.analysis_id, attempt=job["attempts"])
        beat_stop = threading.Event()
        beat = threading.Thread(target=self._heartbeat, args=(job["id"], beat_stop), daemon=True)
        beat.start()
        started = time.monotonic()
        try:
            with tempfile.TemporaryDirectory(prefix="pep-") as tmp:
                video = self._fetch(job, Path(tmp))
                analysis = analyse(video, req, self.perceiver)
                overlay_key = thumb_key = None
                # Players (app) and staff (lab) see "what Pep saw" and a cover image.
                # Tracka's own clips skip both: it has its own thumbnails, and it saves time.
                if job["source"] in ("lab", "app"):
                    overlay_key = self._overlay(video, analysis, job["id"], Path(tmp))
                    thumb_key = self._thumbnail(video, analysis, job["id"], Path(tmp))
                timings = analysis.timings | {"total": round(time.monotonic() - started, 2)}
                db.finish(
                    job["id"],
                    self.name,
                    analysis.result.to_wire(),
                    timings,
                    overlay_key,
                    callback=bool(req.callback_url),
                    thumb_key=thumb_key,
                )
                log.info("job.done", job_id=job["id"], seconds=timings["total"])
        except CantReadClip as exc:
            # The clip itself is the problem: tell the player, don't retry.
            failed = CoachResult.failed(req.analysis_id, str(exc), MODEL_VERSION)
            db.finish(job["id"], self.name, failed.to_wire(), {}, None, callback=bool(req.callback_url))
            log.info("job.unreadable", job_id=job["id"], reason=str(exc))
        except Exception as exc:
            log.error("job.error", job_id=job["id"], error=str(exc), trace=traceback.format_exc()[-2000:])
            if not db.retry_later(job["id"], self.name, str(exc), job["attempts"]):
                failed = CoachResult.failed(
                    req.analysis_id,
                    "Something went wrong reading this clip. Please try again later.",
                    MODEL_VERSION,
                )
                db.finish(job["id"], self.name, failed.to_wire(), {}, None, callback=bool(req.callback_url))
        finally:
            beat_stop.set()
            beat.join(timeout=5)
            if job["source"] == "app":  # tell the player (bell + push); never fails the job
                from .players.notifications import clip_finished

                clip_finished(job["id"])

    def _heartbeat(self, job_id: str, stop: threading.Event) -> None:
        s = settings()
        every = max(5, s.job_lease_seconds // 3)
        while not stop.wait(every):
            if not db.heartbeat(job_id, self.name, s.job_lease_seconds):
                log.warning("job.lost_lease", job_id=job_id)
                return

    def _fetch(self, job: dict, tmp: Path) -> Path:
        dest = tmp / "clip.mp4"
        if job.get("video_key"):
            return storage().fetch(job["video_key"], dest)
        url = job["request"]["videoUrl"]
        # Stream to disk in chunks: never hold a whole video in memory.
        with httpx.stream("GET", url, timeout=60, follow_redirects=True) as resp:
            resp.raise_for_status()
            size = 0
            with dest.open("wb") as f:
                for chunk in resp.iter_bytes(1 << 20):
                    size += len(chunk)
                    if size > MAX_DOWNLOAD_BYTES:
                        raise ValueError("clip is larger than 400 MB")
                    f.write(chunk)
        return dest

    def _overlay(self, video: Path, analysis, job_id: str, tmp: Path) -> str | None:
        from .overlay import render_overlay

        try:
            out = render_overlay(video, analysis, tmp / "overlay.mp4")
            key = f"overlays/{job_id}.mp4"
            storage().put(key, out)
            return key
        except Exception as exc:  # a missing debug video must never fail the analysis
            log.warning("overlay.failed", job_id=job_id, error=str(exc))
            return None

    def _thumbnail(self, video: Path, analysis, job_id: str, tmp: Path) -> str | None:
        from .overlay import render_thumbnail

        try:
            out = render_thumbnail(video, analysis, tmp / "thumb.jpg")
            key = f"thumbs/{job_id}.jpg"
            storage().put(key, out, "image/jpeg")
            return key
        except Exception as exc:
            log.warning("thumbnail.failed", job_id=job_id, error=str(exc))
            return None


def start_inline_worker() -> Worker:
    """Runs a worker thread inside the API process. Handy locally; use real workers in production."""
    w = Worker()
    threading.Thread(target=w.run, name="pep-inline-worker", daemon=True).start()
    return w
