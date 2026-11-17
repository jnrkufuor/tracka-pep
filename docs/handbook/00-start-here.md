# Pep handbook: start here

Pep is Tracka's AI coach. A player uploads a clip. Pep finds them, measures
how they move and play, scores them against players their age, and explains
what to work on. The scores also feed a role-based database that scouts can
search.

This handbook has two jobs:

1. **Explain the system**: why it's built this way, and what every part does.
2. **Teach you to rebuild it**: every chapter ends with a **workbook** of
   exercises (things to *do* in the code) and questions (with answers
   folded away). The workbooks focus on AI, SRE and cloud.

## The 30-second version

```
 Tracka app ──► tracka-api ──POST /analyses──► Pep API ──► Postgres queue ◄── Pep workers (GPU)
                     ▲                                                           │
                     └────────── signed callback with scores ◄────────────────── ┘
                                                                  YOLO26 → tracking → metres →
                                                                  Kalman → metrics → norms →
                                                                  skills → Gemini notes → roles
```

- **Pep API** (FastAPI, on Render): accepts jobs, serves the Pep Lab web UI,
  and reports health.
- **Pep workers** (on Modal GPUs, or a Render CPU worker): do the heavy
  analysis.
- **Postgres**: holds the job queue, the results and scouts' ratings.
- **Cloudflare R2**: stores the video files.

## Reading order

| # | Chapter | You'll learn |
|---|---|---|
| 01 | [Architecture](01-architecture.md) | Web tier vs worker tier, queues, leases, idempotency, webhooks, 12-factor |
| 02 | [CI/CD](02-cicd.md) | GitHub Actions, test matrices, Docker, deploy hooks, smoke tests, branch protection |
| 03 | [Platforms](03-platforms.md) | What Render, Cloudflare, Modal, GitHub, Docker and Gemini are for, and their gotchas |
| 04 | [The models](04-models.md) | YOLO26, pose, ByteTrack, optical flow + RANSAC, homography, pinhole, Kalman + RTS, gradient boosting, Gemini |
| 05 | [Features and predictors](05-features.md) | Every measurement: definition, units, thresholds, pitfalls |
| 06 | [Scoring](06-scoring.md) | z-scores, percentiles, confidence, role fit, the learned scorer |
| 07 | [Python toolbox](07-python.md) | Generators, Protocols, dataclasses, context managers, caching, NumPy tricks |
| 08 | [Cost](08-cost.md) | What a clip costs and how to change that |
| 09 | [Making Pep better](09-improving.md) | The accuracy roadmap, data strategy, MLOps, privacy |
| 10 | [Runbook](10-runbook.md) | SLOs, alerts, what to do when things break |

Also see [`../CODEMAP.md`](../CODEMAP.md) (where everything is) and
[`../DESIGN.md`](../DESIGN.md) (the Lab's visual design).

## Run it in five minutes

```bash
git clone https://github.com/jnrkufuor/tracka-pep && cd tracka-pep
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev,vision,coach,train]"
cp .env.example .env                       # PEP_INLINE_WORKER=true is already set
python scripts/make_test_clip.py run.mp4   # a clip where the true top speed is 25.2 km/h
pep analyse run.mp4 --positions RW --age 17 --height 1.75 --overlay seen.mp4
pep serve                                  # then open http://localhost:8000
pytest                                     # the fast tests (about 2 seconds)
```

## How to use the workbooks

- **Do** the exercises in a branch (`git switch -c workbook-01`). Breaking
  things on purpose is how you learn what the tests protect.
- **Answer** the questions out loud or in writing before you open the
  answer.
- **Reproduce at a high level**: after each chapter, try to sketch that part
  of the system on paper from memory. If you can draw it and say why, you
  own it.
