# 03 · The platforms: what each one is for

You used Render and Cloudflare on tracka-api. Here's what those (and the
other platforms Pep uses) actually are, what they're good and bad at, and
the gotchas.

## The categories first

| Category | What it means | Pep uses |
|---|---|---|
| **PaaS** (Platform as a Service) | You give it code or a Dockerfile; it runs, restarts, scales and serves it. You don't manage servers. | Render |
| **Serverless compute** | Functions or containers start when there's work and stop when there isn't. Pay per second. | Modal (GPUs) |
| **Object storage** | A huge, cheap key → file store reached over HTTP. Not a disk. | Cloudflare R2 |
| **Edge network / CDN** | Servers in hundreds of cities that sit in front of your app: caching, TLS, DNS, security. | Cloudflare |
| **Managed database** | Someone else runs Postgres: backups, upgrades, failover. | Render Postgres |
| **CI/CD** | Runs your checks and deploys on every push. | GitHub Actions |
| **Model API** | A hosted AI model you call over HTTP. | Gemini |
| **Containers** | Package the app *with* its OS libraries, so it runs the same everywhere. | Docker |

The art is in the trade-off: the more a platform does for you, the less
control you have and (usually) the more each unit costs. PaaS is perfect
for a small team; at large scale you might move to Kubernetes or bare cloud
VMs.

## Render (PaaS)

**What it does.** Builds your repo (or Dockerfile), runs it, restarts it if
it crashes, gives it HTTPS and a URL, rolls out new versions with zero
downtime (it waits for the health check before switching traffic), keeps
old deploys for one-click rollback, and runs managed Postgres.

**Service types you'll meet:**
- *Web service*: gets HTTP traffic (the Pep API).
- *Background worker*: no HTTP, just runs (the CPU Pep worker).
- *Cron job*: runs on a schedule.
- *Postgres / Key Value*: managed databases.

**Key ideas:**
- **Blueprints** (`render.yaml`) are **infrastructure as code**: the
  services, database and env vars live in git. Recreating everything takes
  one click, and changes are reviewable in PRs.
- **Regions**: Render runs in Oregon, Ohio, Virginia, Frankfurt and
  Singapore. Frankfurt is the closest to Ghana, so Pep uses it. Keep the API
  and its database in the *same* region: they talk over a private network.
- **Ephemeral filesystem**: anything written to disk vanishes on the next
  deploy. That's why clips go to R2.
- **Free plans sleep** after 15 minutes idle (the first request then takes
  about a minute), and the free Postgres expires after 30 days. Fine for
  experiments, not for Tracka.
- **Health checks**: `healthCheckPath: /readyz` means a deploy only goes
  live once it can reach the database.
- **Docker target limitation**: Render builds a Dockerfile's final stage
  and can't pick a target. That's why Pep has two files: `Dockerfile` (API)
  and `Dockerfile.worker`.

