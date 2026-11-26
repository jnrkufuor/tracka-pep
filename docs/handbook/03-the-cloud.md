# 03 · The cloud

## The idea

"The cloud" just means **computers in someone else's data centre that
you rent by the hour, minute or second**. Instead of buying a server and
keeping it in a cupboard, you ask a provider for computing power,
storage or a database, and pay for what you use.

The key question is **how much do you manage yourself?** A comparison
with food:

| Level | Food version | You manage | Examples |
|---|---|---|---|
| **On-premises** | Grow and cook everything | Everything, including the building | Your own servers |
| **IaaS** (Infrastructure as a Service) | Rent a kitchen | Operating system, software, updates | AWS EC2, Google Compute Engine, DigitalOcean |
| **PaaS** (Platform as a Service) | Use a catering kitchen with staff | Just your code | Render, Heroku, Fly.io, Railway |
| **Serverless** | Order a meal when you're hungry | Just functions; nothing runs when idle | AWS Lambda, Cloudflare Workers, Modal |
| **SaaS** (Software as a Service) | Eat at a restaurant | Nothing, you just use it | Gmail, GitHub, Gemini API |

The less you manage, the faster you move, but the less control you have
and (usually) the more each unit costs. Small teams should manage as
little as possible.

## The common approaches

### Containers and Docker
A **container** packages your program *together with* everything it
needs (Python version, libraries, ffmpeg) into one **image**. The same
image runs identically on your laptop, in testing and in production. "It
works on my machine" stops being a problem. **Docker** is the standard
tool for building and running containers; a **Dockerfile** is the recipe.

### Kinds of hosting

| Kind | What it's for | Examples |
|---|---|---|
| **App platforms (PaaS)** | Run your API and background workers | Render, Fly.io, Railway, Heroku |
| **Serverless GPUs** | Rent a GPU only while a job runs | Modal, RunPod, Replicate |
| **Object storage** | Store big files cheaply | Cloudflare R2, AWS S3, Backblaze B2 |
| **Managed databases** | Someone else runs backups, upgrades and failover | Render Postgres, Supabase, Neon, AWS RDS |
| **Static hosting + CDN** | Serve websites made of fixed files from servers near users | Cloudflare Pages, Netlify, Vercel |
| **CDN / edge network** | Copies of your content in hundreds of cities; also security (TLS, firewalls, rate limits) | Cloudflare, Fastly, CloudFront |

### Words that decide the bill
- **Compute**: CPU/GPU time. **Egress**: data leaving the provider's
  network (downloads), often surprisingly expensive for video. **Storage**:
  gigabytes per month. **Requests**: per million API calls.
- **Always-on vs scale-to-zero**: an always-on server costs the same busy
  or idle; a serverless function costs nothing when idle but has **cold
  starts** (a few seconds to wake up).
- **Regions**: data centres in particular places. Closer to users means
  faster; data laws can require particular places.

### Infrastructure as code
Instead of clicking around dashboards, you describe your servers,
databases and settings in a file that lives in git (Render's
`render.yaml`, Terraform, Pulumi). Changes are reviewed like code, and
you can rebuild everything from scratch.

## How Tracka does it

| Piece | Where | Why there |
|---|---|---|
| Pep API | **Render** web service, Frankfurt (`render.yaml`, `Dockerfile`) | PaaS: deploys from GitHub, HTTPS, health checks, rollbacks. Frankfurt is Render's closest region to Ghana. |
| Database | **Render Postgres**, Frankfurt | Managed backups; same region as the API, so they talk privately and fast |
| GPU workers | **Modal** (`deploy/modal_app.py`) | Pay per second of GPU; scale to zero overnight; a hard cap of 4 GPUs |
| Video files | **Cloudflare R2** | S3-compatible with **zero egress fees**: videos are downloaded a lot |
| The web app | **Cloudflare Pages** (`.github/workflows/app.yml`) | The Flutter web build is static files; Pages serves them from a city near the player |
| The phone apps | Google Play / Apple App Store (later) | Installed on phones; they talk to the API |
| AI coach | **Gemini API** (SaaS) | A frontier video model without running one ourselves |

Details worth knowing:
- **Render's disk is temporary**: anything written there disappears on
  the next deploy. That's why videos go to R2.
- **Free plans sleep** after 15 minutes idle and the free database
  expires after 30 days. Use paid Starter plans for real players.
- **Two Dockerfiles**: `Dockerfile` (the small API image, no AI
  libraries) and `Dockerfile.worker` (PyTorch, YOLO, ffmpeg). The API
  stays small and fast to deploy; only workers carry the heavy AI stack.
- **Presigned URLs**: the app and workers download videos straight from
  R2 with temporary signed links, so video bytes don't pass through the
  API.
- **Modal's two entry points**: `drain()` runs every 2 minutes and
  processes queued clips; `kick()` lets the API wake workers right after
  an upload.

### Push notifications: a service account signs its own token (pep/players/push.py)

To send a push, the API proves to Google who it is. It signs a short JWT with
the Firebase service account's private key, swaps it for an access token that
lasts an hour, and caches it. That's the **OAuth 2.0 service-account flow**. The
key lives only in an env var (`PEP_FCM_SERVICE_ACCOUNT`); the app gets only
non-secret ids at build time. Setup steps: `docs/PUSH_SETUP.md`.

## Words to know
cloud · IaaS · PaaS · serverless · SaaS · container · image · Dockerfile ·
region · egress · cold start · scale to zero · CDN · edge · static
hosting · object storage · managed database · infrastructure as code ·
presigned URL

## Workbook 03

**Try it**
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

**Questions**

**1. Why is Tracka's API on a PaaS (Render) and not a rented virtual
machine?**

*Answer:* A PaaS handles the operating system, HTTPS, restarts,
deployments and rollbacks. For a small team, that time is better spent on
the product. A VM gives more control, but you become the system
administrator.

**2. When would an always-on GPU be cheaper than Modal?**

*Answer:* When it's busy most of the time. Serverless costs more per hour
but nothing when idle, so above roughly half-time use a dedicated GPU
usually wins.

**3. What is egress, and why does it matter so much for a video app?**

*Answer:* Egress is data downloaded out of the provider. Videos are large
and get downloaded repeatedly (by workers, the app, later scouts), so
per-gigabyte egress fees would dominate the bill. R2 charges none.

**4. Why does the API image leave out PyTorch?**

*Answer:* The API doesn't run AI models. A smaller image builds and
deploys faster, uses less memory, and has fewer things that could have
security holes.
