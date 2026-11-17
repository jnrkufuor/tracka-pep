"""
Picking the player the clip is about, and following them through the clip.

A match clip has 5-20 people in it. Pep scores one: the player who posted
it. Two ways to find them:

  1. The player tells us (`target` point: "this is me", tapped on a frame).
     We take the track whose box contains that point. Always prefer this.
  2. Otherwise we guess, scoring each track by:
       - how much of the clip it's on screen (the camera follows the subject),
       - how big it is (the subject is usually closest to the camera),
       - how often it's near the ball.

Then "stitching". Trackers lose people: a player runs behind a defender, the
tracker drops their ID and gives them a new one when they reappear. If the
target's track ends and a new track starts soon after, near where the target
should be and about the same size, we treat it as the same player. That
keeps a 30-second clip from turning into five unconnected 6-second ones.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

import numpy as np

from .types import Box, FrameObs, Person, apply_affine


@dataclass
class TargetSample:
    """The chosen player (and the ball) at one moment, in reference coordinates."""

    t: float
    feet: tuple[float, float] | None  # bottom-middle of their box, camera motion removed
    box_h: float | None  # their box height in reference pixels: our ruler
    box: Box | None  # in frame pixels (for drawing)
    keypoints: np.ndarray | None  # (17, 3) in frame pixels
    ball: tuple[float, float] | None  # ball centre, reference coordinates
    ball_frame: tuple[float, float] | None  # ball centre, frame pixels
    zoom: float  # how much the camera has zoomed since frame 0


def choose_target(
    obs: list[FrameObs], hint: tuple[float, float] | None = None, hint_t: float = 0.0
) -> list[int]:
    """Returns the chain of track IDs that make up the target player (after stitching)."""
    by_track: dict[int, list[tuple[FrameObs, Person]]] = defaultdict(list)
    for o in obs:
        for p in o.people:
            if p.track_id >= 0:
                by_track[p.track_id].append((o, p))
    if not by_track:
        return []

    first: int | None = None
    if hint is not None:
        first = _track_at_hint(obs, hint, hint_t)
    if first is None:
        first = _most_likely_subject(obs, by_track)
    return _stitch(first, by_track)


def _track_at_hint(obs: list[FrameObs], hint: tuple[float, float], hint_t: float) -> int | None:
    # Look at the frames around the hint time, nearest first.
    for o in sorted(obs, key=lambda o: abs(o.t - hint_t))[:15]:
        px, py = hint[0] * o.width, hint[1] * o.height
        inside = [p for p in o.people if p.track_id >= 0 and p.box.contains(px, py, pad=0.1 * p.box.h)]
        if inside:
            return min(inside, key=lambda p: _dist(p.box.center, (px, py))).track_id
    return None


def _most_likely_subject(obs: list[FrameObs], by_track: dict[int, list[tuple[FrameObs, Person]]]) -> int:
    n = len(obs)
    best_id, best_score = -1, -1.0
    for tid, seen in by_track.items():
        presence = len(seen) / n
        size = float(np.median([p.box.h / o.height for o, p in seen]))
        near_ball = np.mean(
            [o.ball is not None and _dist(p.box.feet, o.ball.center) < 1.2 * p.box.h for o, p in seen]
        )
        score = presence * size * (1.0 + float(near_ball))
        if score > best_score:
            best_id, best_score = tid, score
    return best_id


def _stitch(
    first: int, by_track: dict[int, list[tuple[FrameObs, Person]]], max_gap_s: float = 1.5
) -> list[int]:
    chain = [first]
    used = {first}
    while True:
        last_obs, last_p = by_track[chain[-1]][-1]
        lx, ly = apply_affine(last_obs.to_ref, *last_p.box.feet)
        candidates = []
        for tid, seen in by_track.items():
            if tid in used:
                continue
            o, p = seen[0]
            gap = o.t - last_obs.t
            if not (0 < gap <= max_gap_s):
                continue
            x, y = apply_affine(o.to_ref, *p.box.feet)
            # A sprinting player covers ~8 m/s; allow roughly that many body heights per second.
            reach = last_p.box.h * (1.0 + 4.5 * gap)
            similar_size = 0.6 < p.box.h / max(last_p.box.h, 1) < 1.6
            if _dist((x, y), (lx, ly)) < reach and similar_size:
                candidates.append((_dist((x, y), (lx, ly)), tid))
        if not candidates:
            return chain
        nxt = min(candidates)[1]
        chain.append(nxt)
        used.add(nxt)


def follow(obs: list[FrameObs], chain: list[int]) -> list[TargetSample]:
    """One TargetSample per frame for the chosen player (fields None where they weren't seen)."""
    wanted = set(chain)
    out: list[TargetSample] = []
    for o in obs:
        person = next((p for p in o.people if p.track_id in wanted), None)
        zoom = float(np.sqrt(abs(np.linalg.det(o.to_ref[:, :2]))))
        ball_ref = apply_affine(o.to_ref, *o.ball.center) if o.ball else None
        if person is None:
            out.append(
                TargetSample(o.t, None, None, None, None, ball_ref, o.ball.center if o.ball else None, zoom)
            )
            continue
        feet = apply_affine(o.to_ref, *person.box.feet)
        out.append(
            TargetSample(
                t=o.t,
                feet=feet,
                box_h=person.box.h * zoom,  # height expressed in reference pixels
                box=person.box,
                keypoints=person.keypoints,
                ball=ball_ref,
                ball_frame=o.ball.center if o.ball else None,
                zoom=zoom,
            )
        )
    return out


def _dist(a: tuple[float, float], b: tuple[float, float]) -> float:
    return float(np.hypot(a[0] - b[0], a[1] - b[1]))
