# 08 · Cost: what a clip costs, and the levers

All prices are list prices as of November 2026, in USD. They change: check
the providers' pricing pages before budgeting.

## The fixed monthly floor

| Item | Plan | Approx. / month |
|---|---|---|
| Render web service (Pep API) | Starter, 512 MB | $7 |
| Render Postgres | Basic-256mb | $6 (+ storage at $0.30/GB) |
| Cloudflare R2 | first 10 GB free, then $0.015/GB-month, egress free | $0–5 at first |
| Modal | per-second; Starter workspaces include $30 of compute a month | $0 while within credit |
| **Floor** | | **≈ $13–20** |

Optional: a Render CPU worker on the Standard plan (2 GB RAM) at about $25
a month instead of, or as well as, Modal.

## Per-clip variable cost (a 30-second clip)

**GPU time.** At 10 samples per second, 30 s = 300 frames. Two YOLO
passes per frame on an L4 GPU take on the order of 10–20 ms, so about
5–10 s of GPU time, plus ~20 s overhead (download, model load in a fresh
container, ffmpeg).
Modal's L4 is about $0.000222 per second (≈ $0.80/hour), so **roughly
$0.005–0.01 per clip** (half a cent to a cent) when containers are warm.
Cold starts add a few seconds each.

**CPU alternative.** On this kind of CPU, perception measured about
0.25 s per frame: 300 frames ≈ 75 s. On a $25/month always-on worker,
that's about 30,000 clips a month of capacity if the queue is always full.
Cheaper per clip at steady volume; slower for each player.

**Gemini coach.** Gemini 3.8 Flash's introductory price is $0.75 per
million input tokens and $3.75 per million output tokens, until 31 December
2026. Video is tokenised at roughly a few hundred tokens per second, so a
30 s clip plus prompt is on the order of 10–20k input tokens plus ~1k
output: **about 1–2 cents per clip**. It's the biggest variable cost.
Levers: lower video resolution or fps, the Batch API for non-urgent
clips, or only calling the coach for clips the player chose to "get
coached".

**Storage.** A 30 s 720p clip is ~10–20 MB. 10,000 clips ≈ 150 GB ≈
$2.25 a month on R2, with free downloads. A 60-day lifecycle rule keeps it
flat.

## Worked example: 5,000 clips a month

| | |
|---|---|
| Render API + DB | ~$13 |
| Modal GPU (5,000 × ~$0.01, after the $30 credit) | ~$20 |
| Gemini (5,000 × ~$0.015) | ~$75 |
| R2 (~75 GB) | ~$1 |
| **Total** | **≈ $110 / month ≈ 2 cents a clip** |

## Cost levers, in order of impact
1. **Coach on demand.** Run Gemini only when a player asks for notes, or
   for drills and longer clips.
2. **Fewer frames.** `PEP_SAMPLES_PER_SECOND=6` cuts GPU time by 40%;
   tracking still works for most clips.
3. **Smaller models.** `yolo26n` for the ball is faster but misses more
   balls: measure the difference with `evaluate.py` before switching.
4. **Batching.** One warm GPU container draining 20 clips beats 20 cold
   starts (that's what `drain()` does).
5. **Spend caps.** `max_containers` on Modal; budget alerts on Gemini.

## Workbook 08
1. Run 10 clips through a deployed Modal worker and read the real GPU
   seconds per clip from Modal's dashboard. Recompute the table above with
   your numbers.
2. Add `coach_input_tokens` to the result's metrics (the Gemini response
   includes usage metadata) so cost per clip appears in the Lab.

<details><summary>Why is the AI coach, not the GPU, the main cost?</summary>

YOLO on a GPU is extremely efficient per frame (milliseconds). A frontier
LLM processing video tokens is far heavier compute, and it's priced
accordingly.
</details>
