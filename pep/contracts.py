"""
The contract between Tracka and Pep, as typed Python objects.

Tracka (tracka-api, src/services/coach.ts) already defines how it talks to
an outside coach model:

  1. Tracka -> Pep:   POST /analyses  {analysisId, videoUrl, lengthSeconds, positions, callbackUrl}
                      Authorization: Bearer COACH_API_KEY
  2. Pep -> Tracka:   POST callbackUrl  (a CoachResult as JSON)
                      X-Tracka-Signature: hex HMAC-SHA256(raw body, COACH_WEBHOOK_SECRET)

Pep is that outside model. These pydantic models mirror Tracka's zod schema
(`coachResultSchema`) field for field, with the same limits, so anything
Pep sends is something Tracka accepts. If you change one side, change the
other: the test tests/test_contracts.py pins the shape.

Pep adds optional fields Tracka doesn't read yet (clipType, drill, roleFit,
metrics...). Zod drops unknown keys, so adding them is safe; Tracka can
start using them whenever it's ready.

Field names are camelCase on the wire (JSON) but snake_case in Python:
`alias_generator=to_camel` does the translation.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel

Confidence = Literal["LOW", "MEDIUM", "HIGH"]
ClipType = Literal["match", "training", "drill", "highlight"]

# Tracka's position codes (tracka-api/src/schemas/onboardingSchema.ts).
POSITIONS = ("GK", "CB", "LB", "RB", "LWB", "RWB", "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "CF", "ST")


class Wire(BaseModel):
    """Base for everything sent as JSON: camelCase outside, snake_case inside."""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="ignore")

    def to_wire(self) -> dict:
        return self.model_dump(by_alias=True, exclude_none=True, mode="json")


class Point(Wire):
    """A point in a frame, as a share of width/height (0..1), so it survives resizing."""

    x: float = Field(ge=0, le=1)
    y: float = Field(ge=0, le=1)


class Calibration(Wire):
    """
    Tells Pep how pixels relate to metres on the ground.

    For drills: four or more ground points the player marked on a frame (cones),
    and where those points really are in metres. Pep fits a homography from
    one to the other (pep/vision/calibration.py).
    """

    at_seconds: float = 0.0
    image_points: list[Point] = Field(min_length=4)
    world_points_m: list[tuple[float, float]] = Field(min_length=4)


class AnalysisRequest(Wire):
    """What Tracka sends (the first five fields), plus optional extras."""

    analysis_id: str
    video_url: str
    length_seconds: float | None = None
    positions: list[str] = Field(default_factory=list)
    callback_url: str | None = None

    # ---- Pep extras (optional; Tracka can start sending them later)
    clip_type: ClipType = "match"
    drill: str | None = None  # a drill id from pep/data/drills.json, when clip_type == "drill"
    player_height_m: float | None = Field(None, ge=1.0, le=2.3)
    age_years: int | None = Field(None, ge=6, le=60)
    sex: Literal["male", "female"] | None = None
    # Where the player is in the first frames ("this is me"). Without it Pep guesses.
    target: Point | None = None
    target_at_seconds: float = 0.0
    calibration: Calibration | None = None
    player_label: str | None = None  # a display name for the Lab; never needed by Tracka
    coach_notes: bool = True  # False: skip the AI coach (the player turned notes off)


class Skill(Wire):
    name: str = Field(max_length=40)
    score: int = Field(ge=0, le=100)
    explanation: str = Field("", max_length=600)
    drill: str = Field("", max_length=600)
    # Pep extras: where the number came from and how sure we are.
    source: Literal["measured", "drill", "ai_observed"] | None = None
    confidence: Confidence | None = None


class Moment(Wire):
    at_seconds: float = Field(ge=0)
    kind: Literal["GOOD", "WORK_ON"]
    text: str = Field(max_length=300)
    # Pep extras (tracka-api's schema ignores unknown keys): a few-word title and the
    # skill area (pep/data/skill_areas.json id) the moment is about.
    title: str | None = Field(None, max_length=60)
    area: str | None = Field(None, max_length=40)


class ReviewTip(Wire):
    """One thing to practise, tied to a moment in the clip and a skill area. Words only:
    Pep picks the drill itself, from the player's kit (pep/players/review.py)."""

    area: str = Field(max_length=40)
    title: str = Field(max_length=60)
    text: str = Field(max_length=300)
    at_seconds: float | None = Field(None, ge=0)


class RoleFit(Wire):
    role: str
    label: str
    score: int = Field(ge=0, le=100)
    coverage: float = Field(ge=0, le=1)  # share of the role's weight we could actually measure


class CoachResult(Wire):
    """What Pep sends back. Mirrors tracka-api coachResultSchema."""

    analysis_id: str
    status: Literal["READY", "FAILED"]
    model_version: str | None = Field(None, max_length=60)
    overall_score: int | None = Field(None, ge=0, le=100)
    confidence: Confidence | None = None
    skills: list[Skill] = Field(default_factory=list, max_length=12)
    moments: list[Moment] = Field(default_factory=list, max_length=30)
    error: str | None = Field(None, max_length=500)

    # ---- Pep extras
    clip_type: ClipType | None = None
    role_fit: list[RoleFit] = Field(default_factory=list)
    metrics: dict[str, float | None] = Field(default_factory=dict)
    summary: str | None = Field(None, max_length=600)
    headline: str | None = Field(None, max_length=60)
    tips: list[ReviewTip] = Field(default_factory=list, max_length=6)
    coach_source: Literal["gemini", "rules"] | None = None

    @classmethod
    def failed(cls, analysis_id: str, message: str, version: str | None = None) -> CoachResult:
        return cls(analysis_id=analysis_id, status="FAILED", error=message[:500], model_version=version)
