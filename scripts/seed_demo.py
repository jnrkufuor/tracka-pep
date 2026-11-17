"""
Fills a database with a demo player and analysed clips, so the app has something to show.

    python scripts/seed_demo.py            # uses PEP_DATABASE_URL / PEP_STORAGE_DIR

Used by the screenshot workflow (.github/workflows/screenshots.yml) and handy
for designing screens locally without running the AI models. The scores are
produced by Pep's real scoring code (norms, skills, roles) from realistic
made-up measurements, so explanations and drills read exactly like real ones.

Demo login: demo@tracka.app / tracka-demo-123
"""

from __future__ import annotations

import subprocess
import tempfile
from datetime import date, timedelta
from pathlib import Path

from pep import MODEL_VERSION, db
from pep.coach.merge import rules_summary
from pep.contracts import CoachResult, Moment
from pep.players import auth, store
from pep.scoring.roles import overall, overall_confidence, role_fits
from pep.scoring.skills import Context, score_skills
from pep.storage import storage

EMAIL, PASSWORD = "demo@tracka.app", "tracka-demo-123"
VIDEO_IDS = [f"00000000-0000-4000-8000-00000000000{i}" for i in range(1, 7)]

CLIPS = [
    # title, clip type, days ago, measurements
    (
        "Sunday league vs Hearts U19",
        "match",
        2,
        {
            "top_speed_ms": 7.9,
            "peak_accel_ms2": 4.1,
            "distance_per_min_m": 112,
            "moving_share": 0.55,
            "turns_per_min": 6.2,
            "ball_at_feet_share": 0.58,
            "touches_per_min": 24,
            "close_control_m": 0.85,
            "ready_knee_deg": 150,
            "head_checks_per_min": 5,
            "seconds_tracked": 74,
            "high_speed_runs": 4,
            "distance_m": 138,
        },
    ),
    (
        "30 m sprint test",
        "drill",
        5,
        {
            "sprint_30m_s": 4.31,
            "split_10m_s": 1.78,
            "top_speed_ms": 8.1,
            "seconds_tracked": 7,
            "distance_m": 34,
        },
    ),
    (
        "Training: 1v1s",
        "training",
        9,
        {
            "top_speed_ms": 7.4,
            "peak_accel_ms2": 3.8,
            "turns_per_min": 7.5,
            "ball_at_feet_share": 0.62,
            "touches_per_min": 28,
            "close_control_m": 0.78,
            "ready_knee_deg": 148,
            "seconds_tracked": 40,
            "moving_share": 0.6,
            "distance_per_min_m": 104,
            "distance_m": 70,
            "high_speed_runs": 2,
        },
    ),
    ("Keepy-ups", "drill", 15, {"juggles_best": 42, "juggles_total": 88, "seconds_tracked": 50}),
    (
        "Cup match, second half",
        "match",
        22,
        {
            "top_speed_ms": 7.6,
            "peak_accel_ms2": 3.6,
            "distance_per_min_m": 98,
            "moving_share": 0.5,
            "turns_per_min": 5.0,
            "ball_at_feet_share": 0.5,
            "touches_per_min": 19,
            "close_control_m": 1.0,
            "ready_knee_deg": 156,
            "head_checks_per_min": 4,
            "seconds_tracked": 95,
            "high_speed_runs": 3,
            "distance_m": 155,
        },
    ),
]

MOMENTS = [
    Moment(at_seconds=4.2, kind="GOOD", text="Great burst here: you beat your man in two steps."),
    Moment(
        at_seconds=11.8,
        kind="WORK_ON",
        text="Heavy touch: the ball ran 3 m ahead and the defender recovered.",
    ),
    Moment(at_seconds=19.5, kind="GOOD", text="You checked your shoulder before receiving. Keep doing that."),
]


def media(tmp: Path, i: int) -> tuple[Path, Path]:
    """A short pitch-green clip with a moving 'player', and a thumbnail from it (needs ffmpeg)."""
    clip, thumb = tmp / f"clip{i}.mp4", tmp / f"thumb{i}.jpg"
    draw = f"drawbox=x='40+t*{60 + i * 10}':y=150:w=40:h=110:color=0xF2F4EC:t=fill,drawbox=x=0:y=118:w=iw:h=4:color=white:t=fill"
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            "color=c=0x2E8A3E:s=640x360:d=8",
            "-vf",
            draw,
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            str(clip),
        ],
        check=True,
    )
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-ss", "3", "-i", str(clip), "-frames:v", "1", str(thumb)],
        check=True,
    )
    return clip, thumb


def main() -> None:
    db.engine()
    if store.user_by_email(EMAIL):
        uid = store.user_by_email(EMAIL)["id"]  # type: ignore[index]
        store.delete_user(uid)
    user = store.create_user(EMAIL, auth.hash_password(PASSWORD))
    uid = user["id"]
    store.update_profile(
        uid,
        {
            "display_name": "Kwame Asante",
            "birth_date": date(2007, 5, 12),
            "sex": "male",
            "height_m": 1.76,
            "positions": ["RW", "ST"],
            "foot": "right",
            "region": "Ashanti",
            "club": "Kumasi Youngsters FC",
            "guardian_consent": False,
        },
    )
    positions = ["RW", "ST"]
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        for i, (title, clip_type, days, metrics) in enumerate(CLIPS):
            vid = VIDEO_IDS[i]
            clip, thumb = media(tmp, i)
            key, thumb_key = f"players/{uid}/videos/{vid}.mp4", f"thumbs/{vid}.jpg"
            storage().put(key, clip)
            storage().put(thumb_key, thumb, "image/jpeg")
            ctx = Context(
                age=19,
                sex="male",
                clip_type=clip_type,
                method="homography" if clip_type == "drill" else "body",
                seconds_tracked=metrics.get("seconds_tracked", 0),
            )
            skills = [s.skill for s in score_skills(metrics, ctx)]
            fits = role_fits(skills)
            result = CoachResult(
                analysis_id=vid,
                status="READY",
                model_version=MODEL_VERSION,
                overall_score=overall(skills, fits, positions),
                confidence=overall_confidence(skills, fits, positions),
                skills=skills,
                moments=MOMENTS if clip_type != "drill" else [],
                clip_type=clip_type,
                role_fit=fits,
                metrics=metrics,
                summary=rules_summary(skills),
                coach_source="rules",
            ).to_wire()
            job = db.enqueue(
                {"analysisId": vid, "videoUrl": key, "positions": positions}, "app", video_key=key
            )
            claimed = db.claim("seed", 60)
            assert claimed and claimed["id"] == job["id"]
            db.finish(job["id"], "seed", result, {"total": 41.2}, key, callback=False, thumb_key=thumb_key)
            store.add_video(
                uid,
                vid,
                title,
                key,
                clip_type,
                "sprint_30m" if "sprint" in title.lower() else None,
                clip.stat().st_size,
                job["id"],
            )
            created = db.now() - timedelta(days=days)
            with db.engine().begin() as c:
                c.execute(store.videos.update().where(store.videos.c.id == vid).values(created_at=created))
        # One clip still being analysed.
        vid = VIDEO_IDS[5]
        clip, _ = media(tmp, 5)
        key = f"players/{uid}/videos/{vid}.mp4"
        storage().put(key, clip)
        job = db.enqueue({"analysisId": vid, "videoUrl": key, "positions": positions}, "app", video_key=key)
        store.add_video(uid, vid, "Friday training", key, "training", None, clip.stat().st_size, job["id"])
    print(f"demo player ready: {EMAIL} / {PASSWORD}; first video {VIDEO_IDS[0]}")


if __name__ == "__main__":
    main()
