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

Suggested first SLOs:
- **Upload availability**: 99.5% of `POST /v1/videos` succeed (30 days).
- **Analysis freshness**: 95% of clips analysed within 10 minutes of
  upload.
- **Analysis success**: 98% of readable clips end `READY`, not `FAILED`.

Not done yet (good learning projects, also in chapter 12):
- Alembic migrations (tables are created with `create_all` today, which
  can't change existing tables safely).
- Grafana dashboards and alerts on the metrics above.
- A tested database restore from Render's backups.
- Error tracking (Sentry) in the API and the app.

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
