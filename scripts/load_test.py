"""
A small load test: many pretend players using the app at once.

WHY (handbook chapter 10, "Capacity"): you want to know where the API slows
down *before* a school tournament sends 500 players to it on the same evening.
A load test makes fake players do what real ones do (open Home, look at their
clips, check Pep) and measures how long each call takes. Watch the p95: the
time 95 out of 100 calls beat. Averages hide the slow calls players feel.

Each pretend player signs up (an adult test account, so no guardian texts are
sent), fills in a profile, then loops over the screens the app opens most.
At the end their accounts are deleted.

    python scripts/load_test.py --url http://localhost:8000 --players 50 --seconds 60

It refuses to run against anything but localhost unless you pass --i-own-this,
because a load test against someone else's server is an attack. Uploads are not
included: they cost GPU time; test those with a handful of real clips.
"""

from __future__ import annotations

import argparse
import asyncio
import random
import statistics
import sys
import time
import uuid
from collections import defaultdict
from urllib.parse import urlparse

import httpx

# What the app calls when you open it and move between tabs, roughly in proportion.
SCREENS = [
    ("/v1/me", 3),
    ("/v1/progress", 2),
    ("/v1/week", 2),
    ("/v1/videos", 2),
    ("/v1/focus", 1),
    ("/v1/notifications", 2),
    ("/v1/pitches", 2),
    ("/v1/coach", 1),
]
PROFILE = {
    "displayName": "Load Test",
    "birthDate": "1995-01-01",
    "sex": "male",
    "heightM": 1.75,
    "positions": ["CM"],
    "region": "Greater Accra",
    "foot": "right",
}


class Results:
    def __init__(self) -> None:
        self.times: dict[str, list[float]] = defaultdict(list)
        self.errors: dict[str, int] = defaultdict(int)

    def add(self, path: str, seconds: float, ok: bool) -> None:
        self.times[path].append(seconds)
        if not ok:
            self.errors[path] += 1

    def report(self, wall: float) -> str:
        def pct(xs: list[float], p: float) -> float:
            xs = sorted(xs)
            return xs[min(len(xs) - 1, int(p / 100 * len(xs)))] * 1000

        lines = [f"{'call':22} {'count':>6} {'errors':>6} {'p50 ms':>8} {'p95 ms':>8} {'p99 ms':>8}"]
        total = errors = 0
        for path in sorted(self.times):
            xs = self.times[path]
            total += len(xs)
            errors += self.errors[path]
            lines.append(
                f"{path:22} {len(xs):6} {self.errors[path]:6} {statistics.median(xs) * 1000:8.0f}"
                f" {pct(xs, 95):8.0f} {pct(xs, 99):8.0f}"
            )
        lines.append(
            f"\n{total} calls in {wall:.1f} s = {total / max(wall, 0.001):.1f} a second; "
            f"{errors} errors ({100 * errors / max(total, 1):.2f}%)"
        )
        return "\n".join(lines)


async def player(client: httpx.AsyncClient, results: Results, until: float, think: float) -> None:
    async def call(method: str, path: str, label: str | None = None, **kw) -> httpx.Response | None:
        t = time.perf_counter()
        try:
            r = await client.request(method, path, **kw)
            results.add(label or path, time.perf_counter() - t, r.status_code < 400)
            return r
        except httpx.HTTPError:
            results.add(label or path, time.perf_counter() - t, False)
            return None

    email = f"load-{uuid.uuid4().hex[:10]}@example.com"
    r = await call("POST", "/v1/auth/signup", json={"email": email, "password": "load-test-pass"})
    if r is None or r.status_code != 201:
        return
    h = {"Authorization": f"Bearer {r.json()['accessToken']}"}
    await call("PATCH", "/v1/me", label="PATCH /v1/me", json=PROFILE, headers=h)
    paths, weights = zip(*SCREENS, strict=True)
    try:
        while time.perf_counter() < until:
            await call("GET", random.choices(paths, weights)[0], headers=h)
            if think:
                await asyncio.sleep(random.uniform(0, 2 * think))  # people pause between taps
    finally:
        await call("DELETE", "/v1/me", label="DELETE /v1/me", headers=h)


async def run(url: str, players: int, seconds: float, think: float = 0.5, transport=None) -> Results:
    results = Results()
    until = time.perf_counter() + seconds
    async with httpx.AsyncClient(base_url=url, timeout=30, transport=transport) as client:
        await asyncio.gather(*(player(client, results, until, think) for _ in range(players)))
    return results


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--url", default="http://localhost:8000")
    ap.add_argument("--players", type=int, default=20)
    ap.add_argument("--seconds", type=float, default=30)
    ap.add_argument("--think", type=float, default=0.5, help="average pause between taps, in seconds")
    ap.add_argument("--i-own-this", action="store_true", help="allow a server that isn't localhost")
    a = ap.parse_args()
    host = urlparse(a.url).hostname or ""
    if host not in {"localhost", "127.0.0.1", "::1"} and not a.i_own_this:
        print("Only run load tests on servers you own. Add --i-own-this if this is yours.", file=sys.stderr)
        return 2
    start = time.perf_counter()
    results = asyncio.run(run(a.url, a.players, a.seconds, a.think))
    print(results.report(time.perf_counter() - start))
    return 0


if __name__ == "__main__":
    sys.exit(main())
