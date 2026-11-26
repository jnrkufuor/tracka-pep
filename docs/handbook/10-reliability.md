# 10 · Reliability and SRE

## The idea

**SRE** (Site Reliability Engineering) is a way of running software that
Google made popular: treat keeping systems up as an *engineering*
problem, with measurements and automation, not heroics at 3 a.m.

The core insight: **100% reliability is the wrong goal.** It's
impossibly expensive, and users can't tell 99.99% from 100% (their own
phone signal fails more often). Instead, pick a target, measure it, and
spend what's left over on shipping features.

## The common approaches

### Measuring reliability: SLIs, SLOs, SLAs, error budgets
- **SLI** (indicator): a measurement of what users experience. "Share of
  upload requests that succeed." "Share of clips analysed within 5
  minutes."
- **SLO** (objective): your target for it. "99.5% of uploads succeed,
  over 30 days."
- **SLA** (agreement): a promise to customers with a penalty. Most
  startups don't need one.
- **Error budget**: 100% − SLO. At 99.5%, you may fail 0.5% of uploads a
  month. Budget left → ship features. Budget spent → slow down and fix
  reliability.

| Availability | Allowed downtime per 30 days |
|---|---|
| 99% | ~7 hours |
| 99.5% | ~3.6 hours |
| 99.9% | ~43 minutes |
| 99.99% | ~4 minutes |

### Observability: seeing inside the system
| Signal | What it is | Tools |
|---|---|---|
| **Logs** | Records of events ("job 42 finished in 31 s"). **Structured** logs (JSON fields) can be searched and counted | structlog, Winston; Grafana Loki, Better Stack, Datadog |
| **Metrics** | Numbers over time (requests per second, queue length) | Prometheus, Grafana |
| **Traces** | One request's path through every service, with timings | OpenTelemetry, Jaeger, Honeycomb |

Google's **four golden signals** to watch for any service: **latency**
(how slow), **traffic** (how much), **errors** (how many fail),
**saturation** (how full: CPU, memory, queue).

**Health checks**: `/healthz` ("is the process alive?") and `/readyz`
("can it do work: is the database reachable?"). Platforms use them to
restart or stop sending traffic to a broken copy.

### Alerts and incidents
- **Alert on symptoms users feel** (errors up, clips stuck) rather than
  causes (CPU at 80%), or you'll get woken up for nothing.
- An **incident** is when users are hurt. The routine: detect → mitigate
  (roll back first, investigate later) → resolve → write a
  **postmortem**.
- **Blameless postmortems** ask "what about the system let this happen?",
  not "who messed up?". People hide mistakes when they're blamed.
- A **runbook** lists steps for known problems so whoever is on call
  doesn't have to improvise.

### Building systems that survive failure
- **Redundancy**: more than one copy of things that can't go down.
- **Graceful degradation**: when a part fails, do less instead of
  nothing (no coach notes, but scores still work).
- **Backups you've tested restoring.** A backup you've never restored is
  a hope, not a backup.
- **Database migrations**: change the database schema with versioned
  scripts (Alembic for Python, Prisma Migrate for Node) that run the same
  way everywhere and can be reviewed.
- **Capacity planning**: estimate future load (players × clips per week ×
  GPU seconds per clip) before it arrives.
- **Toil**: repetitive manual work. SREs automate it away.

## How Tracka does it

| Practice | Where |
|---|---|
| Health checks | `/healthz` (alive), `/readyz` (database reachable) in `pep/api/app.py`; Render uses `/readyz` for deploys |
| Metrics | `/metrics` in Prometheus format: request counts and latency by route, jobs by status, age of the oldest queued job (`pep_oldest_queued_seconds`: the best "are players waiting?" signal) |
| Structured logs | `pep/log.py` (structlog): JSON lines like `job.done job_id=… seconds=31.2` |
| Job reliability | Leases + heartbeats, retries with backoff + jitter, max attempts, idempotent enqueue (`pep/db.py`, `pep/worker.py`) |
| Graceful degradation | Gemini down → rule-written notes; GPU workers down → clips wait in the queue and run later, nothing is lost |
| Timings | Each result stores per-stage timings (`timings`): where did the 40 s go? |
| Cost guard | Modal `max_containers=4` caps GPU spend in a traffic spike |
| Error tracking | `pep/errors.py`: Sentry or GlitchTip when `PEP_SENTRY_DSN` is set, with personal details stripped before anything leaves |
| App crash reports | The app sends crashes to our own `POST /v1/app-errors` (`pep/players/app_errors.py`), grouped in Pep Lab › App errors |
| Backups | `scripts/backup.py`: backup, restore, check; the monthly restore drill is in `docs/RUNBOOK.md` |
| Load testing | `scripts/load_test.py`: pretend players open the app's busiest screens and report p50/p95/p99 |

