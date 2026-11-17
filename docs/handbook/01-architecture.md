# 01 · Architecture

## The picture

```
                       ┌─────────────────────────── Render (Frankfurt) ───────────────────────────┐
  Tracka app           │                                                                          │
     │ upload clip     │   ┌──────────────┐  insert job   ┌──────────────────────────────┐        │
     ▼                 │   │   Pep API    │──────────────►│ Postgres                     │        │
  tracka-api ──POST────┼──►│  (FastAPI)   │               │  jobs: QUEUED/RUNNING/READY  │◄──┐    │
  /analyses  Bearer    │   │  + Pep Lab   │◄──read────────│  ratings (scout labels)      │   │    │
     ▲                 │   └──────┬───────┘               └──────────────────────────────┘   │    │
     │                 │          │ kick (optional)                                          │    │
     │                 └──────────┼──────────────────────────────────────────────────────────┼────┘
     │                            ▼                                                          │ claim / finish
     │                 ┌──────────────────── Modal (serverless GPUs) ───────────────┐        │ (SKIP LOCKED)
     │                 │  drain():  claim → download clip → analyse → save result ──┼────────┘
     │                 └───────────┬────────────────────────────────────────────────┘
     │                             │ fetch video (presigned URL)        ┌─────────────────────┐
     │                             └───────────────────────────────────►│ Cloudflare R2       │
     │                                                                  │ clips, overlays     │
     └──── POST callbackUrl  X-Tracka-Signature: HMAC ◄── worker        └─────────────────────┘
                                                    │
                                                    └──► Gemini API (video in, coaching notes out)
```

## The parts and why each exists

### 1. A contract, not a merge
`tracka-api` already had a slot for an outside coach model: it sends
`POST {COACH_API_URL}/analyses` and expects a signed callback (see
`src/services/coach.ts` in tracka-api). Pep implements **exactly** that
contract (`pep/contracts.py`), so Tracka needs **no code change** to switch
from its built-in rules coach to Pep: set `COACH_API_URL` and the two shared
secrets.

> **Concept: loose coupling.** Two services that agree on a small, written
> contract can be built, deployed, scaled and replaced independently. The
> contract is the only thing both sides must keep stable, and a test pins it
> (`tests/test_contracts.py`).

### 2. Web tier vs worker tier
Analysing a clip takes 10 seconds to several minutes, and HTTP requests
should answer in milliseconds. So the API only **records** the job and
answers `202 Accepted`. Workers do the heavy lifting elsewhere.

Why this split is good:
- **Different resources**: the API needs little CPU and must always be up.
  Workers need GPUs and can come and go.
- **Independent scaling**: 10 clips arrive at once? Add workers. The API
  doesn't care.
- **Failure isolation**: a worker crashing on a weird video can't take the
  API down.
- **Smaller attack surface**: the internet-facing service doesn't contain
  PyTorch.

### 3. A queue in Postgres
The queue is just the `jobs` table, using `SELECT … FOR UPDATE SKIP LOCKED`
(`pep/db.py`). Each worker locks the row it takes and skips rows others have
locked, so no job is handed out twice and nobody waits.

Why not Redis, RabbitMQ or SQS? **Fewer moving parts.** We need Postgres
anyway, it's transactional (the job and its result live in the same
database), and it handles thousands of jobs an hour. Switch when you
measure a reason to, not before.

### 4. Leases and heartbeats (surviving crashes)
A claimed job gets `lease_until = now + 5 min`. The worker renews it every
~100 s (`Worker._heartbeat`). If a worker dies (out of memory, machine
pre-empted, deploy), the lease expires and another worker reclaims the job.
This is **at-least-once** processing, so finishing a job is written to be
safe to repeat.

### 5. Retries with exponential backoff and jitter
Transient errors (network blips, a GPU hiccup) are retried after
30 s, 60 s, 120 s…, plus a random 0–10 s (`db.retry_later`). The randomness
("jitter") stops a thousand failed jobs from all retrying in the same second
(a **thundering herd**). Clips that simply can't be read (`CantReadClip`) are
**not** retried: you'd pay for the same failure three times.

### 6. Idempotency
Tracka might send the same `analysisId` twice (a timeout and a retry, a
double tap). `db.enqueue` returns the existing job instead of creating a
second one. **Idempotent** = doing it twice has the same effect as doing it
once. Every API that's retried needs this.

### 7. Webhooks, signed
Results go back by `POST callbackUrl`. The body is signed:
`hex(HMAC-SHA256(secret, body))`. Tracka recomputes it, compares in constant
time, and rejects anything that doesn't match. Delivery is its own state
machine (`callback_status`: PENDING → SENT / GAVE_UP) with its own retries.
A finished analysis is never re-run just because Tracka was briefly down.

