"""Back up the test database, restore it into a fresh one, and check nothing was lost."""

from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from test_player_api import complete_profile, signup

from pep.api.app import app
from pep.config import settings

spec = importlib.util.spec_from_file_location("backup", Path(__file__).parents[1] / "scripts" / "backup.py")
assert spec and spec.loader
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


@pytest.mark.skipif(
    not settings().database_url.startswith("sqlite"), reason="the Postgres path needs pg_dump"
)
def test_backup_restore_check_round_trip(tmp_path):
    with TestClient(app) as client:
        complete_profile(client, signup(client))
    dump = backup.backup(tmp_path, settings().database_url)
    target = f"sqlite:///{tmp_path / 'drill.db'}"
    backup.restore(dump, target)
    live, restored = backup.check(settings().database_url), backup.check(target)
    assert restored["tables"] == live["tables"] and restored["tables"]["users"] == 1
    assert restored["orphans"] == {} and restored["newest"]["users"]
    # A database with players is never overwritten by accident.
    with pytest.raises(SystemExit):
        backup.restore(dump, target)
