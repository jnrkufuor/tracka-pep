# 07 · From numbers to fair scores

A raw number means nothing until you say *compared with whom*. Pep compares each player with players their own age and sex, shows a band (Below average to Standout) instead of a score out of 100, and says how sure it is.

## The idea

"Top speed 8.1 m/s." Is that good? For a 12-year-old, brilliant. For a professional winger, ordinary. Turning measurements into fair, explainable scores is mostly statistics, not AI.

A **norm** describes what's typical for a group (say, boys aged 15–16): its **mean** (average) and **standard deviation** (SD: how spread out values are).

- A **z-score** says how many SDs above or below typical you are: (your value − mean) / SD. z = 0 is average; z = +1 beats about 84% of the group; z = +2 about 98%.
- A **percentile** is the share of the group you beat.
- Some measures are **lower is better** (sprint times): flip the sign.
- Some have a **long tail** (keepy-ups: most do 10, a few do 500). Compare their **logarithms**, so one superstar doesn't squash everyone else together.

## The usual ways to do it

| Approach | How | Good | Bad |
| --- | --- | --- | --- |
| **Rules (weighted sums)** | Experts choose weights: Pace = 60% top speed + 40% 10 m split | Explainable; works with no data | Weights are opinions |
| **Learned model** | Learn weights from expert ratings (chapter 05) | Matches what coaches actually value | Needs lots of labelled data |
| **Hybrid** | Rules first; a learned model once there's enough data; rules stay as a check | Best of both | More moving parts |

Two more ideas every scoring system needs:

- **Honesty about uncertainty.** A score from a shaky 10-second clip shouldn't look as certain as one from a careful drill. Good systems show **confidence** next to each score, refuse to score when the evidence is too thin, and don't claim more precision than they have.
- **Fairness.** Scores shape opportunities. Compare by age and sex, don't punish players for what the camera did (bad light, far away), and check for groups the system scores lower for no good reason.

## What we chose and why

- **Norms by age band and sex**, starting from published youth-football research, to be replaced with our own players' data as it grows. Comparing a 13-year-old with adults would be meaningless and discouraging.
- **Bands, never a 0–100 overall score.** Each area gets a band: Below average (under the 30th percentile), Average (30–60), Above average (60–80), Strong (80–93), Standout (93+). A number like "62" hides what was measured and invites "I'm bad". "Above average · 10 m in 1.92 s · high confidence · growing" says what Pep saw, how it compares, how sure it is and which way it's going, and each part can be checked.
- **Confidence is earned.** Timed tests reach high confidence after 2 clips (same task, real metres from the cones); match clips need 4 (they vary much more).
- **Say what Pep can't see.** Areas with no measurement say *Not seen yet*, *Coming later* or *Pep can't see this*, instead of guessing.
- **Hybrid scoring.** Rules from norms today; the learned scorer joins once coaches have rated enough clips, and only if it beats the rules on players it hasn't seen.
- **Role fit with coverage.** Each role (inside forward, box-to-box midfielder…) weights skills differently. **Coverage** says how much of a role's weight was actually measured, so Pep never suggests "playmaker" from pace alone.

## How it's set up

| Piece | Where |
| --- | --- |
| Norms (u13, u15, u17, u20, senior) | `pep/data/norms.json`, `pep/scoring/norms.py`, rebuilt by `training/build_norms.py` |
| Skills from measurements | `pep/scoring/skills.py` |
| Role fit and coverage | `pep/scoring/roles.py`, `pep/data/roles.json` |
| Skill areas, bands, confidence, trend | `pep/players/skill_areas.py`, `pep/data/skill_areas.json` |
| Progress in plain words ("about 2 metres ahead") | `pep/players/progress.py` |
| The learned scorer | `pep/scoring/learned.py` |

## Words to know

norm · mean · standard deviation · z-score · percentile · log scale · weighted sum · band · confidence · coverage · trend · fairness · measurement bias

## Workbook 07

**Try it**

1. In `pep/data/norms.json`, find the u17 values for `top_speed_ms` (mean 7.6, SD 0.6). Work out the z-score and percentile of 7.8 m/s by hand, then check with `pep/scoring/norms.py`.
2. Change one weight in `pep/data/roles.json` and run `pytest tests/test_scoring.py`. Which tests notice?
3. In `tests/test_skill_areas.py`, add a test for a U17 midfielder with head checks of 9, 8 and 3 a minute (newest first). Predict the band, confidence and trend before you run it.
4. Ask: who might our norms be unfair to? (Hint: where did the research data come from?)

**Questions**

**1. Two players both run 7.5 m/s. One is 13, one is 19. Why can their Pace differ?**

*Answer:* Each is compared with players their own age. 7.5 m/s is well above average at 13 and below average at 19.

**2. Why compare keepy-ups on a log scale?**

*Answer:* A few people do hundreds. On a normal scale they'd stretch the SD and squash everyone else together. Logs make "10 → 20" count about as much as "100 → 200".

**3. Why bands instead of a score out of 100?**

*Answer:* A phone clip can't measure precisely enough to separate a 71 from a 72, and a single low number can crush a young player for what might be a camera problem. A band plus the measured value is honest and checkable.

**4. What does a role's coverage protect against?**

*Answer:* Recommending a role based on skills that were never measured.

## More practice

Exercises added as features were built. Each one points at real code.

1. Open `pep/data/norms.json` and find the u17 values for `top_speed_ms`
   (mean 7.6, SD 0.6). Work out by hand the z-score and percentile
   of 7.8 m/s, then check with the functions in
   `pep/scoring/norms.py`.
2. Change one weight in `pep/data/roles.json` and run `pytest
   tests/test_scoring.py`. Which tests notice?
3. Run `python scripts/seed_demo.py`, log in as the demo player, and
   explain to a friend why Agility is the top skill and Scanning the focus.
4. Ask: who might Pep's norms be unfair to? (Hint: where did the research
   data come from?)
5. In `tests/test_skill_areas.py`, add a test for a U17 midfielder with
   head checks of 9, 8 and 3 a minute (newest first). Predict the band,
   confidence and trend before you run it.
6. In `pep/players/progress.py`, the sprint card says "about 2 metres
   ahead". Work out the formula by hand for 4.9 s → 4.6 s over 30 m, then
   check it against `test_sprint_progress_in_plain_words`.