### 8. Object storage, presigned URLs
Videos live in Cloudflare R2, never on server disks (Render's disks are
wiped on every deploy). Workers and browsers fetch with **presigned URLs**:
time-limited links signed with our key, so video bytes never pass through
the API.

### 9. Configuration from the environment (12-factor)
Every setting is an environment variable read by `pep/config.py`. The same
Docker image runs on your laptop, in CI, on Render and on Modal; only the
environment differs. Secrets never live in git.

### 10. Observability built in
- **Logs** are structured JSON events with a `request_id`/`job_id`
  (`pep/log.py`).
- **Metrics** are exposed at `/metrics` in Prometheus format: request rate,
  errors and latency per route, plus queue depth and the oldest waiting job.
- **Health checks**: `/healthz` (the process is alive) and `/readyz` (it can
  reach the database). Render only sends traffic to a new deploy once
  `/readyz` passes.
- **Per-stage timings** for every analysis (`Timer.stage`), shown in the
  Lab. When things get slow, you know *which* stage got slow.

## A request's life, step by step

1. A player posts a clip in the Tracka app. tracka-api stores it and calls
   `POST /analyses` with a 6-hour video link.
2. The Pep API checks the Bearer key, validates the body (pydantic),
   inserts or reuses a job (idempotent), optionally kicks Modal, and
   answers 202.
3. A worker claims the job (SKIP LOCKED) and starts heartbeating.
4. It streams the video to a temp file and runs `pipeline.analyse`:
   frames → YOLO → camera → target → metres → Kalman → metrics → norms →
   skills → Gemini → roles.
5. It saves the result, marks `callback_status = PENDING`, and delivers the
   signed callback, retrying if needed.
6. Tracka stores the result; the Journey tab shows it. Scouts see the role
   fit.

## Alternatives we didn't choose (yet)

| Instead of | You could use | When it becomes worth it |
|---|---|---|
| Postgres queue | Redis + RQ/Celery, SQS, Pub/Sub | Tens of thousands of jobs an hour, or fan-out to many consumers |
| Modal | RunPod, AWS Batch, a fixed GPU VM | Steady 24/7 load (a reserved GPU gets cheaper above ~40–50% use) |
| One Python monolith for vision | Separate microservices per model | Several teams, or models needing very different hardware |
| `create_all` | Alembic migrations | As soon as production has data you can't lose (soon!) |
| HTTP Basic for the Lab | Real accounts (OAuth, Tracka login) | Before giving the Lab to anyone outside the core team |

---

## Workbook 01

**Exercises**

1. Run `pep serve` with `PEP_INLINE_WORKER=true`, upload a clip in the Lab,
   and watch the logs. Find the `job.start` and `job.done` events and the
   `request_id` on the upload request.
2. Run the API **without** the inline worker, upload a clip, then run
   `pep worker` in a second terminal. Then run two workers and upload three
   clips. Check the `worker` column in the `jobs` table: who did what?
3. Kill a worker with `kill -9` mid-clip. Set `PEP_JOB_LEASE_SECONDS=30`
   first. Watch another worker pick the job up after the lease expires.
4. Send the same `POST /analyses` twice with curl (same `analysisId`).
   Confirm one job exists. Read `db.enqueue` and explain the `FAILED` branch.
5. Write a tiny Flask or FastAPI "fake Tracka" that receives callbacks and
   verifies `X-Tracka-Signature`. Point a job's `callbackUrl` at it.

**Questions**

<details><summary>1. Why does the API answer 202 and not 200?</summary>

202 Accepted means "I've taken your request, but the work isn't done".
200 would suggest the result is in the response. The result comes later by
callback.
</details>

<details><summary>2. What would break if two workers could claim the same job?</summary>

The clip would be analysed twice (wasted GPU money), and two results could
race to be saved and sent. Tracka might receive two different callbacks for
one analysis. SKIP LOCKED plus the `worker == me` checks in
`finish`/`heartbeat` prevent this.
</details>

<details><summary>3. Why is processing "at least once" and not "exactly once"? What makes that OK?</summary>

A worker can finish the analysis and then die before it records "done";
the lease expires and the job runs again. Exactly-once delivery is
impossible in general across a network. It's OK because the work is
idempotent: re-running produces the same result and overwrites the same row,
and Tracka keys results by `analysisId`.
</details>

<details><summary>4. Why sign callbacks if they go over HTTPS anyway?</summary>

HTTPS hides the content in transit and proves *Tracka's* identity to us. It
doesn't prove *our* identity to Tracka: anyone can POST to Tracka's public
callback URL. The HMAC signature proves the sender knows the shared secret
and that the body wasn't changed.
</details>

<details><summary>5. Give one reason to move the queue off Postgres, and one reason not to yet.</summary>

To move: very high job rates, where polling and row locks add load to the
database that also serves the API, or the need for pub/sub fan-out. Not yet:
one less system to run, secure, monitor and pay for; transactional
consistency between jobs and results; current volume is tiny.
</details>
