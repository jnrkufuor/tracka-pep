# 03 · The cloud

We rent everything and manage as little as possible: the API and database on Render, the GPU workers on Modal, video files and the website on Cloudflare. Each is the cheapest place that does its one job well.

## The idea

"The cloud" means **computers in someone else's data centre that you rent by the hour, minute or second**. Instead of buying a server, you ask a provider for computing power, storage or a database, and pay for what you use.

The key question is **how much do you manage yourself?**

| Level | Food version | You manage | Examples |
| --- | --- | --- | --- |
| **Your own servers** | Grow and cook everything | Everything, including the building | A server in a cupboard |
| **IaaS** (infrastructure) | Rent a kitchen | Operating system, software, updates | AWS EC2, DigitalOcean |
| **PaaS** (platform) | A catering kitchen with staff | Just your code | Render, Fly.io, Railway, Heroku |
| **Serverless** | Order a meal when hungry | Just functions; nothing runs when idle | Modal, AWS Lambda, Cloudflare Workers |
| **SaaS** (software) | Eat at a restaurant | Nothing; you just use it | Gmail, GitHub, the Gemini API |

The less you manage, the faster you move, with less control and (usually) a higher price per unit. Small teams should manage as little as possible.

## Why we need GPUs

A **CPU** (the normal processor) is a few very smart workers who do one task at a time, quickly. A **GPU** (graphics processor) is thousands of simple workers who all do the same small sum at once. Graphics need exactly that: every pixel gets the same maths. So does AI. Finding players in a video frame means multiplying huge grids of numbers, and a GPU does those in parallel.

For Pep, that's the difference between a 30-second clip taking several minutes on a CPU and well under a minute on a GPU. But GPUs are expensive, and clips arrive in bursts (evenings, weekends), so you don't want one switched on all day. That's why the workers run on **serverless GPUs**: a GPU starts when there's a clip and stops when the queue is empty, and we pay per second.

## The usual ways to do it

Most products need the same handful of pieces. These are the common choices for each:

| Piece | What it's for | Common choices |
| --- | --- | --- |
| App platform (PaaS) | Run the API around the clock | Render, Fly.io, Railway, Heroku |
| Managed database | Someone else runs backups, upgrades and failover | Render Postgres, Neon, Supabase, AWS RDS |
| Serverless GPUs | Rent a GPU only while a job runs | Modal, RunPod, Replicate |
| Object storage | Store big files cheaply | Cloudflare R2, AWS S3, Backblaze B2 |
| Static hosting + CDN | Serve a website made of fixed files from servers near users | Cloudflare Pages, Netlify, Vercel |

**Containers** tie it together. A container packages your program *with* everything it needs (Python version, libraries, ffmpeg) into one **image**, so it runs the same on a laptop and in the cloud. **Docker** builds them from a recipe called a **Dockerfile**.

