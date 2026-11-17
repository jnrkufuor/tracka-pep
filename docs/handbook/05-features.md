# 05 · Features and predictors: every measurement Pep makes

A **feature** (or **predictor**, or **variable**) is a number computed from
the clip that we believe carries information about the player. Choosing
features well matters more than choosing models: a great model can't
recover information the features threw away, and a bad feature (noisy,
biased, leaky) poisons everything downstream.

For each feature: what it is, its unit, how it's computed, why it matters
for football, and its known pitfalls.

## Movement (`metrics/kinematics.py`)

| Feature | Unit | Definition | Why it matters | Pitfalls |
|---|---|---|---|---|
| `top_speed_ms` | m/s | Best **1-second average** of smoothed speed | Pace: the most-asked-about attribute in scouting | A single-frame max would be a glitch. Body-ruler error is ±10–15%. Short clips may not include a sprint. |
| `top_speed_at` | s | When it happened | Shown as a moment in the app | |
| `peak_accel_ms2` | m/s² | Max rate of change of the half-second-averaged speed | Acceleration over the first 5–10 m wins more duels than top speed | Very sensitive to noise; trust drill splits more |
| `distance_m` | m | ∫ speed dt | Volume of work | Only counts tracked time |
| `distance_per_min_m` | m/min | distance / tracked minutes | Work rate, comparable across clip lengths | Inflated in short, intense clips |
| `moving_share` | 0–1 | Share of time faster than 2 m/s (a jog) | Engagement and work rate | Depends on what the clip shows (a highlight is all action) |
| `high_speed_share` | 0–1 | Share of time faster than 5.5 m/s (19.8 km/h, the usual "high-speed running" line) | Intensity | |
| `high_speed_runs` | count | Runs of 1 s or more above 5.5 m/s | Repeated sprint ability | |
| `turns_per_min` | /min | Heading changes ≥ 45° within 0.8 s while above 2.5 m/s | Agility, change of direction | Needs ≥ 8 s of running, or it's not scored |
| `seconds_tracked` | s | Time the player was seen | Evidence for confidence | |

## Ball (`metrics/ball.py`)
Distances are measured in **body heights** (scale-free: works near and far)
and converted to metres where the scale is known.

| Feature | Unit | Definition | Why | Pitfalls |
|---|---|---|---|---|
| `ball_at_feet_share` | 0–1 | Of frames with the ball within 2 body heights, the share within 0.6 | Control, keeping possession | No ball height from one camera: an aerial ball "near" the feet in the image may be in the air |
| `touches_per_min` | /min | Ball changes direction > 60° while at the feet | Involvement, dribbling style | Missed ball detections hide touches |
| `close_control_m` | m | Median feet-to-ball gap while running (> 3 m/s) with the ball | Dribbling tightness (lower = better) | Needs the ball detected while running |
| `heavy_touches` | count | Ball goes from at the feet to more than 2.5 m away within 0.6 s while running | Touch quality | Could be a deliberate push into space |

## Body (`metrics/technique.py`, pose keypoints)

| Feature | Unit | Definition | Why | Pitfalls |
|---|---|---|---|---|
| `ready_knee_deg` | degrees | Median knee angle while nearly still (lower = more bent) | "Ready position": quicker reactions | Camera angle distorts 2-D angles |
| `sprint_lean_deg` | degrees | Torso angle from vertical while above 5 m/s | Acceleration mechanics (about 10–25° is good early in a sprint) | Not yet scored, only reported. Needs a side-on view. |
| `head_checks_per_min` | /min | Head turns > 0.35 shoulder-widths and back | Scanning: elite midfielders look around constantly | Crude, front-on views only, so confidence is always LOW |

## Goalkeeping (`metrics/goalkeeping.py`)

| Feature | Unit | Definition |
|---|---|---|
| `dives` | count | Hip centre drops below 22% of standing height after being above 40% within 0.7 s |
| `dive_speed_ms` | m/s | Peak sideways hip speed during a dive |
| `set_share` | 0–1 | Share of the clip still with knees bent below 160° |

