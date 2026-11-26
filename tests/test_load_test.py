"""The load-test script runs against the app in-process and cleans up after itself."""

from __future__ import annotations

import asyncio
import importlib.util
from pathlib import Path

import httpx
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from pep import db
from pep.api.app import app
from pep.players import store

spec = importlib.util.spec_from_file_location(
    "load_test", Path(__file__).parents[1] / "scripts" / "load_test.py"
)
assert spec and spec.loader
load_test = importlib.util.module_from_spec(spec)
spec.loader.exec_module(load_test)


def test_load_test_measures_calls_and_deletes_its_players():
    with TestClient(app):  # start-up: tables exist
        transport = httpx.ASGITransport(app=app)
        results = asyncio.run(
            load_test.run("http://test", players=3, seconds=0.5, think=0, transport=transport)
        )
    report = results.report(0.5)
    assert "/v1/me" in report and "p95" in report
    assert sum(results.errors.values()) == 0, report
    with db.engine().connect() as c:
        assert c.execute(select(func.count()).select_from(store.users)).scalar_one() == 0