Words that decide the bill: **compute** (CPU or GPU time), **storage** (gigabytes per month), **egress** (data leaving the provider, often expensive for video), and **always-on vs scale-to-zero** (a server that's always on costs the same busy or idle; a serverless one costs nothing idle but takes a few seconds to wake, a **cold start**).

## What we chose and why

| Piece | Where | Why there |
| --- | --- | --- |
| API | **Render** web service, Frankfurt | Deploys from GitHub, HTTPS and health checks built in, one-click rollback. Frankfurt is Render's closest region to Ghana |
| Database | **Render Postgres**, Frankfurt | Managed backups, and next to the API so they talk privately and fast |
| Workers | **Modal** serverless GPUs | Pay per second, nothing when idle, a hard cap of 4 GPUs at once |
| Video files | **Cloudflare R2** | S3-compatible with **no egress fees**: clips are watched and downloaded a lot |
| Website | **Cloudflare Pages** | The web app is static files; Pages serves them from a city near the player, free |
| AI coach | **Gemini API** | A top video-reading model without running one ourselves |

We describe the Render setup in a file in git (`render.yaml`), so it can be reviewed and rebuilt from scratch. That's **infrastructure as code**.

**Testing and launch use different plans.** `render.yaml` sets up the free plans for testing: the API sleeps after 15 quiet minutes and the free database stops after 30 days. `render.prod.yaml` sets up the paid plans for real players. Render has no free background workers, which is another reason the analysis runs on Modal.

## How it's set up

- Two Dockerfiles: `Dockerfile` (the small API image, no AI libraries) and `Dockerfile.worker` (PyTorch, YOLO, ffmpeg). The API stays small and quick to deploy.
- Render's disk is temporary: anything written there disappears on the next deploy. That's why clips go straight to R2.
- The app and the workers download clips from R2 with **presigned URLs** (temporary signed links), so video never passes through the API.
- `deploy/modal_app.py` has two entry points. `kick()` is called by the API right after an upload, so a clip starts within seconds. `drain()` also runs on a timer as a safety net, in case a kick is missed.
- Push notifications: the API signs a short token with a Firebase **service account** key and swaps it for an access token (`pep/players/push.py`). The key lives only in an environment variable.
- Step-by-step setup: `docs/RUNBOOK.md` and `docs/PUSH_SETUP.md`.

## Words to know

cloud · IaaS · PaaS · serverless · SaaS · CPU · GPU · container · image · Dockerfile · region · compute · egress · cold start · scale to zero · CDN · static hosting · object storage · managed database · infrastructure as code · presigned URL · service account

## Workbook 03

**Try it**

1. Build the API image (`docker build -t pep-api .`), run it (`docker run -p 8000:8000 pep-api`) and open `/healthz`. Then read the `Dockerfile` line by line and explain each one.
2. Compare `render.yaml` with `render.prod.yaml`. List every difference and say what a player would notice for each (hint: the first visit after 15 quiet minutes).
3. Upload a clip, find it in the R2 bucket, open its presigned link, wait an hour, and try the link again.
4. In Modal's dashboard, watch a `drain` run. How long was the cold start, and how long the actual analysis?

**Questions**

**1. Why do the workers need GPUs and the API doesn't?**

*Answer:* The workers run AI models that multiply huge grids of numbers, which GPUs do thousands at a time. The API mostly reads and writes small records, which a CPU does easily.

**2. Why serverless GPUs instead of one GPU server that's always on?**

*Answer:* Clips arrive in bursts. An always-on GPU costs the same at 3 a.m. as at 7 p.m. Serverless GPUs cost nothing when the queue is empty.

**3. Why store videos in R2 and not on Render's disk or in the database?**

*Answer:* Render's disk is wiped on every deploy, and databases are built for small records, not huge files. R2 is cheap per gigabyte and charges nothing when clips are downloaded.

**4. Why keep the API and database in the same region?**

*Answer:* Every request touches the database, often several times. In the same region they talk over a fast private network; across the world, each request would wait for many long round trips.

## More practice

Exercises added as features were built. Each one points at real code.

1. Build the API image: `docker build -t pep-api .`, run it with
   `docker run -p 8000:8000 pep-api`, and open `/healthz`. Then read the
   `Dockerfile` line by line and explain each one.
2. Deploy to Render from `render.yaml` (New → Blueprint). Open your
   service's Logs while you call `/readyz`. Then compare `render.yaml` with
   `render.prod.yaml`: list every difference, and for each one say what a
   player would notice (hint: the first call after 15 quiet minutes).
3. Create an R2 bucket, set the `PEP_S3_*` variables, upload a clip, and
   find it in the bucket. Open its presigned link, wait an hour, and try
   again.
4. `pip install modal`, then `modal deploy deploy/modal_app.py`, and watch
   a clip run on a GPU in Modal's dashboard.
5. Read `access_token()` in `pep/players/push.py`. Decode the JWT it signs
   (jwt.io, with a test key): what are `iss`, `aud` and `exp`, and why is the
   token cached for less than the hour it lasts?
