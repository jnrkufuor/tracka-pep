# 02 · Designing the system

Tracka is one codebase run as two kinds of process: a fast web tier that answers the app, and a slow worker tier that analyses clips. A queue sits between them, so each part can fail or grow without dragging the other down.

## The idea

**System design** is deciding how to split a product into parts, how those parts talk, where data lives, and what happens when something breaks.

Think of a busy restaurant. Waiters take orders fast; cooks do the slow work; order tickets sit on a rail in between. A waiter doesn't stand in the kitchen waiting for a stew. If one cook is off sick, the tickets wait on the rail and nothing is lost. That's the whole chapter in one picture.

The principle behind it is **loose coupling**: each part knows as little as possible about the others. It only knows the agreed way to talk to them (an API, a table, a message format). Loosely coupled parts can be changed, replaced, scaled or restarted on their own. **Tightly coupled** parts break together.

## The usual ways to do it

**One big program or many small ones?**

| Approach | What it is | Good | Bad |
| --- | --- | --- | --- |
| **Monolith** | One program does everything | Simple to build, test and deploy | One part can't grow alone; one bug can take everything down |
| **Microservices** | Many small programs, each with one job, talking over the network | Teams and parts grow on their own | Much more to run, watch and debug; network calls fail |
| **Modular monolith** | One program, split inside into modules with clear boundaries | Most of the simplicity, easy to split later | Needs discipline to keep modules apart |

Most successful products start as a modular monolith and split a piece out only when there's a measured reason.

**Fast work and slow work.** Some work answers in milliseconds ("show my profile"). Some takes minutes ("analyse this clip"). If both happen in the same request, the phone waits, the connection times out, and one slow job blocks everyone. The usual answer is a **job queue**: the web server writes the job down and answers straight away; separate **workers** pick jobs up and do them. This is **asynchronous** work.

| Where to keep the queue | Notes |
| --- | --- |
| A database table (Postgres `SKIP LOCKED`) | Nothing extra to run; fine up to thousands of jobs an hour |
| Redis (with Celery, RQ, Sidekiq) | Very fast; one more system to run |
| RabbitMQ, Kafka | Powerful messaging; heavy to operate |
| Cloud queues (AWS SQS, Google Pub/Sub) | Fully managed; ties you to that cloud |

**Designing for failure.** Networks drop, servers restart, phones lose signal. Good systems expect it:

- **Retries with exponential backoff**: wait 30 s, then 60 s, then 120 s, so you don't hammer a struggling service. Add **jitter** (a random extra wait) so a thousand clients don't retry in the same second.
- **Idempotency**: doing something twice has the same effect as doing it once. A phone that retries an upload must not create two clips.
- **Timeouts**: never wait forever.
- **Leases and heartbeats**: a worker borrows a job for a few minutes and keeps renewing the loan while it works. If it crashes, the loan runs out and another worker takes the job.

**Where data lives.** Records (users, profiles, scores) go in a **relational database**. Big files (videos) go in **object storage**. The database row points at the file. Settings go in **environment variables**, never in the code, and secrets never go in git.

## What we chose and why

- **A modular monolith.** One Python package, `pep/`, with clear modules: `players/` (accounts and clips), `vision/` and `metrics/` (analysis), `scoring/`, `coach/`, `api/`. We're a small team; microservices would add running costs without a measured need.
- **Two tiers from one codebase.** The same code runs as the API (`pep serve`) or as a worker (`pep worker`). The **web tier** stores the clip, writes a job and answers `202 Accepted` in a fraction of a second. The **worker tier** does the slow analysis on machines with GPUs (chapter 03 explains why GPUs). The two grow separately: a busy evening needs more workers, not a bigger API.
- **The queue is a Postgres table.** We already run Postgres, so the queue costs nothing extra and lives next to the data it describes. Workers claim jobs with `SELECT … FOR UPDATE SKIP LOCKED`: each worker locks the row it takes and skips rows others hold, so no clip is analysed twice. If we ever outgrow it, Redis is the next step.
- **Loose coupling at every seam.** The app knows only the `/v1` API. The API and workers only share the jobs table. The scoring code knows nothing about where a clip came from: the player app and the service API (chapter 01) send jobs in the same format. Any part can be swapped (a new GPU provider, a different AI model) without touching the others.
- **Built to grow.** Scouts will arrive as *new* tables that point at `users`, not as changes to existing ones. That keeps today's code and data untouched when they do.
- **Some state is computed, not stored.** A player's training week is worked out from the facts they gave (matches, sessions done, how they feel) on every request. A stored plan could drift out of date; a computed one can't. This is called **derived state**.

