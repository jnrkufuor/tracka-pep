# 02 · Designing a system

## The idea

**System design** is deciding how to split a product into parts, how
those parts talk, where data lives, and what happens when something
breaks. Think of a restaurant again. A small café can have one person
doing everything. A busy restaurant splits the work: waiters take orders
fast, cooks do the slow work, and order tickets sit on a rail in between
so nothing gets lost when the kitchen is busy. Software works the same
way.

## The common approaches

### One big program, or many small ones?

| Approach | What it is | Good | Bad |
|---|---|---|---|
| **Monolith** | One program does everything | Simple to build, test and deploy; best for small teams | Hard to scale one part separately; one bug can take everything down |
| **Microservices** | Many small programs, each owning one job, talking over the network | Teams and parts scale independently | Much more to run, monitor and debug; network calls fail |
| **Modular monolith** | One program, carefully split into modules with clear boundaries | Most of the simplicity, ready to split later | Needs discipline to keep the modules separate |

Most successful products start as a (modular) monolith and split pieces
out only when there's a measured reason.

### Fast work vs slow work: synchronous vs asynchronous
- **Synchronous**: you ask and wait for the answer (the waiter waits at
  the counter). Fine when the answer takes milliseconds.
- **Asynchronous**: you hand the work over and get the answer later (the
  order ticket on the rail). Needed when work takes seconds or minutes.

The usual tool for asynchronous work is a **job queue**: the web server
writes a job down and answers immediately; separate **workers** pick
jobs up and do them.

| Queue technology | Notes |
|---|---|
| A database table (Postgres `SKIP LOCKED`) | No extra system to run; fine up to thousands of jobs an hour |
| Redis (with RQ, Celery, Sidekiq) | Very fast; another system to run |
| RabbitMQ, Kafka | Powerful messaging; heavier to operate |
| Cloud queues (AWS SQS, Google Pub/Sub) | Fully managed; ties you to that cloud |

### Things go wrong: design for failure
Networks drop, servers restart, phones lose signal. Good systems assume
it:
- **Retries with exponential backoff**: if something fails, try again
  after 30 s, then 60 s, then 120 s… The waits grow so you don't hammer a
  struggling service. Add **jitter** (a random extra wait) so a thousand
  clients don't all retry at the same second.
- **Idempotency**: doing something twice has the same effect as doing it
  once. If a phone retries an upload because the answer got lost, you
  must not create two copies.
- **Timeouts**: never wait forever.
- **Leases and heartbeats**: a worker "borrows" a job for a while and
  keeps renewing the loan while it works. If the worker crashes, the loan
  runs out and someone else picks the job up.

### Where data lives

| Kind of storage | Holds | Examples |
|---|---|---|
| **Relational database** | Structured records with relationships (users, profiles, videos, scores) | Postgres, MySQL, SQLite |
| **Object storage** | Big files (videos, images), addressed by name | Cloudflare R2, AWS S3, Google Cloud Storage |
| **Cache** | Copies of hot data for speed | Redis |
| **Local disk** | Temporary files only (it's wiped on most platforms) | |

Rule of thumb: records in the database, files in object storage, and a
pointer from one to the other.

### Configuration: the "12-factor" rules
A well-known checklist for apps that run in the cloud. The parts that
matter most: keep **settings in environment variables** (not in the
code), keep **secrets out of git**, and make the program **stateless**:
any copy of it can serve any request because nothing important is kept
in memory or on local disk.

## How Tracka does it

```
 App ──HTTP──► Pep API (FastAPI) ──writes job──► Postgres "jobs" table ◄──claims── Pep workers (GPU)
                  │                                    ▲                              │
                  └──stores clip──► Cloudflare R2 ◄────┼──────── downloads clip ──────┘
                                                       └──────── saves result ────────┘
```

- **A modular monolith**: one Python package, `pep/`, with clear modules:
  `players/` (accounts and videos), `vision/` and `metrics/` (analysis),
  `scoring/`, `coach/`, `api/`. One codebase, two ways to run it: as the
  API (`pep serve`) or as a worker (`pep worker`).
- **Web tier vs worker tier**: analysing a clip takes 10 seconds to a few
  minutes, so the API stores the clip, writes a job, and answers `202` in
  a fraction of a second. Workers (on GPUs) do the slow part. The two scale
  separately: busy evening, more workers; the API doesn't change.
- **The queue is a Postgres table** (`pep/db.py`). Workers claim jobs with
  `SELECT … FOR UPDATE SKIP LOCKED`: each worker locks the row it takes and
  skips rows others hold, so no clip is analysed twice.
- **Leases**: a claimed job is leased for 5 minutes and the worker renews
  the lease while it works (`Worker._heartbeat`). Crash, and another
  worker takes over.
- **Retries**: temporary errors retry with backoff and jitter
  (`db.retry_later`). A clip that simply can't be read ("too short") is
  *not* retried; that would waste money.
- **Idempotency**: sending the same analysis twice returns the existing
  job (`db.enqueue`).
- **Data**: accounts, profiles, videos and results in Postgres; video
  files and thumbnails in R2; each `videos` row points at its file and its
  analysis job (`pep/players/store.py`).
- **Built to grow**: scouts and opportunities will be *new* tables that
  point at `users`, not changes to existing ones. The `role` column on
  `users` is already there for that, and the `/v1/opportunities` route
  already exists (empty for now).
- **Settings** all come from environment variables (`pep/config.py`).
- **Derived state: the training week** (`pep/players/training.py`). The
  database keeps only facts the player gave (their team training and
  matches, sessions they moved, skipped or finished, how their body feels).
  The week with Pep's sessions in it is *computed* from those facts on every
  request (`GET /v1/week`), so it can never go stale, and changing a rule
  ("no Pep session the day before a match") changes every player's plan at
  once. New tables (`events`, `session_changes`, `training_log`, `health`)
  all point at `users`.

## Words to know
monolith · microservices · modular monolith · synchronous · asynchronous ·
job queue · worker · retry · exponential backoff · jitter · idempotency ·
timeout · lease · heartbeat · relational database · object storage ·
cache · stateless · 12-factor · derived state · source of truth

## Workbook 02

**Try it**
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

**Questions**

**1. Why not analyse the clip inside the upload request?**

*Answer:* It takes too long: the phone would wait minutes, connections
would time out, and a slow job would block the API for everyone. Queuing
it lets the API answer at once and the workers scale separately.

**2. What does idempotency protect against in an upload?**

*Answer:* Retries. If the answer to a request gets lost, the client
retries. Without idempotency, each retry would create a duplicate.

**3. Why put video files in R2 instead of in the database?**

*Answer:* Databases are built for many small structured records, not huge
files; storing videos there makes backups slow and the database
expensive. Object storage is cheap per gigabyte and serves big files
efficiently.

**4. Why add random jitter to retries?**

*Answer:* Without it, every client that failed at the same moment retries
at the same moment, hitting the recovering service with a spike (a
"thundering herd") that can knock it down again.

**5. Why does Tracka compute the week on every request instead of saving
the plan in a table?**

*Answer:* A saved plan is a copy that can drift from its inputs: add a
match on Saturday and a stored plan would still have a hard session on
Friday until something rebuilt it. Computing it from the facts (events,
moves, skips, health) means there's one source of truth and the plan is
always right. The cost is a little work per request, which is cheap here.
