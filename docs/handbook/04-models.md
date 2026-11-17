# 04 · The models, one by one

Pep isn't one model. It's a **pipeline** of specialised steps, some learned
(neural networks), some classical (geometry, filtering, statistics).
Knowing which is which, and why, is the most important idea in this
handbook:

> Use learning where the world is too messy to write rules (what does a
> person look like?). Use maths where physics already gives the answer (how
> far did they move?). Learned models are powerful but opaque; classical
> methods are explainable and need no training data.

| Step | Method | Learned? | File |
|---|---|---|---|
| Find people + body points | YOLO26-pose (CNN) | yes, pretrained on COCO | `vision/perception.py` |
| Find the ball | YOLO26 detection + zoomed second look | yes, pretrained on COCO | `vision/perception.py` |
| Same person across frames | ByteTrack (Kalman + Hungarian matching) | no | Ultralytics, `vision/target.py` |
| Cancel camera motion | Shi-Tomasi corners, Lucas-Kanade flow, RANSAC | no | `vision/camera.py` |
| Pixels → metres | Homography or pinhole "body ruler" | no | `vision/calibration.py` |
| Smooth path → speed | Kalman filter + RTS smoother | no | `metrics/kinematics.py` |
| Scores | Norms (z-scores) + rules | no (for now) | `scoring/` |
| Agree with scouts | Gradient-boosted trees | yes, on your ratings | `scoring/learned.py`, `training/train_scorer.py` |
| Words and moments | Gemini 3.8 Flash (video LLM) | yes, hosted | `coach/llm.py` |

---

## 1. YOLO26: object detection

**What it does.** Takes an image and returns boxes:
`(x1, y1, x2, y2, class, confidence)`. We ask for COCO class 0
("person") and 32 ("sports ball").

**How it works (the intuition).**
- A **convolutional neural network (CNN)** slides small learned filters
  over the image. Early layers respond to edges and colours, middle layers
  to textures and parts (a knee, a stripe), deep layers to whole objects.
- The **backbone** extracts features at several scales; the **neck**
  mixes fine detail with big-picture context (so small balls and big
  players are both found); the **head** predicts boxes and classes at
  every location.
- "YOLO" = *You Only Look Once*: one forward pass finds everything, which
  makes it fast enough for video.
- Older YOLOs predicted many overlapping boxes and cleaned up with
  **NMS** (non-maximum suppression: keep the most confident box, drop
  others overlapping it). YOLO26 is trained to output one box per object
  ("end-to-end, NMS-free"), which simplifies deployment.

**Sizes.** n / s / m / l / x trade speed for accuracy. Pep uses `s` for
the ball (small objects need capacity) and `n` for pose. Change them with
`PEP_DETECTOR_MODEL` / `PEP_POSE_MODEL`.

**Why YOLO26:** state of the art for real-time detection, pose and
tracking in one package, trivial to fine-tune, huge community.

**Limits here.** Trained on COCO (everyday photos), not football. It
misses small, blurred balls and can confuse referees with players. The fix
is **fine-tuning** (`training/finetune_detector.py`) on football frames,
ideally Tracka's own.

**The zoomed second look (SAHI idea).** YOLO shrinks frames to 640 px
internally. A 10 px ball becomes 5 px: invisible. If the full-frame pass
misses the ball, we crop around the two biggest players' feet, enlarge, and
look again. Small things become detectable when you zoom in where they're
likely to be.

### Licences (important for a business)
Ultralytics YOLO is **AGPL-3.0**. AGPL's network clause means that if you
serve the model to users over a network, the source of the whole service
using it must be available under AGPL too, and that includes models you
fine-tune. Ultralytics sells an Enterprise License that removes these
obligations. Your `tracka-pep` repo is public today, which fits AGPL. Before
a commercial launch, choose deliberately:
1. keep Pep open-source under AGPL (and check what that means for Tracka
   with a lawyer);
2. buy the Ultralytics Enterprise License; or
3. swap in Apache-2.0 models (e.g. RT-DETR for detection, RTMPose for
   pose). The `Perceiver` protocol makes that a contained change. tracka-api's
   built-in coach already uses YOLOX (Apache-2.0) for this reason.

*(Not legal advice; get a lawyer to confirm before you charge money.)*

---

## 2. YOLO26-pose: body keypoints

Same network family, with an extra head that predicts **17 keypoints**
per person (the COCO layout: nose, eyes, ears, shoulders, elbows, wrists,
hips, knees, ankles), each with a confidence. Pep uses them for joint
angles (knee bend, torso lean), head turns (scanning) and goalkeeper dives
(`metrics/technique.py`, `metrics/goalkeeping.py`).