Suggested first SLOs:
- **Upload availability**: 99.5% of `POST /v1/videos` succeed (30 days).
- **Analysis freshness**: 95% of clips analysed within 10 minutes of
  upload.
- **Analysis success**: 98% of readable clips end `READY`, not `FAILED`.

Not done yet (good learning projects, also in chapter 12):
- Alembic migrations (tables are created with `create_all` today, which
  can't change existing tables safely).
- Grafana dashboards and alerts on the metrics above.
- Running the restore drill every month and writing it down (the tools are
  ready: `docs/RUNBOOK.md`).

### Error tracking that respects children (pep/errors.py, pep/players/app_errors.py)

An **error tracker** collects crashes from everywhere, groups the same crash
into one *issue* (by a **fingerprint**: the message plus the top of the stack
trace), and counts how many people it hit. That turns 3,000 log lines into
"one bug, 41 players, since version 0.3".

Crash reports leave your servers, so they must not carry personal data. Tracka
strips request bodies, headers, query strings, user details and stack
variables, and replaces emails and phone numbers in messages (`scrub_text`).
The app doesn't include a crash SDK at all: it sends reports to our own API,
which applies the same scrubbing, keeps at most 20 a day per player
(a **rate limit**), and only then forwards them.

### Backups, restores and load tests (scripts/)

A **backup** is a copy you can go back to; **RPO** (recovery point objective)
is how much data you can afford to lose (a nightly backup means up to a day),
and **RTO** (recovery time objective) is how long getting back may take. The
only way to know your RTO is to time a real restore: that is the **restore
drill**. `scripts/backup.py check` proves a restore worked: row counts, the
newest row, and **orphans** (rows pointing at a player who isn't there).

A **load test** shows where the system slows down before real players find
out. Look at **percentiles**: p95 is the time 95 out of 100 calls beat.
Averages hide the slow calls people actually feel.

### Keeping children safe: guardian approval (pep/players/guardian.py)

Safety is part of reliability: a system that works but lets a stranger
approve a 14-year-old's account has failed. The guardian flow uses a few
standard ideas you'll meet everywhere:

- **Something you have.** The link code in the text (`/g/4F7K`) is short so
  it can be typed, which also makes it guessable. So it only *finds* the
  request. To act, the guardian proves they hold the phone with a one-time
  code (OTP) texted to it: 10 minutes, 5 tries, then ask again.
- **Hash secrets at rest.** Codes and page sessions are stored as keyed
  hashes (HMAC), like passwords, so a leaked database leaks no codes.
- **Rate limits.** One text a minute, so nobody can flood a guardian's phone.
- **Fail closed.** No answer in 7 days means no; a reply from another number
  is ignored; the SMS webhook needs a shared secret or it pretends not to exist.
- **The adapter pattern.** Texts go through `sms.sender()`. Today it's a
  placeholder that keeps texts in `sms_outbox`; a real provider is one class.

### Notifications without duplicates (pep/players/notifications.py)

A worker can retry a job; a schedule can run twice; two phones can open the
bell at once. Each notification has a **dedupe key** ("review:<clip id>",
"event:<id>:<date>") that's unique per player, so doing it again changes
nothing. The same trick as the upload queue's idempotency key. Quiet hours
(9 pm to 7 am, Ghana time; always on for under-18s) only hold back push
messages; the bell keeps everything. Push itself is a placeholder until
Firebase Cloud Messaging is set up in the app.

### Moderation with an audit trail (pep/players/moderation.py)

Three reports hide a clip automatically, which is fast but blunt. A person
then decides in Pep Lab › Safety: keep it, take it down, or pause the player's
posting. Every decision goes into `moderation_log` with who and why: an
**audit trail**, so mistakes can be found and decisions explained to a parent.

## Words to know
SRE · SLI · SLO · SLA · error budget · availability · observability ·
logs · structured logging · metrics · traces · golden signals · latency ·
saturation · health check · alert · incident · mitigation · postmortem ·
blameless · runbook · redundancy · graceful degradation · backup ·
migration · capacity planning · toil

## Workbook 10

**Try it**
1. Run `pep serve`, click around the app, then open
   `localhost:8000/metrics`. Find the request counter for `/v1/videos`.
2. Stop the database (or point `PEP_DATABASE_URL` at nothing) and call
   `/healthz` and `/readyz`. Why do they answer differently?
3. Write the SLOs above as Prometheus queries (hint:
   `rate(pep_http_requests_total{status=~"5.."}[30d])`).
4. Pretend Gemini's API key expired on Friday night. Write a one-page
   postmortem: timeline, impact, root cause, what you'll change.
5. Add Alembic: `alembic init migrations`, generate a first migration
   from `pep/db.py` and `pep/players/store.py`'s tables.
6. Sign up as a 15-year-old, add a guardian number, then read the text in
   the `sms_outbox` table. Open `/g/<code>` in a browser and approve. Then
   try 6 wrong codes: what does the page say, and which constant decides?
7. Run `notifications.sweep(uid)` twice in a Python shell and count the rows
   in `notifications`. Then change a dedupe key to include the time and run
   it twice again. What goes wrong, and why does the key matter?
8. Sign up as a 15-year-old whose guardian approves, then try Settings ›
   Your data › Delete my account. Follow the request to the guardian page
   and say yes. Why does `delete_account` read the guardian's number
   *before* deleting (look at `_delete_by_guardian`)?
9. Report a clip from three accounts, then open Pep Lab › Safety and keep it.
   Read `/lab/moderation/log`. What would you add to the log so a parent's
   complaint could be answered a month later?
10. Run `pep serve`, then `python scripts/load_test.py --players 20 --seconds 30`.
    Which call has the highest p95? Double the players: which numbers grow
    first, and why is sign-up slow on purpose (hint: password hashing)?
11. Do the restore drill from `docs/RUNBOOK.md` on your laptop with SQLite:
    `backup`, `restore --into sqlite:////tmp/drill.db`, `check`. Then delete
    a user row from the restored copy with `sqlite3` and run `check` again.
    What does it report, and why does that matter after a real restore?
12. Send `POST /v1/app-errors` with a message containing an email address,
    then open Pep Lab › App errors. What was saved? Send the same error 25
    times: how many are kept, and which constant decides?

**Questions**

**1. Your SLO is 99.5% and you've used the whole error budget by day 20.
What happens?**

*Answer:* Freeze risky releases and spend the time on reliability fixes
until the budget recovers. That's the deal the error budget makes.

**2. Why alert on "clips older than 10 minutes in the queue" rather than
"GPU at 90%"?**

*Answer:* The first is something players feel. A busy GPU is fine as long
as clips finish on time; alerting on it would wake people for nothing.

**3. What's the difference between `/healthz` and `/readyz`?**

*Answer:* `/healthz` says the process is running; `/readyz` says it can
actually serve (its dependencies, like the database, work). A platform
restarts a failing `/healthz` and stops routing traffic to a failing
`/readyz`.

**4. Why are postmortems blameless?**

*Answer:* If people are punished for mistakes, they hide them, and the
system never improves. Most incidents come from systems that made the
mistake easy.

**5. Why does the app send crashes to our API instead of straight to a crash service?**

*Answer:* Most players are children. Our API can strip personal details and
limit how much is sent before anything leaves, and the store privacy forms
stay simple because no outside SDK collects data from the phone.

**6. Your backups run every night, but you've never restored one. What do you actually know?**

*Answer:* Only that a file is being written. You don't know it's complete,
that it restores, or how long a restore takes (your RTO). The monthly drill
turns the backup from a hope into a fact.
