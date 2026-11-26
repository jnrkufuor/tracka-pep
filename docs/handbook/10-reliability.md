# 10 · Reliability and safety

We don't aim for perfect; we aim for targets players would notice, measure them, and make every part fail gently. For a children's app, safety is part of reliability: a system that works but lets a stranger approve a 14-year-old's account has failed.

## The idea

**SRE** (Site Reliability Engineering) treats keeping software running as an engineering problem, with measurements and automation, not heroics at 3 a.m. Its core insight: **100% is the wrong goal.** It's impossibly expensive, and users can't tell 99.99% from 100% (their own phone signal fails more often). So you pick a target, measure it, and spend what's left over on new features.

- An **SLI** (indicator) measures what users feel: "share of uploads that succeed".
- An **SLO** (objective) is the target: "99.5% of uploads succeed over 30 days".
- The **error budget** is what's left: 0.5% may fail. Budget left → ship features. Budget spent → slow down and fix reliability.

| Availability | Allowed downtime per 30 days |
| --- | --- |
| 99% | about 7 hours |
| 99.5% | about 3.6 hours |
| 99.9% | about 43 minutes |
| 99.99% | about 4 minutes |

## The usual ways to do it

**Seeing inside the system (observability):**

| Signal | What it is | Common tools |
| --- | --- | --- |
| **Logs** | Records of events. **Structured** logs (fields, not sentences) can be searched and counted | structlog; Grafana Loki, Better Stack, Datadog |
| **Metrics** | Numbers over time (requests a second, queue length) | Prometheus, Grafana |
| **Traces** | One request's path through every part, with timings | OpenTelemetry, Honeycomb |
| **Error tracking** | Crashes grouped into issues, counted by how many people they hit | Sentry, GlitchTip |

Watch the **four golden signals**: latency (how slow), traffic (how much), errors (how many fail), saturation (how full). Give every service **health checks**: `/healthz` (is the process alive?) and `/readyz` (can it do work: is the database reachable?).

**When things go wrong:** alert on symptoms players feel (clips stuck), not causes (CPU at 80%). In an **incident**: detect → limit the damage (roll back first, investigate later) → fix → write a **blameless postmortem** that asks "what about the system let this happen?". Keep a **runbook** of steps for known problems.

**Surviving failure:** **graceful degradation** (do less instead of nothing), **backups you've tested restoring** (a backup never restored is a hope), **load tests** before a big day, and **percentiles** instead of averages (p95 is the time 95 out of 100 requests beat; averages hide the slow ones people feel).

## What we chose and why

- **Suggested SLOs**: 99.5% of uploads succeed; 95% of clips analysed within 10 minutes; 98% of readable clips finish rather than fail.
- **The best single signal** is the age of the oldest clip waiting in the queue. It's what players actually feel.
- **Graceful degradation everywhere.** Gemini down → rule-written notes. Workers down → clips wait in the queue and run later; nothing is lost. Phone offline → saved screens and the upload queue.
- **Error tracking that respects children.** Reports leave our servers without names, request bodies, headers or local variables, and emails and phone numbers are replaced. The app has no crash SDK: it sends crashes to our own API, which scrubs them, keeps at most 20 a day per player, and only then forwards them.
- **A hard cap on GPUs** (4 at once), so a traffic spike or a bug can't produce a huge bill.
- **The API refuses to start in production with development secrets**: a failed deploy is caught by the health check while the old version keeps running.

**Safety, built like reliability:**

- **Guardian approval.** An under-18 player's guardian gets a short link by text. The link only *finds* the request; to act, the guardian proves they hold the phone with a one-time code (10 minutes, 5 tries). Codes are stored hashed, like passwords.
- **No messages, minimal profiles.** Others only see a shirt name, position, age group and region.
- **Moderation with an audit trail.** Reports hide a clip until staff review it in Pep Lab › Safety, and every decision is logged.
- **Deleting an under-18's account** needs the guardian's yes once they've approved the account.

## How it's set up

| Practice | Where |
| --- | --- |
| Health checks and metrics | `/healthz`, `/readyz`, `/metrics` in `pep/api/app.py` |
| Structured logs | `pep/log.py` |
| Leases, retries, idempotent jobs | `pep/db.py`, `pep/worker.py` |
| Error tracking (`PEP_SENTRY_DSN`) | `pep/errors.py` |
| App crash reports | `pep/players/app_errors.py`; Pep Lab › App errors |
| Backups, restore and check | `scripts/backup.py`; the monthly restore drill in `docs/RUNBOOK.md` |
| Load test | `scripts/load_test.py` |
| Guardian approval | `pep/players/guardian.py` |
| Moderation | `pep/players/moderation.py` |

## Words to know

SRE · SLI · SLO · error budget · observability · log · metric · trace · error tracking · health check · incident · blameless postmortem · runbook · graceful degradation · backup · restore drill · load test · percentile · rate limit · one-time code

## Workbook 10

**Try it**

1. Run `pep serve`, use the app, then open `localhost:8000/metrics`. Find the request counter for `/v1/videos`.
2. Point `PEP_DATABASE_URL` at nothing and call `/healthz` and `/readyz`. Why do they answer differently?
3. Run `python scripts/load_test.py --players 20 --seconds 30`. Which call has the highest p95? Why is sign-up slow on purpose?
4. Do the restore drill on your laptop: `backup`, `restore`, `check`. Then delete a player from the restored copy and run `check` again. What does it report?
5. Sign up as a 15-year-old, add a guardian number, and read the text in the `sms_outbox` table. Try 6 wrong codes on the guardian page. What happens, and which setting decides?

**Questions**

**1. Your SLO is 99.5% and you've used the whole error budget by day 20. What happens?**

*Answer:* Pause risky releases and spend the time on reliability until the budget recovers.

**2. Why alert on "clips waiting over 10 minutes" rather than "GPU at 90%"?**

*Answer:* The first is something players feel. A busy GPU is fine as long as clips finish on time.

**3. Why are postmortems blameless?**

*Answer:* If people are punished for mistakes, they hide them, and the system never improves. Most incidents come from systems that made the mistake easy.

**4. Why send app crashes to our own API instead of straight to a crash service?**

*Answer:* Most players are children. Our API can strip personal details and limit how much is sent before anything leaves, and the store privacy forms stay simple.

## More practice

Exercises added as features were built. Each one points at real code.

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
