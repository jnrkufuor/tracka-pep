# 10 · Runbook: running Pep in production (SRE)

## Service level objectives (SLOs)
An **SLO** is a target for how well the service should work, measured from
the user's side. Pep's starting SLOs:

| SLI (what we measure) | SLO (target) | Where to see it |
|---|---|---|
| API availability: `/readyz` and `POST /analyses` succeed | 99.5% per 30 days | Render metrics, `pep_http_requests_total` |
| Time to result: clip queued → result sent | 95% under 3 minutes | Lab › Health (wait + run p95) |
| Analysis success: READY ÷ (READY + FAILED for non-clip reasons) | 98% | Lab › Health |
| Callback delivery | 99.9% of results reach Tracka | `callbacksGaveUp` = 0 |

**Error budget**: 99.5% availability allows about 3.6 hours down a month.
Spend it on deploys and experiments; when it runs out, freeze features and
fix reliability.

## Alerts (page someone only for things users feel)
| Alert | Condition | Likely causes |
|---|---|---|
| Queue backing up | `pep_oldest_queued_seconds` > 600 for 10 min | Workers down, Modal deploy failed, GPU quota |
| Failure spike | > 10% FAILED in an hour | Bad deploy, model file missing, Gemini outage (shouldn't fail jobs: check) |
| Callbacks giving up | any `GAVE_UP` | Tracka down or secret mismatch |
| API down | `/readyz` failing for 2 min | DB down, bad deploy, Render incident |

## Incidents: what to do

**Clips stuck in QUEUED**
1. Lab › Health: is anything RUNNING? Check the oldest queued age.
2. Modal dashboard: did `drain` run recently? Errors? Check `pep-secrets`
   (DB URL).
3. Render worker (if used): is it running? Out of memory? (Logs: `Killed`.)
4. Quick fix: trigger a drain by hand (`modal run deploy/modal_app.py::drain`)
   or `pep drain` from any machine with the production env.

**Many FAILED with "Something went wrong"**
1. Read `job.error` events in the logs (they include the traceback).
2. A recent deploy? Roll back on Render or Modal, then investigate.
3. Retry: send the same `analysisId` again; a FAILED job is re-queued
   (`db.enqueue`).

**Tracka says it never got results**
1. Lab › result › Under the hood › callback status and error.
2. `HTTP 401/403` → `COACH_WEBHOOK_SECRET` differs between Pep and Tracka.
3. Timeouts → Tracka asleep (free plan) or down. Pending callbacks retry
   automatically for about 8 minutes (6 tries: 15 s, 30 s, 1, 2, 4 min); `GAVE_UP` ones can be resent by setting
   `callback_status='PENDING'` in SQL.

**Scores suddenly look different**
1. Compare `modelVersion` before and after.
2. Run `training/evaluate.py` on the benchmark with both versions.
3. If the norms file changed, that's expected. Communicate it.

## Deploys
- Merge to `main` → CI → CD (Render hook, then Modal). Watch the deploy job.
- **Rollback**: Render › pep-api › Events › previous deploy › Rollback.
  Modal: check out the last good commit and run
  `modal deploy deploy/modal_app.py` again.
- Database changes: back-compatible first (add columns, never drop in the
  same deploy).

## Routine
- Weekly: review Dependabot PRs; skim failures in Lab › Players (FAILED).
- Monthly: retrain the scorer if new ratings arrived; rebuild norms
  quarterly; test restoring a database backup.

## Workbook 10
1. Set up Grafana Cloud (free tier) to scrape `/metrics`; build a panel
   for `pep_oldest_queued_seconds` and an alert at 600 s.
2. **Game day**: stop all workers for 15 minutes on staging, queue 20
   clips, watch the alert fire, restart, and time the recovery.
3. Write a postmortem template: timeline, impact, root cause, what went
   well, action items. Blameless: systems fail, not people.

<details><summary>Why alert on queue age rather than queue length?</summary>

Users feel waiting time, not queue size. 50 queued clips with 10 fast
workers is fine; 3 clips with no workers is an outage. The age of the oldest
job captures both.
</details>
