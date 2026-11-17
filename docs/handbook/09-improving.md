# 09 · Making Pep better: the roadmap

The rule above all others: **measure, change one thing, measure again.**
Every improvement below should be judged with `training/evaluate.py` (on a
benchmark with ground truth) and the Lab's Calibrate tab (agreement with
scouts).

## 1. Build the data flywheel (start now)
Accuracy comes from data more than code.
1. **Ground truth for physical metrics.** Run Tracka testing days: players
   do the 30 m sprint drill filmed by phone *and* timed with timing gates
   (or a high-frame-rate camera with a homography). Every clip becomes a
   labelled benchmark item.
2. **Scout ratings.** Get 2–3 scouts or coaches to rate 300+ clips in the
   Lab, with some overlap so you can measure scout-vs-scout agreement.
3. **Disputes.** tracka-api already collects them. Each dispute is a
   labelled error, the most valuable data there is.
4. **Frames for fine-tuning.** Save frames where the ball wasn't found or
   the target was lost. Label them in CVAT or Roboflow (**active learning**:
   label what the model gets wrong, not random frames).

## 2. Vision upgrades (biggest accuracy gains)
| Upgrade | Why | How |
|---|---|---|
| Fine-tune the ball detector on Tracka frames | The ball is the weakest link | `training/finetune_detector.py`, imgsz 1280 |
| Players/referee/keeper classes | Stop following the referee | Fine-tune with those classes |
| Re-identification (BoT-SORT, OSNet) | Fewer broken tracks in busy clips | `PEP_TRACKER=botsort.yaml`, then a football ReID model |
| Pitch-line calibration | Homography without cones on match clips | A keypoint model for pitch landmarks (SoccerNet calibration task) |
| Better pose model | Steadier joint angles | YOLO26m-pose, or RTMPose (Apache-2.0) |
| Action spotting | Know *what happened*: pass, shot, tackle, save | Train on SoccerNet action spotting, then Tracka clips. Unlocks real goalkeeping, passing accuracy and defending. |
| Jersey-number OCR | Confirm the target in team clips | A small text recogniser on the back crop |

## 3. Measurement upgrades
- **Per-player height.** Ask height at sign-up; the body ruler depends on it.
- **Phone field of view.** Read the phone model from video metadata and use
  its real FOV instead of assuming 66°.
- **Calibrate `BOX_TO_STATURE`** against timing-gate data (currently 0.96;
  synthetic tests read about 4% low).
- **Interpolate across short gaps** using the Kalman prediction, so brief
  occlusions don't split segments.

## 4. Scoring upgrades
- Replace starter norms with Tracka's own (`training/build_norms.py`), per
  sex and age band. Consider position-specific norms.
- Train the learned scorer once you have ≥ 300 rated clips; retrain monthly;
  ship only if it beats the rules on validation.
- Per-role learned models once data allows ("what makes a scout rate a
  winger highly?").
- Calibrate confidence: check that HIGH-confidence scores really are closer
  to scouts than LOW ones. If not, the confidence rules are wrong.

## 5. Engineering upgrades
- **Alembic migrations** before the schema changes in production
  (`create_all` can create tables but never alter them).
- **Auth for the Lab**: Tracka accounts (scouts, admins) instead of one
  password.
- **Progress reporting** from worker to Lab (a `stage` column updated as
  the pipeline runs).
- **Prometheus + Grafana** (or Grafana Cloud's free tier) scraping
  `/metrics`, with alerts (chapter 10).
- **Error tracking**: Sentry for exceptions in API and worker.
- **Load test**: queue 500 fake jobs; watch the queue drain; find the
  bottleneck.

## 6. Privacy, safety and fairness (do these before launch)
- **Register with Ghana's Data Protection Commission.** The Data Protection
  Act, 2012 (Act 843) requires data controllers to register before
  processing personal data.
- **Minors**: parental consent at sign-up for under-18s; scouts see minors'
  profiles only through verified accounts; no direct contact without a
  guardian or academy in the loop.
- **Retention**: delete raw clips after N days (R2 lifecycle rule); keep
  only metrics.
- **Biometrics**: body keypoints describe a person's body; treat pose data
  as personal data.
- **Fairness**: check scores by region, pitch type (grass/astroturf/sand)
  and phone quality. If players filmed on cheap phones score lower for the
  same sprint time, that's measurement bias, not talent.
- **Model licences**: decide the AGPL question (chapter 04).

## Workbook 09
1. Pick one upgrade from §2, write a one-page plan (data needed,
   evaluation, risk), and estimate its cost.
2. Design the timing-gate testing day: how many players, which drills,
   what you record, and how it feeds `labels.json`.

<details><summary>Why label the frames the model gets wrong rather than random ones?</summary>

Random frames are mostly easy cases the model already handles; labelling
them teaches it little. Hard frames sit on its decision boundary, so each
label there moves the model most. That's active learning.
</details>
