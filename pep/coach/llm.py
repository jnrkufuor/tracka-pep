"""
The AI coach: a video-understanding language model that watches the clip.

Pep's measurements answer "how fast, how often, how close". They can't
answer "was that the right pass?" or "did they check their shoulder before
receiving?". A large multimodal model (Gemini, which accepts video) can give
a decent first opinion on those, in plain words, with timestamps.

The golden rule here: THE MODEL WRITES WORDS, PEP OWNS THE NUMBERS.
  - We give the model our measurements and tell it not to invent others.
  - Skills it rates by eye are marked `source: "ai_observed"`, confidence
    LOW, and count half in role fit (scoring/roles.py).
  - Its timestamps are clamped to the clip, its text is length-limited, and
    if the call fails or times out we fall back to rule-written text
    (coach/rules.py). The coach being down never fails an analysis.

STRUCTURED OUTPUT: instead of parsing free text, we hand the API a schema
(the pydantic model `CoachNotes`) and it returns JSON that matches it. That
turns "an LLM said something" into typed data you can validate and test.

Cost (introductory Gemini 3.8 Flash pricing, check before relying on it):
video is billed as tokens, roughly a few hundred per second of video, so a
30 s clip with the prompt is in the order of 10-20k input tokens: about one
or two US cents per clip. See docs/handbook/08-cost.md.
"""

from __future__ import annotations

import contextlib
import json
import time
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field

from ..config import settings
from ..log import get_logger

log = get_logger(__name__)

OBSERVABLE = ("Passing", "Finishing", "Defending", "Decision making", "First touch")


class NoteMoment(BaseModel):
    at_seconds: float
    kind: Literal["GOOD", "WORK_ON"]
    text: str = Field(description="One sentence, under 25 words, addressed to the player as 'you'.")


class Observed(BaseModel):
    skill: Literal["Passing", "Finishing", "Defending", "Decision making", "First touch"]
    rating: int = Field(ge=1, le=5, description="1 poor, 3 typical for the age, 5 excellent")
    evidence: str = Field(description="What you saw that justifies the rating, one or two sentences.")


class Tip(BaseModel):
    skill: str
    tip: str = Field(description="One concrete thing to practise, under 35 words.")


class CoachNotes(BaseModel):
    summary: str = Field(description="Two sentences: the clearest strength and the one thing to work on.")
    moments: list[NoteMoment] = Field(default_factory=list)
    observed: list[Observed] = Field(default_factory=list)
    tips: list[Tip] = Field(default_factory=list)


SYSTEM = """You are Pep, a youth football coach reviewing a player's video for the Tracka app.
Players are mostly 12-23 and many play in Ghana on all kinds of pitches; be encouraging, direct and specific.

Rules:
- Only talk about the ONE player described in the request. If you can't find them, say so in the summary.
- Measurements in the request were computed by Pep's tracking. Never contradict them and never invent other numbers (no speeds, distances or percentages of your own).
- Every moment needs a real timestamp in seconds within the clip.
- Rate an 'observed' skill only if the clip clearly shows it at least twice. Leave it out otherwise.
- Write to the player as 'you'. Plain English, short sentences, no jargon a 14-year-old wouldn't know.
"""


def build_prompt(context: dict) -> str:
    return (
        "Review this clip.\n\n"
        f"Player: {context.get('who', 'the main player in the clip')}\n"
        f"Position(s): {', '.join(context.get('positions') or []) or 'unknown'}\n"
        f"Age: {context.get('age') or 'unknown'}\n"
        f"Clip type: {context.get('clip_type')}\n"
        f"Clip length: {context.get('length'):.1f} s\n\n"
        "Pep's measurements (trust these):\n"
        f"{json.dumps(context.get('metrics', {}), indent=1)}\n\n"
        "Pep's skill scores so far (0-100, 62 is typical for their age group):\n"
        f"{json.dumps(context.get('skills', {}), indent=1)}\n\n"
        "Return: a summary; 3-8 moments (good things and things to work on, roughly balanced); "
        f"observed ratings for any of {', '.join(OBSERVABLE)} the clip clearly shows; and one tip for each "
        "of the two lowest-scoring skills."
    )


def watch(video: Path, context: dict) -> CoachNotes | None:
    """Ask the video model for notes. Returns None (never raises) if it isn't configured or fails."""
    s = settings()
    if s.coach_provider != "gemini" or not s.gemini_api_key:
        return None
    try:
        from google import genai
        from google.genai import types
    except ImportError:
        log.warning("coach.sdk_missing", hint="pip install -e '.[coach]'")
        return None

    started = time.monotonic()
    client = genai.Client(api_key=s.gemini_api_key)
    uploaded = None
    try:
        uploaded = client.files.upload(file=str(video))
        # Video files are processed asynchronously; wait until they're usable.
        while _state(uploaded) == "PROCESSING":
            if time.monotonic() - started > s.coach_timeout_seconds:
                raise TimeoutError("video processing took too long")
            time.sleep(2)
            uploaded = client.files.get(name=uploaded.name)
        if _state(uploaded) == "FAILED":
            raise RuntimeError("the model couldn't process the video")

        response = client.models.generate_content(
            model=s.coach_model,
            contents=[uploaded, build_prompt(context)],
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM,
                response_mime_type="application/json",
                response_schema=CoachNotes,
                temperature=0.4,
            ),
        )
        notes = (
            response.parsed
            if isinstance(response.parsed, CoachNotes)
            else CoachNotes.model_validate_json(response.text)
        )
        log.info("coach.done", seconds=round(time.monotonic() - started, 1), moments=len(notes.moments))
        return notes
    except Exception as exc:  # the coach is optional: log and fall back to rules
        log.warning("coach.failed", error=str(exc)[:300])
        return None
    finally:
        if uploaded is not None:
            with contextlib.suppress(Exception):  # tidying up is best-effort
                client.files.delete(name=uploaded.name)


def _state(f) -> str:
    st = getattr(f, "state", None)
    return getattr(st, "name", str(st or "ACTIVE")).upper()
