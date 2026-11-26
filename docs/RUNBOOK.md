# Runbook: keeping Tracka up

What to do, step by step, when something needs looking after. Written for
whoever is on call, including you at 11 pm before a tournament. The ideas
behind it are in handbook chapter 10.

## Every day: is anything wrong?

| Look at | Where | Worry when |
|---|---|---|
| Players waiting for Pep | `/metrics`: `pep_oldest_queued_seconds` | over 600 (10 minutes) |
| Server errors | `/metrics`: `pep_http_requests_total{status=~"5.."}` | more than 1 in 200 calls |
| New crashes | Pep Lab › App errors, and the error tracker (if `PEP_SENTRY_DSN` is set) | a new crash, or one hitting many players |
| Safety | Pep Lab › Safety | any open report. Safety reports about a child come first, the same day |
| Texts to guardians | the `sms_outbox` table | rows stuck as not sent |

## Error tracking

- **Server:** set `PEP_SENTRY_DSN` to a Sentry or GlitchTip project DSN and
  restart. Reports leave without user details, request bodies, headers or
  local variables, and emails and phone numbers in messages are replaced
  (`pep/errors.py`). Empty = errors only go to the logs.
- **App:** release builds send crashes to `POST /v1/app-errors` on our own
  API, never straight to another company. They show in Pep Lab › App errors,
  grouped, and are forwarded to the tracker when the DSN is set.
- Fix first what hits the most *players*, not what happens most often.

## Backups

**What needs backing up:**
1. The database (accounts, profiles, results, guardian approvals). Use your
   database host's daily backups *and* our own copy, kept with another provider.
2. The clips, in object storage (R2/S3). Turn on **object versioning** with a
   30-day lifecycle rule for old versions, so a clip deleted by mistake can be
   brought back. Clips a player deletes on purpose must stay deleted: the
   30-day rule makes sure the old versions go too, and the privacy policy
   should say "within 30 days".

**Our own copy, nightly** (a scheduled job on the host, e.g. a Render cron job):

```bash
python scripts/backup.py backup --upload    # pg_dump to PEP_BACKUP_BUCKET/backups/
```

Use a separate bucket from the clips, with its own keys, and a lifecycle rule
that deletes backups after 35 days. A backup is personal data about children:
keep it encrypted at rest (R2 and S3 are) and limit who can read the bucket.

## The restore drill (once a month, 20 minutes)

A backup you've never restored is a hope. Once a month:

1. Make an empty database (a free Neon or Supabase project, or
   `createdb pep_drill` locally).
2. Download last night's backup from the backup bucket.
3. Restore it:
   `python scripts/backup.py restore pep-<time>.dump --into postgresql://…/pep_drill`
4. Check it: `python scripts/backup.py check postgresql://…/pep_drill`
   - row counts look like production's (Lab › Health);
   - `newest` is from last night;
   - `orphans: none` (exit code 0).
5. Point a local `pep serve` at it (`PEP_DATABASE_URL=…`), log in with a test
   account, open Home. Then delete the drill database.
6. Write the date and how long it took in the table below. If anything failed,
   that's this month's most important fix.

| Date | Backup from | Minutes to restore | Problems |
|---|---|---|---|
| | | | |

## When production's database is lost or broken

1. Stop writes: put the API in maintenance (scale it to 0, or turn on the
   host's maintenance page). Players see "Can't reach Tracka"; the app keeps
   showing saved screens, and the upload queue keeps clips on the phone.
2. Prefer the host's **point-in-time recovery** (fewer lost minutes). If that's
   not possible, restore our nightly copy into a *new* database, as in the drill.
3. Check it (step 4 above), then point `PEP_DATABASE_URL` at it and start the API.
4. Anything since the backup is lost: clips uploaded since then are still in
   storage but have no rows. Tell players plainly, in the app and on WhatsApp.
5. Write a blameless postmortem (handbook 10, workbook question 4).

## Load testing (before a big day)

```bash
pep serve   # or a staging copy, never production on a busy day
python scripts/load_test.py --url http://localhost:8000 --players 50 --seconds 60
```

It signs up adult test accounts, opens the screens the app uses most, and
deletes the accounts at the end. Watch **p95** and **errors**. Uploads are
left out (they cost GPU time): test those with a few real clips.

Baseline on a laptop (one process, SQLite, November 2026): 50 players, about
150 calls a second, 0 errors, p95 under 100 ms for most screens, slowest
`/v1/progress` at about 310 ms. Sign-up is slow on purpose (password hashing).
Re-run against staging on Postgres before launch and write the numbers here.

## Clips while testing for free (Modal)

The free Render setup (`render.yaml`) has no worker, because Render's
background workers are never free. Clips are analysed on Modal instead,
whose free plan includes monthly credits:

1. Sign up at modal.com, then on your laptop: `pip install modal && modal token new`.
2. In Render, open `pep-db` › Connect and copy the **External** database URL.
   Change `postgresql://` at the start to `postgresql+psycopg://`.
3. Create the secret Modal reads (one line; values from Render's Environment tab):
   `modal secret create pep-secrets PEP_DATABASE_URL=… PEP_STORAGE=s3 PEP_S3_BUCKET=pep-clips PEP_S3_ENDPOINT=… PEP_S3_ACCESS_KEY=… PEP_S3_SECRET_KEY=… PEP_KICK_TOKEN=… COACH_WEBHOOK_SECRET=…`
4. `modal deploy deploy/modal_app.py`. It prints a `kick` address: put it in
   Render as `PEP_KICK_URL`, so clips start within seconds.
5. Upload a clip in the app. Modal's dashboard shows the run; Pep's notes
   appear when it finishes.

Watch the credits in Modal's dashboard. `max_containers=4` caps how many
GPUs run at once. The safety-net run (every 30 minutes while testing) costs a
little even when the queue is empty; set it to 2-5 minutes at launch in
`deploy/modal_app.py`.

Instead of steps 1 and 4 on a laptop, CI can deploy it: add `MODAL_TOKEN_ID`
and `MODAL_TOKEN_SECRET` (Modal › Settings › API Tokens) as GitHub secrets, and
every merge to main redeploys the worker. Create `pep-secrets` in Modal's
dashboard (Secrets › Custom) with the same values as step 3.

## Pushes not arriving

`docs/PUSH_SETUP.md`. Check `PEP_FCM_SERVICE_ACCOUNT` is set, look for
`push.failed` in the logs, and remember iOS needs an APNs key in Firebase.

## Guardian texts not arriving

Texts are a placeholder until an SMS provider is chosen (`LogSender` writes to
`sms_outbox`). Until then guardians use the link, and the self-confirm tick is on.
