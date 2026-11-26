"""
Back up the database, restore it, and check a restore worked.

WHY (handbook chapter 10, "Backups you have tested"): a backup you have never
restored is a hope, not a backup. Hosting providers keep their own copies, but
you still want (1) a copy somewhere they don't control, and (2) a habit of
restoring it into a spare database to prove it works. docs/RUNBOOK.md has the
monthly drill.

    python scripts/backup.py backup               # writes var/backups/pep-<time>.dump (or .db)
    python scripts/backup.py backup --upload      # ...and copies it to the backup bucket
    python scripts/backup.py restore FILE --into postgresql://.../pep_drill
    python scripts/backup.py check  postgresql://.../pep_drill

Postgres uses `pg_dump -Fc` (the "custom" format: compressed, and pg_restore
can restore one table from it). SQLite (local and tests) uses SQLite's own
online backup, which is safe while the API is running.

Clips are not in the database: they live in object storage (R2/S3). Turn on
versioning for that bucket so a deleted clip can be brought back for 30 days
(see the runbook).
"""

from __future__ import annotations

import argparse
import os
import shutil
import sqlite3
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy import create_engine, func, inspect, select, text

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def _url() -> str:
    from pep.config import settings

    return settings().database_url


def _pg(url: str) -> str:
    """pg_dump wants postgresql://, SQLAlchemy uses postgresql+psycopg://."""
    return url.replace("postgresql+psycopg://", "postgresql://", 1)


def _sqlite_path(url: str) -> Path:
    return Path(url.split("sqlite:///", 1)[1])


def backup(out_dir: Path, url: str | None = None) -> Path:
    url = url or _url()
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    if url.startswith("sqlite"):
        dest = out_dir / f"pep-{stamp}.db"
        src = sqlite3.connect(_sqlite_path(url))
        dst = sqlite3.connect(dest)
        with dst:
            src.backup(dst)
        src.close()
        dst.close()
    else:
        dest = out_dir / f"pep-{stamp}.dump"
        subprocess.run(["pg_dump", "-Fc", "--no-owner", "--no-acl", "-f", str(dest), _pg(url)], check=True)
    return dest


def upload(path: Path) -> str:
    """Copy a backup to PEP_BACKUP_BUCKET (keep it separate from the clips bucket)."""
    import boto3

    from pep.config import settings

    s = settings()
    bucket = os.environ.get("PEP_BACKUP_BUCKET") or s.s3_bucket
    if not bucket:
        raise SystemExit("Set PEP_BACKUP_BUCKET (or PEP_S3_BUCKET) to upload backups.")
    key = f"backups/{path.name}"
    boto3.client(
        "s3",
        endpoint_url=s.s3_endpoint or None,
        aws_access_key_id=s.s3_access_key,
        aws_secret_access_key=s.s3_secret_key,
        region_name=s.s3_region,
    ).upload_file(str(path), bucket, key)
    return f"{bucket}/{key}"


def _has_users(url: str) -> bool:
    eng = create_engine(url)
    try:
        if "users" not in inspect(eng).get_table_names():
            return False
        with eng.connect() as c:
            return bool(c.execute(text("select count(*) from users")).scalar_one())
    finally:
        eng.dispose()


def restore(path: Path, into: str, force: bool = False) -> None:
    """Restore a backup into a database. Refuses to overwrite one that has players, unless forced."""
    if _has_users(into) and not force:
        raise SystemExit("That database already has players. Restore into an empty one, or pass --force.")
    if into.startswith("sqlite"):
        shutil.copyfile(path, _sqlite_path(into))
    else:
        subprocess.run(
            ["pg_restore", "--clean", "--if-exists", "--no-owner", "--no-acl", "-d", _pg(into), str(path)],
            check=True,
        )


def check(url: str) -> dict:
    """Row counts, how new the newest data is, and rows whose player is missing."""
    eng = create_engine(url)
    from sqlalchemy import MetaData

    md = MetaData()
    md.reflect(eng)
    report: dict = {"tables": {}, "orphans": {}, "newest": {}}
    with eng.connect() as c:
        for name, t in sorted(md.tables.items()):
            report["tables"][name] = c.execute(select(func.count()).select_from(t)).scalar_one()
            if "users" in md.tables and name != "users" and "user_id" in t.c:
                users = md.tables["users"]
                q = (
                    select(func.count())
                    .select_from(t)
                    .where(t.c.user_id.is_not(None), t.c.user_id.not_in(select(users.c.id)))
                )
                n = c.execute(q).scalar_one()
                if n:
                    report["orphans"][name] = n
            if name in {"users", "videos"} and "created_at" in t.c:
                newest = c.execute(select(func.max(t.c.created_at))).scalar_one()
                report["newest"][name] = str(newest) if newest else None
    eng.dispose()
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description="Back up, restore and check Pep's database.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("backup")
    b.add_argument("--out", type=Path, default=ROOT / "var" / "backups")
    b.add_argument("--upload", action="store_true")
    r = sub.add_parser("restore")
    r.add_argument("file", type=Path)
    r.add_argument("--into", required=True)
    r.add_argument("--force", action="store_true")
    k = sub.add_parser("check")
    k.add_argument("url", nargs="?")
    a = ap.parse_args()

    if a.cmd == "backup":
        path = backup(a.out)
        print(f"Backed up to {path} ({path.stat().st_size / 1e6:.1f} MB)")
        if a.upload:
            print(f"Uploaded to {upload(path)}")
    elif a.cmd == "restore":
        restore(a.file, a.into, a.force)
        print("Restored. Now run: python scripts/backup.py check " + a.into.split("@")[-1])
    else:
        rep = check(a.url or _url())
        for name, n in rep["tables"].items():
            print(f"{name:28} {n:8}")
        print("newest:", rep["newest"])
        print("orphans:", rep["orphans"] or "none")
        return 1 if rep["orphans"] else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