Keypoints are less reliable when limbs are hidden, blurred or side-on.
That's why every pose metric ignores low-confidence points
(`MIN_KP_CONF = 0.4`) and needs a minimum number of frames.

---

## 3. ByteTrack: keeping identities across frames

Detection gives boxes per frame, with no idea that box #3 now is box #5
before. **Tracking** links them into **tracks** with stable IDs.

ByteTrack, step by step:
1. **Predict** each existing track's next box with a **Kalman filter**
   (constant-velocity motion).
2. **Match** high-confidence detections to predictions by box overlap
   (**IoU**, intersection over union), solving the best one-to-one
   assignment with the **Hungarian algorithm** (that's the `lap` package).
3. **Second chance**: match *low*-confidence detections to the
   still-unmatched tracks. This is ByteTrack's key idea: a half-hidden
   player gets a low score but is still the same player.
4. Unmatched tracks stay alive for a while (in case the player reappears);
   unmatched high-confidence detections start new tracks.

`botsort.yaml` adds **re-identification** (an appearance embedding) and
camera-motion compensation inside the tracker. Try it with
`PEP_TRACKER=botsort.yaml` and compare.

**Our layer on top** (`vision/target.py`): pick *the* player (a tap hint,
or presence × size × near-ball), then **stitch** tracks the tracker broke
(the target's track ends and a similar-sized new one starts nearby within
1.5 s, so treat it as the same player).

---

## 4. Camera-motion compensation (classical computer vision)

Phones pan and zoom. Without correction, a still player looks like they're
running.
1. **Shi-Tomasi corners** (`goodFeaturesToTrack`): find points that are
   easy to follow (corners, not flat grass), with people masked out.
2. **Lucas-Kanade optical flow** (`calcOpticalFlowPyrLK`): find where each
   point moved in the next frame. It assumes brightness stays constant and
   motion is small, and uses an image pyramid for bigger motions.
3. **RANSAC** (`estimateAffinePartial2D`): fit one move + rotate + zoom
   that explains most point movements. RANSAC repeatedly fits to a random
   minimal subset, counts the points that agree ("inliers"), and keeps the
   best. Points on moving players or noise get outvoted.
4. **Chain** the per-frame transforms into "current frame → first frame"
   (multiply 3×3 homogeneous matrices).

`camera_reliability` is the share of steps where this worked. Low values
(plain grass, motion blur) lower the scores' confidence.

---

## 5. Pixels → metres: homography and the pinhole "body ruler"

**Homography** (drills). A 3×3 matrix `H` maps points on one plane (the
ground, as the camera sees it) to another (the ground in metres). Four
point pairs fix its 8 unknowns; more points are fitted by least squares.
It handles perspective properly: it's how broadcast systems calibrate from
pitch lines. The player taps the cones; we know where the cones are in
metres (`pep/data/drills.json`).

**Pinhole model** (everything else). A camera with focal length `f`
pixels sees an object of height `H` metres at distance `Z` as `h = f·H/Z`
pixels tall. Knowing the player's height (`playerHeightM`, default 1.72 m)
and their box height gives distance: `Z = f·H/h`. Then sideways position is
`X = (u − cx)·Z/f`. We assume a typical phone field of view (66° wide) to
get `f`. Box heights jitter (arms up, crouching), so they're smoothed hard
first (median, then mean).

**Accuracy we measured:** on synthetic clips with known speeds (5.0, 6.5,
8.0 m/s), top speed reads about 4% low on average (`training/evaluate.py`).
That comes from `BOX_TO_STATURE = 0.96`: running players' boxes are shorter
than their height, but the test clip's static cut-out isn't. On real clips
expect ±10–15%. That's why drills (homography) carry HIGH confidence and
clip estimates MEDIUM at best.

---

## 6. Kalman filter + RTS smoother: from jittery positions to clean speed

Differentiating noisy positions amplifies noise: 10 cm of jitter at 10 fps
becomes ±1 m/s of fake speed. The Kalman filter treats the player as a
point with position and velocity (`[x, y, vx, vy]`):
- **Predict**: physics moves the state forward; uncertainty grows by the
  "process noise" (how hard players can accelerate, `accel_sigma = 4 m/s²`).
- **Update**: blend the prediction with the measurement. The **Kalman
  gain** weighs them by their uncertainties: trust a precise measurement
  (homography: ±0.15 m) more than a vague one (body ruler far away: ±0.6 m).
- **Missing frames**: predict only.
- **RTS smoother**: we have the whole clip, so we also run backwards and
  let the future correct the past. Offline estimates are much cleaner than
  live ones.

`tests/test_kinematics.py::test_raw_differences_would_be_much_worse` shows
the difference numerically.

---

## 7. Gradient-boosted trees: the learned scorer

Once scouts have rated clips in the Lab, `training/train_scorer.py` learns
"measurements → scout rating".

- A **decision tree** splits the data by questions ("top speed > 7.4?") to
  predict a number. One tree is crude.
- **Boosting** adds trees one at a time, each fitting what the previous
  ones got wrong (the residuals), scaled by a small learning rate.
- scikit-learn's `HistGradientBoostingRegressor` bins features for speed,
  handles missing values natively, and supports **monotonic constraints**:
  we promise a faster sprint never lowers the score.

Why trees, not a neural network: a few hundred rows of tabular data is
exactly where boosted trees win. They're fast to train, need little tuning,
and are easier to inspect.

**Validation done right.** `GroupKFold` by player: no player appears in
both training and validation folds, otherwise the model "recognises Kofi"
and looks better than it is (**data leakage**). We only save the model if
it **beats the rules baseline** on validation MAE.

---

## 8. Gemini 3.8 Flash: the coach that watches

A large multimodal model that takes the video plus our measurements and
returns **structured JSON** (`CoachNotes`): a summary, timestamped moments,
skills it can judge by eye (passing, finishing, decision-making), and tips.

**Guardrails** (`coach/llm.py`, `coach/merge.py`):
- the prompt gives our numbers and forbids inventing others;
- AI-observed skills are marked `ai_observed`, LOW confidence, and count
  half in role fit;
- timestamps are clamped to the clip and text lengths are limited;
- any failure falls back to rule-written text. The coach never fails an
  analysis.

**Why a hosted model rather than training our own:** recognising "a good
pass" needs huge amounts of labelled video. A frontier model gives a decent
first opinion today. As Tracka collects labelled clips, specific skills can
move to trained in-house models (see chapter 09).

---

## Workbook 04

**Exercises**

1. Run `pep analyse run.mp4 --overlay seen.mp4` and watch `seen.mp4`. What
   happens to the box when the player is partly out of frame?
2. Switch `PEP_DETECTOR_MODEL` between `yolo26n.pt` and `yolo26s.pt` on
   the same clip. Compare the `perception` time and the `ball_frames`
   metric.
3. Set `PEP_TRACKER=botsort.yaml`. On a busy match clip, compare how many
   track IDs the target needed (log `chain` in `pipeline.py`).
4. In a notebook, generate a straight run with 0.3 m noise, then plot raw
   frame-to-frame speed against `analyse_movement(...).speed`. Change
   `accel_sigma` to 1 and to 10. What happens to lag and noise?
5. Fit a homography by hand: pick four points on a photo of a pitch (the
   corners of the penalty box, 40.3 × 16.5 m), call `fit_homography`, then
   map the penalty spot. Is it 11 m from the goal line?
6. Make 120 fake ratings where scouts value *acceleration* (not speed), run
   `train_scorer.py`, and check that the model learned it.

**Questions**

<details><summary>1. Why is the ball much harder to detect than players?</summary>

It's tiny (often under 15 px), motion-blurred into a streak, partly hidden
by feet, and COCO has few football-sized balls on pitches. Downscaling to
640 px can shrink it to a couple of pixels.
</details>

<details><summary>2. ByteTrack already uses a Kalman filter. Why does Pep run another one?</summary>

They serve different purposes and spaces. ByteTrack's predicts boxes in
*pixels* from frame to frame to match detections, online. Pep's smooths the
chosen player's *ground position in metres*, offline with an RTS backward
pass, to get physically meaningful speed.
</details>

<details><summary>3. What does RANSAC protect against in camera-motion estimation?</summary>

Outliers: points on moving players, the ball, bad flow matches. A
least-squares fit would be pulled by them. RANSAC finds the transform the
*majority* agrees on.
</details>

<details><summary>4. A player runs straight at the camera. Why might the body-ruler method under-read their speed, and how does the pinhole model help?</summary>

On screen they barely move sideways: they just get bigger. Counting
sideways pixels alone would read nearly zero. The pinhole model turns the
growing box into decreasing distance `Z = f·H/h`, so the motion along the
depth axis is counted. It's noisy, though, because box height jitter
becomes depth jitter.
</details>

<details><summary>5. What is data leakage, and how does GroupKFold prevent it here?</summary>

Information from the validation set leaking into training, making scores
look better than they'll be in reality. With several clips per player, a
random split puts the same player on both sides. GroupKFold keeps all of a
player's clips in one fold, so validation always tests on unseen players.
</details>

<details><summary>6. Why must the LLM never set the numeric scores itself?</summary>

LLMs can produce confident numbers with no measurement behind them
(hallucination), and they're not consistent from run to run. Scouts must be
able to trust that a number means the same thing for every player. Numbers
come from measurement and norms; the model contributes words, moments and
clearly labelled low-confidence observations.
</details>
