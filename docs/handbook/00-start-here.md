# 00 · Start here

This handbook teaches the ideas behind Tracka: how apps talk to servers,
how systems are designed, how the cloud works, how code gets shipped, how
AI and computer vision work, and how to keep a service running. Each
chapter does three things, in this order:

1. **The idea**: what the concept is, in plain words, with an everyday
   comparison. No prior knowledge assumed.
2. **The common approaches**: the main ways people solve it, and when each
   one fits.
3. **How Tracka does it**: our choices, as a worked example, with the files
   to open.

Every chapter ends with a **workbook**: things to try, and questions with
answers. You learn by doing.

## Tracka in one page

Tracka is starting with **players**. A player downloads the app (or opens
the website), makes a profile, and uploads clips of themselves playing.
**Pep**, Tracka's AI coach, watches each clip, measures how they move and
play, compares them with players their age, and tells them what to
practise. Later, there will be a separate app for **scouts**, and
eventually the two will connect.

```
   Player's phone / browser                         Tracka's servers (the "backend")
 ┌──────────────────────────┐   HTTPS + JSON   ┌──────────────────────────────────────┐
 │  Tracka app (Flutter)    │ ───────────────► │  Pep API   (accounts, videos, scores)│
 │  Home · Videos · Pep ·   │ ◄─────────────── │     │                                │
 │  Chances · Profile       │                  │     ▼ job queue (Postgres)           │
 └──────────────────────────┘                  │  Pep workers (GPU): watch, measure,  │
                                               │  score, write coaching notes         │
                                               │     │                                │
                                               │     ▼ video files (Cloudflare R2)    │
                                               └──────────────────────────────────────┘
```

| Part | What it is | Where it lives in the code |
|---|---|---|
| The app | One Flutter codebase that builds the Android app, the iPhone app and the website | `app/` |
| Pep API | The server the app talks to: logins, profiles, videos, scores | `pep/players/`, `pep/api/` |
| Pep workers | The programs that analyse clips with AI | `pep/pipeline.py`, `pep/worker.py` |
| Pep Lab | A staff-only web console for testing clips, rating them and watching system health | `web/` |
| Training tools | Scripts that improve Pep over time | `training/` |

## Reading order

| # | Chapter | The big question |
|---|---|---|
| 01 | How software talks | How does an app on a phone get data from a server? |
| 02 | Designing a system | How do you split a product into parts that work together and survive failures? |
| 03 | The cloud | Where do the servers actually run, and who manages them? |
| 04 | CI/CD | How does code get from a laptop to users safely, many times a day? |
| 05 | Machine learning | How does a computer learn from examples? |
| 06 | Computer vision | How does a computer understand a video? |
| 07 | From numbers to scores | How do you turn measurements into fair, honest scores? |
| 08 | Large language models | How do you use an AI like Gemini inside a product, safely? |
| 09 | Mobile and web apps | How do you build one app for Android, iPhone and the web? |
| 10 | Reliability (SRE) | How do you keep a service working, and know when it isn't? |
| 11 | Python toolbox | Python features worth knowing, from this codebase |
| 12 | Cost, privacy and what's next | What it costs, the law, and how to make Pep better |

## Run everything on your laptop

```bash
git clone https://github.com/jnrkufuor/tracka-pep && cd tracka-pep
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev,vision,coach,train]"
cp .env.example .env            # PEP_INLINE_WORKER=true: one process does everything
pep serve                       # the API (+ Lab console at /lab) on http://localhost:8000
python scripts/seed_demo.py     # optional demo player: demo@tracka.app / tracka-demo-123
pytest                          # the backend's tests

cd app                          # the Flutter app (install Flutter first: flutter.dev)
./tool/setup_platforms.sh
flutter run -d chrome --dart-define=PEP_API_URL=http://localhost:8000
```

## How to use this handbook

- **Read the idea first, then open the file.** Every "How Tracka does it"
  section names the files. Reading real code next to the explanation is
  the fastest way to learn.
- **Do the workbook on a branch** (`git switch -c workbook-02`). Break
  things on purpose; see which tests catch it.
- **Explain it back.** After each chapter, explain the idea to someone (or
  out loud) without looking. If you can draw it and say *why*, you
  understand it.
