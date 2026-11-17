# 04 · CI/CD: shipping code safely

## The idea

Imagine a group essay where five people edit the same document. If
everyone saves over each other for a month and then tries to combine
the versions the night before it's due, it's chaos. Much better: each
person adds small changes often, and a strict friend checks every
change (spelling, references, word count) before it goes in.

That is **CI/CD**:

- **Continuous Integration (CI)**: every change is merged into the main
  code often (daily, not monthly), and a robot **automatically checks**
  each one: does it build, do the tests pass, is the style right?
- **Continuous Delivery (CD)**: every change that passes is *ready* to
  release with one click.
- **Continuous Deployment** (the other CD): every change that passes is
  released *automatically*, with no click.

Why bother? Bugs are cheapest to fix minutes after they're written.
Small releases are easy to understand and easy to undo. And nobody has
to remember a 20-step release checklist: the robot does it the same way
every time.

## The pieces

### Version control (git) and branches
**Git** records every change to the code with who made it and why. A
**branch** is a parallel copy where you can work without disturbing the
main code. When you're done, you open a **pull request (PR)**: a request
to merge your branch, where teammates review the change and CI checks
it. **Branch protection** can require green checks and a review before
anything merges into `main`.

### Common branching approaches

| Approach | How it works | Good for |
|---|---|---|
| **Trunk-based** | Everyone merges small changes into `main` many times a day; unfinished features hide behind flags | Fast teams with good tests |
| **GitHub Flow** | Short-lived branch per change → PR → merge to `main` → deploy | Most small teams (Tracka) |
| **Git Flow** | Long-lived `develop` and `release` branches | Products with scheduled versions (some mobile apps, boxed software) |

### What the robot checks
- **Linting**: style and common-mistake checks (unused variables,
  risky patterns). Python: `ruff`. Dart: `flutter analyze`.
- **Formatting**: one consistent layout so diffs show real changes.
- **Type checking**: catches "you passed text where a number was
  expected" before the program runs. Python: `mypy`.
- **Tests**:
  - **unit tests** check one small piece (does hashing a password then
    checking it work?);
  - **integration tests** check pieces together (upload → worker →
    score appears);
  - **end-to-end tests** drive the whole app like a user.
  The usual advice is a **test pyramid**: many fast unit tests, fewer
  integration tests, a handful of slow end-to-end ones.
- **Builds**: the Docker image builds, the app compiles.
- **Security**: known-vulnerable libraries (Dependabot), leaked secrets.

### CI tools

| Tool | Notes |
|---|---|
| **GitHub Actions** | Built into GitHub; workflows are YAML files in `.github/workflows/` |
| GitLab CI | Same idea, built into GitLab |
| CircleCI, Buildkite, Jenkins | Separate services (Jenkins you host yourself) |
| Codemagic, Bitrise | Specialists in mobile app builds |

A GitHub Actions **workflow** runs on an **event** (a push, a PR, a
schedule, a button). It contains **jobs** (which run in parallel on
fresh virtual machines called **runners**), and each job has **steps**
(commands). **Secrets** (passwords, API keys) are stored in GitHub's
settings and handed to jobs at run time, never written in the code.
An **artifact** is a file a job produces (an app build, a report).

### Ways to release safely

| Strategy | How | Why |
|---|---|---|
| **Rolling** | Replace servers one at a time | Simple; the default on most platforms |
| **Blue-green** | Run the new version beside the old, then switch traffic over | Instant switch back if it's bad |
| **Canary** | Send 5% of users to the new version first, watch, then the rest | Bugs hurt few people |
| **Feature flags** | Ship the code switched off; switch it on later (for some users) | Separates "deployed" from "released" |
| **Rollback** | Go back to the last good version | Your safety net. Practise it |

Mobile apps are different: once someone installs a version, you can't
roll it back on their phone. That's why app stores offer **staged
rollouts** (release to 10% of users first) and why the server must keep
supporting older app versions for a while.

## How Tracka does it

| Workflow file | Runs when | What it does |
|---|---|---|
| `ci.yml` | Every push and PR | Ruff lint + format, mypy, tests on SQLite *and* Postgres, a slow test with the real YOLO models, Docker image builds |
| `app.yml` | Changes in `app/` | `flutter analyze` + tests; builds the **web app** (and deploys it to Cloudflare Pages from `main`) and the **Android APKs** |
| `deploy.yml` | Push to `main` after CI passes | Triggers Render's deploy hook and `modal deploy` (skipped if the secrets aren't set) |
| `evaluate.yml` | By hand | Runs the benchmark, so model changes come with numbers |
| `screenshots.yml` | App changes, or by hand | Builds the app in demo mode and photographs every screen |
| `dependabot.yml` | Weekly | Opens PRs to update libraries and Actions |

- **Branching: GitHub Flow.** Feature branches (like `player-app`), PRs
  into `main`, `main` always deployable.
- **Continuous deployment for the API**: green `main` → Render deploys
  automatically (rolling, with a health check on `/readyz`). Rollback is
  one click in Render's dashboard.
- **Continuous delivery for the apps**: CI produces an APK and a web
  build on every change; publishing to the Play Store / App Store is a
  deliberate manual step.
- **Tests at two levels**: `tests/test_player_api.py` drives the API
  like the app does (sign up → upload → worker → coach summary), and
  smaller tests check pieces like norms and the Kalman filter.
- **Same tests, two databases**: tests run on SQLite (fast) and real
  Postgres (the `SKIP LOCKED` queue only exists there).
- **Models get CI too**: `MODEL_VERSION` is bumped when scoring changes,
  and `training/evaluate.py` reports before/after numbers. This is
  sometimes called **MLOps**: CI/CD ideas applied to machine learning.

## Words to know
CI · continuous delivery · continuous deployment · git · branch · pull
request · branch protection · trunk-based · GitHub Flow · lint · type
check · unit / integration / end-to-end test · test pyramid · workflow ·
job · step · runner · secret · artifact · rolling · blue-green · canary ·
feature flag · rollback · staged rollout · MLOps

## Workbook 04

**Try it**
1. Make a branch, break a test on purpose (change an expected number in
   `tests/test_scoring.py`), push, and open a PR. Watch CI go red and read
   the log. Fix it and watch it go green.
2. Turn on branch protection for `main` (Settings → Branches): require
   the `CI` checks and one review.
3. Read `.github/workflows/app.yml` and draw its jobs: which run in
   parallel, which wait (`needs:`) for others?
4. Add a step to `ci.yml` that prints how long the test suite took.
5. Practise a rollback: deploy something to Render, then roll back to the
   previous deploy from the dashboard.

**Questions**

**1. What's the difference between continuous delivery and continuous
deployment?**

*Answer:* Delivery: every passing change is *ready* to release, and a
person presses the button. Deployment: every passing change is released
automatically.

**2. Why do Tracka's tests run on both SQLite and Postgres?**

*Answer:* SQLite is fast and needs no setup, but production is Postgres,
and some features (like `FOR UPDATE SKIP LOCKED`) only exist there. Testing
both catches bugs that only appear in production's database.

**3. Why can't you "roll back" a mobile app like you can a server?**

*Answer:* The old version is already installed on people's phones, and you
can't change it remotely. You can only ship a new fixed version, so you
use staged rollouts and keep the API compatible with older app versions.

**4. Where should the Cloudflare API token live, and why not in the YAML
file?**

*Answer:* In GitHub's encrypted Secrets. The YAML is in git, which anyone
with repo access (now or in the future) can read, along with its whole
history.