## How it's set up

- Queue, leases, retries and idempotent enqueue: `pep/db.py`.
- The worker loop, with its heartbeat: `pep/worker.py`.
- Players, clips and the pointer to each file and job: `pep/players/store.py`.
- The training week (derived state): `pep/players/training.py`.
- Every setting, read from environment variables: `pep/config.py`.

## Words to know

loose coupling · tight coupling · monolith · microservices · modular monolith · web tier · worker tier · synchronous · asynchronous · job queue · worker · retry · exponential backoff · jitter · idempotency · timeout · lease · heartbeat · relational database · object storage · stateless · derived state

## Workbook 02

**Try it**

1. Run the API without the inline worker, upload a clip, then start `pep worker` in another terminal and watch it pick the job up. Start two workers and upload three clips: which worker took which?
2. Set `PEP_JOB_LEASE_SECONDS=30`, start a clip, and kill the worker with `kill -9`. Watch another worker take over when the lease runs out.
3. Draw the system from memory: app, API, database, queue, workers, file storage. Label each arrow with what flows along it.
4. Sketch where the scout app would plug in. Which tables would you add, and which parts would you reuse unchanged?
5. Add a Saturday match (`POST /v1/events`) and fetch `GET /v1/week`. Why is Friday never a hard Pep session? Find the rule in `place_sessions`.

**Questions**

**1. Why not analyse the clip inside the upload request?**

*Answer:* It takes too long. The phone would wait minutes, connections would time out, and one slow job would block the API for everyone. Queuing lets the API answer at once and the workers grow on their own.

**2. What does loose coupling buy us, concretely?**

*Answer:* We can change one part without touching the others: move workers to another GPU provider, swap the AI model, or add a scout app, while the player app keeps working unchanged.

**3. Why keep the queue in Postgres instead of Redis?**

*Answer:* We already run Postgres, and at our size it's fast enough. One fewer system to run, back up and monitor.

**4. Why add random jitter to retries?**

*Answer:* Without it, every client that failed at the same moment retries at the same moment, hitting the recovering service with a spike that can knock it down again.

**5. Why compute the training week instead of saving it?**

*Answer:* A saved plan is a copy that can drift: add a Saturday match and a stored plan would still have a hard Friday session. Computing it from the facts keeps one source of truth.

## More practice

Exercises added as features were built. Each one points at real code.

1. Run the API without the inline worker, upload a clip in the app,
   then start `pep worker` in another terminal and watch it pick the job
   up. Start two workers and upload three clips: which worker did which?
2. Set `PEP_JOB_LEASE_SECONDS=30`, start a clip, and kill the worker with
   `kill -9`. Watch another worker take over after the lease runs out.
3. Draw Tracka's design from memory: boxes for app, API, database, queue,
   workers and storage, with arrows labelled with what flows along them.
4. Sketch where a future **scout** app would plug in. Which tables would
   you add? Which existing parts would it reuse?
5. With `pep serve` running, add a Saturday match (`POST /v1/events`) and
   fetch `GET /v1/week`. Which days did Pep pick for its sessions, and why
   is Friday never one of them? Find the rule in `place_sessions`.
