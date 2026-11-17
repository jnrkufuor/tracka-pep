# 02 · CI/CD

**CI (continuous integration)**: every push is automatically checked
(lint, types, tests, Docker build) so problems are caught minutes after
they're written, not weeks later in production.

**CD (continuous delivery/deployment)**: once checks pass on `main`, the
same commit is deployed automatically, the same way every time. No "it
worked on my laptop", and no hand-run deploys at midnight.

## The pipeline

```
 git push / pull request
        │
        ▼
 ┌────────────────────── CI (.github/workflows/ci.yml) ───────────────────────┐
 │  lint ─ ruff check, ruff format --check, mypy                               │
 │  test ─ pytest × {sqlite, postgres}  (matrix: same tests, two databases)    │
 │  slow-test ─ real YOLO26 on the synthetic clip (truth: 25.2 km/h)           │
 │  docker ─ build the API image, run it, curl /healthz and /readyz            │
 └─────────────────────────────────────┬───────────────────────────────────────┘
                                       │ all green on main
                                       ▼
 ┌─────────────────── CD (.github/workflows/deploy.yml) ──────────────────────┐
 │  api ─ POST Render deploy hook → wait for /readyz → smoke tests            │
 │  gpu-worker ─ modal deploy deploy/modal_app.py                             │
 └────────────────────────────────────────────────────────────────────────────┘

 Manual: evaluate.yml ─ re-score the benchmark; fail if accuracy dropped (the MLOps gate)
 Weekly: dependabot ─ pull requests for dependency updates (CI runs on each)
```

## Things worth understanding in the YAML

**Triggers (`on:`).** `push` to main and every `pull_request`. Deploy uses
`workflow_run`: it starts when CI *finishes* on main, and its first line
checks that CI actually succeeded.

**`concurrency`.** A new push cancels the old, still-running CI on the same
branch (saves minutes). Deploys use `cancel-in-progress: false`: never stop
a deploy halfway.

**Service containers.** The `test` job starts a real `postgres:16` next to
the runner. Our queue uses `FOR UPDATE SKIP LOCKED`, which SQLite doesn't
have, so the queue code must be tested on Postgres too. That's what the
**matrix** does: same tests, two databases, run in parallel.

**Caching.** `actions/setup-python` with `cache: pip` reuses downloaded
packages. The slow test caches YOLO weights (`actions/cache`), and Docker
builds use the GitHub Actions layer cache (`cache-from: type=gha`). Caching
turns a 10-minute pipeline into a 2-minute one.

**CPU-only PyTorch in CI.** GitHub runners have no GPU, and the CUDA build
of PyTorch is gigabytes. Installing from PyTorch's CPU index is much
smaller and faster. (Production workers use the CUDA build.)

**Secrets.** Deploy URLs and tokens are GitHub Actions secrets, injected as
environment variables. Steps check `if: env.HOOK != ''`, so the workflow
skips cleanly before you've set them up instead of failing.

**Smoke tests.** After deploying, CI calls the live service: `/readyz`
must answer, and an unauthenticated `POST /analyses` must be refused with
401. A smoke test is a few cheap checks that the deploy is alive and secure.
It's not a full test suite.

**Environments.** `environment: production` makes deploys visible under
the repo's Environments, and lets you require a manual approval click before
production changes.

## What I need you to set up on GitHub

1. **Branch protection** on `main` (Settings → Branches → Add rule):
   require a pull request, and require the checks `lint`,
   `test (sqlite)`, `test (postgres)` and `docker` to pass. Now nobody,
   including you, can push broken code straight to main.
2. **Collaborator**: Settings → Collaborators → add Eric (Write access is
   enough to open PRs; Maintain if he should merge).
3. **Actions secrets** (Settings → Secrets and variables → Actions):
   `RENDER_DEPLOY_HOOK_URL`, `PEP_PUBLIC_URL`, `MODAL_TOKEN_ID`,
   `MODAL_TOKEN_SECRET`.
4. **Environment** named `production` (optional: add yourself as a
   required reviewer).
5. On Render, turn **Auto-Deploy off** for pep-api once CI deploys it, so
   only commits that passed CI reach production.

## Branches and releases

- Work on short-lived branches (`feat/ball-detector`, `fix/callback-retry`),
  then open a PR. CI runs; Eric (or you) reviews; merge; CD ships.
- Keep commits small and messages meaningful ("Kalman: lower accel_sigma
  for keepers", not "fix").
- **Rollback**: on Render, every deploy is kept. In the service's
  *Events*, pick the last good deploy and choose *Rollback*. Or
  `git revert` the bad commit and let CD ship the revert (slower, but your
  git history stays truthful).

## The MLOps gate (`evaluate.yml`)

Code tests prove the code does what we wrote. They don't prove the model is
still *accurate*. `training/evaluate.py` re-scores a benchmark of clips with
known answers and **fails if top-speed error goes above a limit**. Run it
before merging anything that touches `vision/`, `metrics/` or `scoring/`.
As real labelled clips come in, the benchmark grows and the gate gets
stricter.

---

## Workbook 02

**Exercises**

1. Push a branch with a deliberate lint error (an unused import). Watch the
   `lint` job fail, read the log, and fix it.
2. Break the queue for Postgres only: change `with_for_update(skip_locked=True)`
   to `with_for_update()` and write a test that claims from two threads.
   Does it fail on SQLite? On Postgres?
3. Run the CI steps locally: `ruff check . && mypy pep && pytest`, then
   `pytest -m slow`.
4. Add a step to `ci.yml` that uploads `coverage.xml` as an artifact.
5. Make a deliberate accuracy regression (set `BOX_TO_STATURE = 0.8` in
   `vision/calibration.py`) and run `training/evaluate.py` on the
   benchmark. Does the gate catch it?

**Questions**

<details><summary>1. What's the difference between continuous delivery and continuous deployment?</summary>

Delivery: every passing commit is *ready* to release, and a human presses
the button (e.g. an environment approval). Deployment: every passing commit
goes out automatically. Our `deploy.yml` is deployment; adding a required
reviewer on the `production` environment turns it into delivery.
</details>

<details><summary>2. Why test the API Docker image in CI if Render builds it anyway?</summary>

To find out *before* merging. A broken Dockerfile found on Render means a
failed production deploy. Found in CI, it's just a red check on a PR.
</details>

<details><summary>3. Why are secrets passed as env vars rather than written in the YAML?</summary>

The YAML is in git: anyone who can read the repo (it's public!) would see
them, forever, in history. GitHub encrypts secrets, masks them in logs, and
doesn't expose them to pull requests from forks.
</details>

<details><summary>4. A deploy passed the smoke test but players report wrong scores. What kind of check would have caught it?</summary>

A model evaluation gate (`evaluate.yml`) on a benchmark with ground truth,
or a canary: send a small share of traffic to the new version and compare
its score distribution with the old one before rolling out fully. Smoke
tests check liveness, not correctness.
</details>
