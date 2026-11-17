# Pep: Tracka's AI coach

Pep watches a player's clip, measures them (speed, acceleration, touches,
body shape, goalkeeping, timed drills), scores them against players their
age, fits them to scouting roles, and explains how to improve, with a
video-understanding model writing the coaching notes.

It plugs into **tracka-api** through the outside-coach contract that's
already there: set `COACH_API_URL` to Pep's URL and share `COACH_API_KEY` and
`COACH_WEBHOOK_SECRET`. No Tracka code changes.

**Learning?** Start with [`docs/handbook/00-start-here.md`](docs/handbook/00-start-here.md).
**Finding your way around?** [`docs/CODEMAP.md`](docs/CODEMAP.md).

## Quick start

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev,vision,coach,train]"
cp .env.example .env

python scripts/make_test_clip.py run.mp4          # true top speed: 25.2 km/h
pep analyse run.mp4 --positions RW --age 17 --height 1.75 --overlay seen.mp4
pep serve                                         # Pep Lab at http://localhost:8000
pytest                                            # fast tests
pytest -m slow                                    # real YOLO26 on the test clip
```

Add `GEMINI_API_KEY` to `.env` for AI coaching notes; without it Pep writes
rule-based notes.

## How it works

```
clip → frames → YOLO26 pose + ball → camera-motion removal → pick the player
     → pixels to metres → Kalman/RTS smoothing → metrics (+ drills)
     → norms by age → skills with explanations and drills → Gemini notes
     → role fit for scouts → signed callback to Tracka
```

| Part | Runs on | Notes |
|---|---|---|
| API + Pep Lab | Render (Frankfurt), `Dockerfile` | FastAPI; `/analyses` for Tracka, `/lab` for people, `/healthz` `/readyz` `/metrics` |
| Queue + results | Render Postgres | `SELECT … FOR UPDATE SKIP LOCKED`, leases, backoff |
| Workers | Modal GPUs (`deploy/modal_app.py`) or Render CPU (`Dockerfile.worker`) | scale to zero on Modal |
| Clips | Cloudflare R2 | presigned URLs, free egress |
| AI coach | Gemini 3.8 Flash | structured JSON, guarded, optional |

## The Tracka contract

```
Tracka → Pep   POST /analyses   Authorization: Bearer COACH_API_KEY
               { analysisId, videoUrl, lengthSeconds, positions, callbackUrl,
                 // optional Pep extras:
                 clipType, drill, playerHeightM, ageYears, sex, target, calibration }

Pep → Tracka   POST callbackUrl   X-Tracka-Signature: hex(HMAC-SHA256(body, COACH_WEBHOOK_SECRET))
               { analysisId, status, modelVersion, overallScore, confidence,
                 skills[{name, score, explanation, drill}], moments[{atSeconds, kind, text}],
                 // extras Tracka can adopt later:
                 roleFit[], metrics{}, summary, clipType, coachSource }
```

## Deploying
1. **Render**: New → Blueprint → this repo (`render.yaml`). Fill in the
   secrets it asks for.
2. **Cloudflare R2**: create bucket `pep-clips` and an API token; set the
   `PEP_S3_*` variables.
3. **Modal** (GPU workers): `modal secret create pep-secrets …`, then
   `modal deploy deploy/modal_app.py`.
4. **tracka-api**: set `COACH_API_URL=https://<pep>`,
   `COACH_API_KEY` and `COACH_WEBHOOK_SECRET` (same values as Pep).
5. **GitHub**: add the Actions secrets and branch protection
   ([handbook 02](docs/handbook/02-cicd.md)).

## Honest limits (v0.1)
- Norms are starter priors, not Ghanaian data yet. Replace them with
  `training/build_norms.py` when you have enough players.
- Clip speeds use a body-height ruler (±10–15%). Drills with marked cones
  are the fair, comparable measure.
- No event recognition yet (passes, shots, tackles): the AI coach's
  observations stand in, labelled LOW confidence.
- Ultralytics YOLO is AGPL-3.0: read [handbook 04](docs/handbook/04-models.md#licences-important-for-a-business)
  before a commercial launch.
