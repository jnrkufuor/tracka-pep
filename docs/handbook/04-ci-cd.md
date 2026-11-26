# 04 · Shipping code safely

Every change goes through a pull request that a robot checks. When it merges into `main`, the API, workers and website deploy themselves; the phone apps are released by hand.

## The idea

Imagine five people writing one essay. If everyone saves over each other for a month and combines the versions the night before it's due, it's chaos. Much better: everyone adds small changes often, and a strict friend checks each one before it goes in.

That's **CI/CD**:

- **Continuous Integration (CI)**: changes are combined into the main code often, and a robot checks each one: does it build, do the tests pass, is the style right?
- **Continuous Delivery**: every change that passes is *ready* to release with one click.
- **Continuous Deployment**: every change that passes is released *automatically*.

Why bother? Bugs are cheapest to fix minutes after they're written, small releases are easy to understand and undo, and nobody has to remember a 20-step release checklist.

## The usual ways to do it

**Version control.** **Git** records every change with who made it and why. A **branch** is a parallel copy where you work without disturbing the main code. A **pull request (PR)** asks to merge your branch: teammates review it, and CI checks it.

| Branching style | How it works | Good for |
| --- | --- | --- |
| **Trunk-based** | Everyone merges small changes into `main` many times a day; unfinished work hides behind flags | Fast teams with strong tests |
| **GitHub Flow** | A short-lived branch per change → PR → merge to `main` → deploy | Most small teams |
| **Git Flow** | Long-lived `develop` and `release` branches | Products with scheduled versions |

**What the robot checks**: **linting** (style and common mistakes), **formatting** (one consistent layout), **type checking** ("you passed text where a number was expected"), **tests**, **builds**, and **security** (known-vulnerable libraries, leaked secrets). Tests come in three sizes: **unit** tests (one small piece), **integration** tests (pieces together), and **end-to-end** tests (the whole app, like a user). The usual advice is a **test pyramid**: many fast small tests, a few slow big ones.

**CI tools**: GitHub Actions (built into GitHub), GitLab CI, CircleCI, Jenkins, and mobile specialists like Codemagic. In GitHub Actions, a **workflow** runs on an event (a push, a PR, a timer, a button); it has **jobs** that run on fresh machines called **runners**; each job has **steps**. **Secrets** (passwords, API keys) live in GitHub's settings and are handed to jobs at run time, never written in the code.

**Releasing safely:**

| Strategy | How | Why |
| --- | --- | --- |
| **Rolling** | Replace servers one at a time | Simple; the default on most platforms |
| **Blue-green** | Run the new version beside the old, then switch traffic | Instant switch back |
| **Canary** | Send 5% of users to the new version first | Bugs hurt few people |
| **Feature flags** | Ship code switched off; switch it on later | Separates "deployed" from "released" |
| **Rollback** | Go back to the last good version | The safety net; practise it |

Phone apps are different: once someone installs a version, you can't take it back. That's why app stores offer **staged rollouts** (release to 10% first), and why the API must keep supporting older app versions.

## What we chose and why

- **GitHub Actions**, because the code already lives on GitHub and it's free at our size.
- **GitHub Flow**: a branch per change, a PR into `main`, and `main` is always ready to deploy. Simple enough for a small team, with a review step.
- **Continuous deployment for the servers.** A green `main` deploys the API to Render (rolling, with a health check on `/readyz`), the workers to Modal, and the website to Cloudflare Pages. Rollback is one click in Render.
- **Continuous delivery for the phone apps.** CI builds an Android app on every change, but publishing to the stores stays a deliberate manual step, because you can't take a phone release back.
- **Tests on two databases.** SQLite is fast for everyday tests; production is Postgres, and the job queue's `SKIP LOCKED` only exists there. So the tests run on both.
- **Models get checks too.** When scoring changes, `MODEL_VERSION` goes up and `training/evaluate.py` reports before-and-after numbers. CI/CD ideas applied to machine learning are called **MLOps**.

## How it's set up

| Workflow | Runs when | What it does |
| --- | --- | --- |
| `ci.yml` | Every push and PR | Ruff lint and format, mypy, tests on SQLite and Postgres, a slow test with the real AI models, Docker builds |
| `app.yml` | Changes in `app/` | `flutter analyze` and tests; builds the website (publishes it from `main`) and the Android app |
| `deploy.yml` | After CI passes on `main` | Triggers Render's deploy and `modal deploy` |
| `evaluate.yml` | By hand | Runs the accuracy benchmark |
| `screenshots.yml` | App changes, or by hand | Builds the app in demo mode and photographs every screen |
| `dependabot.yml` | Weekly | Opens PRs to update libraries |

Before committing, run the same checks locally: `ruff check`, `ruff format --check`, `mypy pep`, `pytest`, and in `app/`: `flutter analyze && flutter test`.

## Words to know

CI · continuous delivery · continuous deployment · git · branch · pull request · GitHub Flow · lint · type check · unit, integration and end-to-end test · test pyramid · workflow · job · runner · secret · artifact · rolling · blue-green · canary · feature flag · rollback · staged rollout · MLOps

## Workbook 04

**Try it**

1. Make a branch, break a test on purpose (change an expected number in `tests/test_scoring.py`), push, and open a PR. Read the red log. Fix it and watch it go green.
2. Turn on branch protection for `main` (Settings → Branches): require the CI checks and one review.
3. Read `.github/workflows/app.yml` and draw its jobs. Which run side by side, and which wait (`needs:`) for others?
4. Practise a rollback: deploy something to Render, then roll back to the previous deploy from the dashboard.

**Questions**

**1. What's the difference between continuous delivery and continuous deployment?**

*Answer:* Delivery: every passing change is ready, and a person presses the button. Deployment: every passing change goes out automatically.

**2. Why do our tests run on both SQLite and Postgres?**

*Answer:* SQLite is fast, but production is Postgres, and some features (like `SKIP LOCKED`) only exist there. Testing both catches bugs that would only appear in production.

**3. Why can't you roll back a phone app like a server?**

*Answer:* The old version is already on people's phones and can't be changed remotely. You can only ship a fixed version, so you use staged rollouts and keep the API compatible.

**4. Where should an API token for deploying live, and why not in the workflow file?**

*Answer:* In GitHub's encrypted Secrets. The workflow file is in git, which anyone with access can read, along with its whole history.

## More practice

Exercises added as features were built. Each one points at real code.

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