## Drills (`drills/runner.py`), the fairest features

| Feature | Unit | How it's timed |
|---|---|---|
| `sprint_30m_s` | s | From moving 20 cm off the start (like timing gates) to crossing 30 m, interpolated between frames |
| `split_10m_s` | s | Same start, to 10 m |
| `agility_5105_s` | s | Start → both turn lines visited → back through the middle |
| `juggles_best` | count | Longest run of bounces (local lowest points of the ball) before it reaches foot level |
| `wall_passes_30s` | count | Ball returns to the feet after being far away, in the first 30 s |

**Interpolation trick.** At 10 samples per second, crossing a line
"between frames" is a 0.1 s uncertainty. Linear interpolation between the
two samples either side cuts it to a few hundredths. See `crossing_time`.

## Quality features (how much to trust the rest)

| Feature | Meaning |
|---|---|
| `camera_reliability` | Share of frames where camera motion was measured |
| `seen_share` | Share of frames where the target player was found |
| `ball_frames`, `pose_frames` | Evidence counts |

## Context features (how to *interpret* the rest)
`age_years`, `sex`, `clip_type` (match / training / drill / highlight),
`calibrated` (homography or not). A 7.5 m/s sprint is excellent at 13 and
ordinary in a senior pro. A highlight reel flatters everyone. Context
features let norms and the learned scorer read the same numbers differently.

## The learned scorer's predictors
`pep/scoring/learned.py → FEATURES`: all of the above that are numeric,
plus the context. The order matters (the model sees a vector), so the saved
model stores the list and refuses to load if it changed. Change the list →
retrain.

## Choosing features: principles you can reuse
1. **Physically meaningful first.** Speed in m/s beats "pixels per frame".
2. **Scale-free where you can.** Body heights work at any zoom.
3. **Robust statistics.** Medians and best-1-second averages, not single
   frames.
4. **Measure evidence.** Every metric has a minimum amount of data before
   it's reported (`None` otherwise). A missing value is honest; a made-up
   one isn't.
5. **No leakage.** Never feed the model anything that contains the answer
   (e.g. the scout's notes, or another scout's rating of the same clip).
6. **Version everything.** Change a threshold → bump `MODEL_VERSION`.

---

## Workbook 05

**Exercises**

1. Add `max_decel_ms2` (hardest slowing down) to `_summarise` in
   `kinematics.py`, with a test. Why might deceleration matter for
   defenders and injury risk?
2. Add `sprint_lean_deg` as a scored part of "Acceleration" (a *target
   band*, not "higher is better": score by distance from 18°). You'll need
   a new norm type in `norms.py`.
3. `touches_per_min` uses a 60° direction change. Make it 45° and 75°, run
   a real clip, and compare with a count you do by eye.
4. Add `weak_foot_share` using pose: which ankle is nearest the ball at
   each touch? What could go wrong?

**Questions**

<details><summary>1. Why is top speed the best 1-second average rather than the maximum frame?</summary>

Single frames carry noise and tracking glitches (an ID switch can teleport a
player). A one-second window needs sustained speed, which only a real
sprint produces. Players also can't physically hold a glitch speed for a
second.
</details>

<details><summary>2. Why measure ball distance in body heights?</summary>

Pixels mean different real distances at different zooms and depths. A body
height is a ruler that's always beside the ball: 0.6 body heights is about
1 m whether the player fills the frame or is tiny in the distance.
</details>

<details><summary>3. Give an example of a feature that would leak the label.</summary>

Using "was this clip in a scout's shortlist?" to predict the scout's
rating, or the average rating other scouts gave the same clip. Both are
partly the answer itself. The model would look brilliant in validation and
be useless on new clips.
</details>

<details><summary>4. Why is `clip_type` a feature at all?</summary>

The same numbers mean different things in different contexts: a highlight
reel is selected for best moments (inflated), and a drill is standardised
(fair). Without it, the learned scorer would mix these populations and be
biased toward players who upload highlights.
</details>
