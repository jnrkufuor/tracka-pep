# 07 · From numbers to scores

## The idea

"Top speed 8.1 m/s." Is that good? For a 12-year-old, brilliant. For a
professional winger, ordinary. A raw number means nothing until you say
**compared with whom**. This chapter is about turning measurements into
fair, explainable scores, which is mostly statistics, not AI.

## The common approaches

### Comparing with a group: norms
A **norm** describes what's typical for a group (say, boys aged 15–16):
its **mean** (average) and **standard deviation** (SD: how spread out
values are).

- **z-score** = (your value − mean) / SD. "How many SDs above or below
  typical are you?" z = 0 is average; z = +1 is better than about 84% of
  the group; z = +2 better than about 98%.
- **Percentile**: the share of the group you beat. If values are roughly
  bell-shaped (**normally distributed**), the percentile comes straight
  from z.
- Some measures are **lower is better** (sprint times): flip the sign.
- Some have a **long tail** (keepy-ups: most people do 10, a few do
  500): compare **logarithms** so one superstar doesn't distort
  everything.

Norms come from published research, from your own data once you have
enough, or both.

### Combining numbers into a score

| Approach | How | Good | Bad |
|---|---|---|---|
| **Rules / weighted sums** | Experts choose weights: Pace = 60% top speed + 40% 10 m split | Explainable; works with no data | Weights are opinions |
| **Learned model** | Learn weights from expert ratings (chapter 05) | Matches what coaches actually value | Needs lots of labelled data |
| **Hybrid** | Rules first; learned model when there's enough data; keep rules as a check | Best of both | More moving parts |

### Being honest about uncertainty
A score from a 10-second shaky clip shouldn't look as certain as one from
a careful drill. Good systems report **confidence** alongside the score,
and refuse to score at all when the evidence is too thin. Also: don't
claim more precision than you have. A phone clip can't honestly separate
a 71 from a 72, or call anyone a 5 or a 100.

### Fairness
Scores shape opportunities, so check they're fair: compare by age and
sex, don't penalise players for things the camera did (bad light, far
away), and watch for groups the model scores systematically lower.

## How Tracka does it

1. **Norms by age band and sex** (`pep/data/norms.json`, loaded in
   `pep/scoring/norms.py`): u13, u15, u17, u20, senior, with a scale
   factor for girls and women. Built from published youth-football
   research to start (`training/build_norms.py` rebuilds them),
   to be replaced with Ghanaian players' own data as it grows.
2. **Measurement → percentile → 30–95**: never below 30 or above 95, by
   design.
3. **Skills** (`pep/scoring/skills.py`): each skill (Pace, Acceleration,
   Agility, Work rate, Ball control, Dribbling, Body shape, Scanning, and
   goalkeeping ones) is a weighted mix of its measurements, with a
   **confidence** from how it was measured (drill vs match, how long the
   player was tracked). Not enough evidence → the skill is left out.
4. **Role fit** (`pep/scoring/roles.py`, `pep/data/roles.json`): each
   role (inside forward, target forward, box-to-box midfielder…) weights
   skills differently. **Coverage** says how much of that role's weight
   we actually measured; a role is only suggested if coverage is high
   enough.
5. **Overall score**: built from the roles for the player's own positions.
6. **The player's dashboard** (`pep/players/coach.py`): the average of the
   newest 5 clips, needing at least 3, with trend, strengths, the focus
   skill, a suggested drill for it, and best-fitting roles (the
   player's own positions first).
7. **Learned scorer** (`pep/scoring/learned.py`): switched on only once
   coaches have rated enough clips (chapter 05).

## Words to know
norm · mean · standard deviation · z-score · percentile · normal
distribution · log transform · weighted sum · confidence · coverage ·
fairness

## Workbook 07

**Try it**
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

**Questions**

**1. Two players both run 7.5 m/s. One is 13, one is 19. Why can their
Pace scores differ?**

*Answer:* Each is compared with players their own age. 7.5 m/s is well
above average for 13-year-olds and below average for 19-year-olds.

**2. Why compare keepy-ups on a log scale?**

*Answer:* The counts have a long tail: a few people do hundreds. On a
normal scale, those few would stretch the SD and squash everyone else
together. Logs make "10 → 20" count about as much as "100 → 200".

**3. Why cap scores at 30–95?**

*Answer:* A phone clip can't measure precisely enough to justify extreme
scores, and a "5" can crush a young player for what might be a camera
problem.

**4. What does a role's "coverage" protect against?**

*Answer:* Recommending a role based on skills we never measured. If only
pace was measured, Pep shouldn't call someone a great playmaker.
