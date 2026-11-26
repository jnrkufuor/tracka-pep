# 00 · Start here

Welcome to Tracka. This handbook explains how Tracka is built and why we built it this way. Each chapter starts with the general idea (how anyone would solve the problem), then shows what we chose and why. You don't need to know any of it before you start.

## Who we are

Tracka helps young footballers get better and get seen, starting in Ghana. A player films themselves (a match, a drill, a sprint) on their phone and uploads the clip. **Pep**, our AI coach, watches it, measures how they move and play, compares them with players their age, and tells them what to practise next. A separate app for **scouts** comes later and will use the same backend.

Three promises shape almost every technical decision in this handbook:

- **Numbers come from measurement, not from an AI's guess.** Speeds, times and scores are measured from the video. The language model only writes the words.
- **Most players are children.** Safety and privacy come first: guardian approval, no private messages, only a shirt name shown to others.
- **Phones and data in Ghana are often slow and costly.** The app saves work offline, uploads when it can, and never loses a clip.

## The parts, in one table

| Part | What it does | Where in the code |
| --- | --- | --- |
| The app | One Flutter codebase that builds the Android app, the iPhone app and the website | `app/` |
| The API (backend) | The server the app talks to: logins, profiles, clips, Pep's results | `pep/players/`, `pep/api/` |
| The workers | Programs that analyse clips with AI, on machines with GPUs | `pep/pipeline.py`, `pep/worker.py` |
| The database | Every account, profile, clip record and result | Postgres (tables in `pep/db.py` and `pep/players/`) |
| File storage | The video files themselves | Cloudflare R2 |
| Pep Lab | A staff-only console: test clips, rate them, moderate Pitchside, watch system health | `web/` |
| Training tools | Scripts that make Pep more accurate over time | `training/` |

## How each chapter works

1. **The idea**: the concept in plain words, with an everyday comparison.
2. **The usual ways to do it**: the main options people choose between, and when each fits.
3. **What we chose and why**: our decision, the reasons, and what we gave up.
4. **How it's set up**: the files to open, so you can read real code next to the idea.
5. **Words to know** and a **workbook**: things to try, and questions with answers.

## Reading order

| # | Chapter | The question it answers |
| --- | --- | --- |
| 01 | How software talks | How does an app on a phone get data from a server? |
| 02 | Designing the system | How do you split a product into parts that work together and survive failure? |
| 03 | The cloud | Where do the parts actually run, and why do we need GPUs? |
| 04 | Shipping code safely | How does code get from a laptop to players without breaking things? |
| 05 | Machine learning | How does a computer learn from examples? |
| 06 | Computer vision | How does a computer turn a video into speeds and distances? |
| 07 | From numbers to fair scores | How do you turn measurements into scores that are fair and honest? |
| 08 | Language models | How do we use an AI that writes, safely? |
| 09 | The app | How do you build one app for Android, iPhone and the web? |
| 10 | Reliability and safety | How do you keep it working, and know when it isn't? |
| 11 | The Python toolbox | Which Python habits show up everywhere in our code? |
| 12 | Cost, privacy and what's next | What does it cost, what does the law ask, and how will Pep get better? |

## Run it on your laptop

Everything runs on one laptop, with no cloud accounts. One process plays the API and the worker at once.

```bash
git clone https://github.com/jnrkufuor/tracka-pep && cd tracka-pep
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev,vision,coach,train]"
cp .env.example .env            # PEP_INLINE_WORKER=true: one process does everything
pep serve                       # the API, plus Pep Lab at /lab, on http://localhost:8000
python scripts/seed_demo.py     # a demo player: demo@tracka.app / tracka-demo-123
pytest                          # the backend's tests

cd app                          # the app (install Flutter first: flutter.dev)
./tool/setup_platforms.sh
flutter run -d chrome --dart-define=PEP_API_URL=http://localhost:8000
```

**Tip:** do each workbook on its own branch (`git switch -c workbook-02`) and break things on purpose. Watching which tests catch what you broke teaches you the system faster than reading. When you finish a chapter, explain it out loud without looking. If you can draw it and say *why*, you understand it.

A map of every folder lives in `docs/CODEMAP.md` in the repo.

## At a glance

```
  The app ──HTTPS + JSON──► API (web tier) ◄──staff only── Pep Lab
  Flutter: Android,          Render, answers at once         rate, moderate,
  iPhone, web                     │            │             watch health
                       stores the clip     writes a job
                                  ▼            ▼
  File storage ◄──────────────────┘   Database + job queue ◄──claims jobs── Workers (worker tier)
  Cloudflare R2                       Render Postgres                       Modal GPUs, start per clip
        ▲                                                                        │      │
        └──────────── workers download the clip by signed link ─────────────────┘      ▼ words only
                                                                                   Gemini API
```

Each part only knows the agreed way to talk to its neighbour (chapter 02 calls this loose coupling). The queue in the middle is the hinge: the API answers the phone straight away, and the workers pick up clips when they're ready.