**Gotchas:** don't keep state on disk; set secrets in the dashboard (or
`sync: false` in the blueprint), never in git; watch memory, since PyTorch
needs at least 2 GB (that's why the worker is on the `standard` plan).

## Cloudflare

Cloudflare is a global network that sits *in front of* (and increasingly
*runs*) your app. The pieces that matter for Tracka:

- **R2 object storage**: S3-compatible (boto3 works unchanged; just point
  `endpoint_url` at R2) with **zero egress fees**. Egress (data *leaving*
  storage) is what makes video expensive on AWS S3. Every clip is
  downloaded by a GPU worker and streamed to scouts, so free egress matters
  a lot here.
- **DNS**: maps `pep.tracka.app` to Render. With the orange-cloud
  **proxy** on, traffic goes through Cloudflare first.
- **CDN / caching**: static files (the Lab's JS/CSS/fonts) are served
  from a nearby Cloudflare city instead of from Frankfurt. That's a real
  speed-up for users in Accra or Kumasi on mobile data.
- **TLS**: free HTTPS certificates; terminate TLS at the edge.
- **WAF and rate limiting**: block abusive traffic before it reaches
  Render. Put a rate limit on `/lab/clips`, since uploads are the
  expensive endpoint.
- **Workers**: small JavaScript or Python functions that run at the edge.
  Later you could validate uploads or sign R2 URLs there.

**R2 setup in short:** create bucket `pep-clips` → R2 → Manage API tokens
→ create a token with Object Read & Write on that bucket → copy the
Access Key ID, Secret and the S3 endpoint
(`https://<account>.r2.cloudflarestorage.com`) into Render as
`PEP_S3_ACCESS_KEY`, `PEP_S3_SECRET_KEY`, `PEP_S3_ENDPOINT`. Add a
**lifecycle rule** that deletes `clips/` after 30–90 days (privacy, and it
keeps storage small).

**Gotcha you hit before:** the endpoint must be the account endpoint
*without* the bucket name, and the bucket's jurisdiction (default vs EU)
must match the endpoint you use.

## Modal (serverless GPUs)

**What it does.** You write Python with decorators
(`@app.function(gpu="L4")`). Modal builds the image, and when the
function is called it starts a GPU container in seconds, runs it and shuts
it down. You pay per second of use. **Scale to zero**: no clips, no bill.

In Pep (`deploy/modal_app.py`):
- `drain()` runs every 2 minutes (`modal.Period`) and processes the queue
  until it's empty.
- `kick()` is a web endpoint the API calls right after queueing, so a clip
  starts within seconds instead of waiting for the next tick.
- `max_containers=4` is a **hard cap on spend**: never more than 4 GPUs at
  once, even if 500 clips arrive.
- Model weights are baked into the image at build time, so containers
  don't download them on every cold start.

**Cold starts.** The first call after idle waits for a container (a few
seconds) plus model loading. For clips that take tens of seconds anyway,
that's acceptable. For live use you'd keep one container warm
(`min_containers=1`), which costs money around the clock.

**Alternatives:** RunPod, Replicate and Baseten (similar idea), or a plain
GPU VM on AWS/GCP/Lambda (cheaper if busy all the time, wasteful if not).

## GitHub (Actions, Dependabot, branch protection)
Covered in [02 · CI/CD](02-cicd.md). Actions runners are fresh virtual
machines for each job. Free minutes are generous for public repos.

## Docker
A **container image** is your app plus the exact OS libraries it needs
(ffmpeg, libGL, Python 3.12), frozen. The same image runs on your laptop, in
CI, on Render and on Modal. Concepts used in Pep's Dockerfiles: slim base
images; **layer caching** (copy `pyproject.toml` and install deps *before*
copying code); a **non-root user**; `.dockerignore` keeps secrets and junk
out; weights downloaded at build time.

## Gemini API (the AI coach)
A hosted multimodal model that accepts video. Pep uploads the clip with
the Files API, asks for **structured JSON** matching a pydantic schema, and
deletes the file afterwards. Model `gemini-3.8-flash` (configurable with
`PEP_COACH_MODEL`). Pricing is per token; video becomes tokens. See
[08 · Cost](08-cost.md). Gotchas: API keys are secrets; models get
deprecated and renamed (3.7 Flash is already routed to 3.8), so keep the
model name in config, never hard-coded.

## Ghana-specific notes
- **Latency**: Frankfurt is about 5,000 km from Accra. API calls are small,
  so it's fine; static files go through Cloudflare's edge.
- **Data costs for players**: mobile data is expensive. Compress clips on
  the phone before upload (720p is plenty: Pep shrinks frames to 1280 px
  anyway), and allow "upload on Wi-Fi".
- **Payments later**: mobile money (MTN MoMo, Telecel Cash) matters more
  than cards. Choose a payment provider with MoMo support when you
  monetise.
- **Data protection**: Ghana's Data Protection Act, 2012 (Act 843), applies
  to anyone processing personal data of people in Ghana. Data controllers
  must register with the Data Protection Commission *before* processing.
  Many of your players are minors, so parental consent and careful scout
  access are essential. See [09 · Making Pep better](09-improving.md).

---

## Workbook 03

**Exercises**

1. Deploy Pep to Render from `render.yaml` (Blueprint). Delete the worker
   block first if you'll use Modal. Open `/healthz`, `/readyz`, `/docs`.
2. Create an R2 bucket and token, set the `PEP_S3_*` variables, upload a
   clip in the Lab, and find the object in the R2 dashboard. Then open the
   presigned `videoUrl`, wait until it expires, and open it again.
3. `pip install modal`, `modal token new`, create the `pep-secrets`
   secret, then `modal deploy deploy/modal_app.py`. Queue a clip and watch
   the `drain` run in Modal's dashboard. Note the GPU seconds it used.
4. Put the Render URL behind a Cloudflare-proxied subdomain and add a rate
   limit rule on `/lab/clips` (e.g. 10 per minute per IP).

**Questions**

<details><summary>1. Why can't the worker save clips to its own disk on Render?</summary>

Render's filesystem is ephemeral: it's wiped on every deploy and restart,
and it isn't shared between instances. Other workers (or the API) could
never see the file. Object storage is shared and durable.
</details>

<details><summary>2. When would a fixed GPU VM be cheaper than Modal?</summary>

When it's busy most of the time. A serverless GPU costs more per hour than
a dedicated one, but nothing when idle. If the GPU would be busy more than
roughly the price ratio (often around 40–60% of the time), a dedicated
machine wins.
</details>

<details><summary>3. What is egress, and why does it matter more for Tracka than for a text app?</summary>

Egress is data leaving the provider's network to the internet. Video is
large and downloaded repeatedly (by workers, Gemini and scouts' browsers),
so per-GB egress fees would dominate the bill. R2 charges nothing for it.
</details>

<details><summary>4. What's the difference between /healthz and /readyz, and which should a load balancer use?</summary>

Liveness (`/healthz`): the process is running. Restart it if this fails.
Readiness (`/readyz`): it can serve traffic now (the database is
reachable). Load balancers and deploy switch-over should use readiness, so
traffic never goes to an instance that can't do its job.
</details>
