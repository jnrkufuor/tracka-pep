# 06 · Scoring: from measurements to scores scouts can trust

```
metrics ──► norms (z, percentile) ──► skill scores (30–95) + explanation + drill + confidence
                                                │
                     AI-observed skills (LOW) ──┤
                                                ▼
                                   role fit (weighted, with coverage)
                                                │
                     learned scorer (if trained) ┤ blend
                                                ▼
                                overall score + overall confidence
```

## 1. Norms: compared with whom?
`pep/data/norms.json` gives, per measurement and age band (u13, u15, u17,
u20, senior), a typical value (mean) and spread (standard deviation).

```
z = (value − mean) / sd                 standard deviations from typical
z = −z            if lower is better (times)
z = (ln(1+value) − ln(1+mean)) / sd   for long-tailed counts (keepy-ups)
percentile = Φ(z) × 100                 Φ = normal CDF: the share of players you'd beat
score = 30 + 0.65 × percentile          → 30 (bottom) … 62.5 (typical) … 95 (top)
```

Why 30–95: from a phone clip we can't honestly call anyone a 5 or a 100.
z is clamped at ±3.5: beyond that a measuring error is likelier than a
prodigy.

**The norms are starter priors** from typical published youth ranges, not
Ghanaian data, and not measured Pep's way. Replace them with
`training/build_norms.py` once you have a few hundred players per band. It
uses **robust statistics** (median and MAD, the median absolute deviation),
and counts each player once (their best clip) so one prolific uploader
can't define "normal".

## 2. Skills (`scoring/skills.py`)
Each skill = one or more metrics (weighted), compared with norms, plus:
- **explanation**: what was measured, with the number and the percentile;
- **drill**: chosen by band (< 55 / 55–74 / 75+), so advice fits level;
- **source**: `drill` > `measured` > `ai_observed`;
- **confidence**: starts HIGH and steps down for each reason to doubt it.

| Reason | Effect |
|---|---|
| Not a standard drill | −1 |
| Distance-based metric without a homography | −1 |
| Camera motion poorly measured (< 60%) | −1 |
| Highlight clip | −1 |
| Age unknown | capped at MEDIUM |

If a drill measured a skill, the drill version wins over the clip estimate.

## 3. Role fit (`scoring/roles.py`, `pep/data/roles.json`)
Scouts search by role. Each role weights skills:

```
role_fit = Σ wᵢ·sᵢ·trustᵢ / Σ wᵢ·trustᵢ     over skills we have
coverage = Σ wᵢ (skills we have) / Σ wᵢ (all)
trust = 1 (measured or drill), 0.5 (AI-observed)
```

**Coverage is the honesty number.** "Inside forward 74, saw 55% of the
role" tells a scout this is a partial picture. The Lab only ranks a player
for a role when coverage is at least 35%.

The **overall score** Tracka shows is the best role fit among roles for
the player's *own* positions (coverage ≥ 35%), else the average of the
measured skills. **Overall confidence** is the median skill confidence,
dropped to LOW if we saw less than half of any of their roles.

The weights in `roles.json` are football opinions. Get a coach and a scout
to review them and record why.

## 4. The learned scorer and the blend
Once trained (chapter 04 §7), its prediction is averaged 50/50 with the
rules score, and the version becomes `pep-0.1.0+scorer-YYYYMMDD`. Why
blend rather than replace: the rules are explainable and stable; the
learned model agrees better with scouts. Half and half keeps both until the
learned model has proven itself on a lot of data.

## 5. Trust rules (shared with Tracka)
- Every score says how sure it is and how many clips it's from.
- Players can always dispute; a person reviews (tracka-api).
- AI observations are labelled and never set numbers.
- Clips can't be compared fairly unless they're the same test: push players
  towards **drills** for anything a scout will rank on.
- **Multiple clips beat one clip.** Tracka averages the newest 5 and won't
  show a score before 3.

## 6. Measuring whether scoring is any good (`pep/evaluation.py`)
Scouts rate clips in the Lab's **Calibrate** tab. Pep reports:
- **MAE**: the average gap in points ("within 6 points").
- **Bias**: does Pep score high or low overall?
- **Spearman ρ**: do Pep and scouts *rank* players the same way? For
  scouting, ranking matters most.
- **Within 10**: the share of clips where Pep is close.

Then measure **scout vs scout** on the same clips. That's the ceiling: Pep
can't be expected to agree with a scout more than scouts agree with each
other.

---

## Workbook 06

**Exercises**

1. A 16-year-old boy has a top speed of 8.2 m/s (band u17: mean 7.6, sd
   0.6). Work out z, the percentile and the score by hand, then check with
   `standing("top_speed_ms", 8.2, 16, "male")`.
2. Add a role "Ball-winning midfielder" to `roles.json` (CDM/CM:
   Defending, Work rate, Agility, Acceleration, Scanning). Upload a clip
   and find it in the role list.
3. Change confidence so that `seconds_tracked < 6` caps every skill at
   LOW. Add a test.
4. Rate 10 clips in the Lab yourself, then have a friend rate the same 10.
   Compute your agreement with each other and with Pep (`agreement` in
   `pep/evaluation.py`).

**Questions**

<details><summary>1. Why convert to percentiles instead of showing raw speed?</summary>

Raw numbers mean nothing without context. 7 m/s is great for an
11-year-old and ordinary for a senior. A percentile against the same age
band ("faster than 80% of U15 players") is meaningful to players and
scouts, and lets different skills share one scale.
</details>

<details><summary>2. When would the normal-distribution assumption be wrong, and what's the fix?</summary>

For skewed or bounded measurements: counts like keepy-ups (long right
tail) or shares near 0 or 1. Fixes: transform first (we use log for
keepy-ups), or use empirical percentiles from real data
(`build_norms.py` could store percentile tables instead of mean/sd).
</details>

<details><summary>3. A player scores 88 for "Poacher" with coverage 0.3. What should a scout conclude?</summary>

Very little yet. Pep saw only 30% of what defines that role (perhaps
acceleration, but not finishing or ball control). It's a lead worth a
look, not a rating. That's why the Lab doesn't rank roles below 35%
coverage.
</details>

<details><summary>4. Why is Spearman more important than MAE for scouting?</summary>

Scouts shortlist the best players for a role: getting the *order* right
matters more than matching each scout's personal scale. A model that's
always 5 points generous (bad MAE) but ranks perfectly is more useful than
one with a small MAE that shuffles the order.
</details>
