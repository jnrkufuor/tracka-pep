"""
Where files live: uploaded clips and debug overlay videos.

Two backends behind one small interface:
  LocalStorage  a folder on disk. Fine on your laptop; useless on Render,
                whose disks are wiped on every deploy ("ephemeral filesystem").
  S3Storage     any S3-compatible object store. We use Cloudflare R2: same
                API as Amazon S3 (so boto3 works unchanged), and no fees for
                downloading ("egress"), which matters when every clip is
                downloaded by a GPU worker and streamed to scouts.

PRESIGNED URLS: instead of proxying video bytes through our API, we hand out
a link that works for a limited time and is signed with our secret key. The
browser (or Gemini, or the worker) fetches straight from R2. Cheaper,
faster, and the bucket stays private.
"""

from __future__ import annotations

import shutil
from functools import cache
from pathlib import Path
from typing import Protocol

from .config import settings


class Storage(Protocol):
    def put(self, key: str, src: Path, content_type: str = "video/mp4") -> None: ...
    def fetch(self, key: str, dest: Path) -> Path: ...
    def url(self, key: str, expires_s: int = 3600) -> str: ...


class LocalStorage:
    def __init__(self, root: Path) -> None:
        self.root = root
        root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        p = (self.root / key).resolve()
        if self.root.resolve() not in p.parents:  # never let a key like "../../etc/passwd" escape the folder
            raise ValueError("bad key")
        return p

    def put(self, key: str, src: Path, content_type: str = "video/mp4") -> None:
        dest = self._path(key)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)

    def fetch(self, key: str, dest: Path) -> Path:
        shutil.copyfile(self._path(key), dest)
        return dest

    def url(self, key: str, expires_s: int = 3600) -> str:
        return f"/lab/files/{key}"

    def local_path(self, key: str) -> Path:
        return self._path(key)


class S3Storage:
    def __init__(self) -> None:
        import boto3

        s = settings()
        self.bucket = s.s3_bucket
        self.client = boto3.client(
            "s3",
            endpoint_url=s.s3_endpoint or None,
            aws_access_key_id=s.s3_access_key,
            aws_secret_access_key=s.s3_secret_key,
            region_name=s.s3_region,
        )

    def put(self, key: str, src: Path, content_type: str = "video/mp4") -> None:
        # upload_file switches to multipart upload for big files automatically
        self.client.upload_file(str(src), self.bucket, key, ExtraArgs={"ContentType": content_type})

    def fetch(self, key: str, dest: Path) -> Path:
        self.client.download_file(self.bucket, key, str(dest))
        return dest

    def url(self, key: str, expires_s: int = 3600) -> str:
        return self.client.generate_presigned_url(
            "get_object", Params={"Bucket": self.bucket, "Key": key}, ExpiresIn=expires_s
        )


@cache
def storage() -> Storage:
    s = settings()
    return S3Storage() if s.storage == "s3" else LocalStorage(s.storage_dir)
