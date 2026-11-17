# 05 · Machine learning, from zero

## The idea

Normal programming: you write the rules. "If speed > 8 m/s, say 'fast'."

**Machine learning (ML)**: you show the computer lots of **examples**
with the right answers, and it *learns* the rules itself. Show it 10,000
photos labelled "player" or "not player" and it learns what a player
looks like, including rules you could never write by hand.

A trained ML program is called a **model**. Using it on new data is
called **inference** (or prediction).

## The main kinds of learning

| Kind | Learns from | Example |
|---|---|---|
| **Supervised** | Examples with answers (**labels**) | Photos labelled "player"; clips rated by a coach |
| **Unsupervised** | Examples without answers; finds structure | Grouping players into similar styles |
| **Reinforcement** | Trial, error and rewards | A robot learning to kick |
| **Self-supervised** | Hides part of the data and predicts it | How large language models learn from text |

Supervised tasks come in two flavours: **classification** (pick a
category: "is this a player?") and **regression** (predict a number:
"what score would a coach give?").

## The vocabulary you'll meet everywhere

- **Features** (also "predictors" or "inputs"): the measurements you give
  the model. For a sprint: top speed, 10 m split, age.
- **Label** (or "target"): the answer you want predicted (a coach's
  score).
- **Training**: adjusting the model so its predictions match the labels.
- **Loss**: a number saying how wrong the model is. Training makes it
  smaller.
- **Parameters / weights**: the numbers inside the model that training
  adjusts. **Hyperparameters**: settings *you* choose (how many trees, how
  fast to learn).

### The golden rule: test on data the model hasn't seen
A student who memorises last year's exam answers isn't necessarily good
at the subject. Same with models. So you split data:

| Split | Used for |
|---|---|
| **Training set** (~70%) | Learning |
| **Validation set** (~15%) | Choosing settings, comparing models |
| **Test set** (~15%) | One final honest score at the end |

- **Overfitting**: the model memorised the training data and fails on
  new data (great on homework, bad on the exam).
- **Underfitting**: the model is too simple to learn the pattern at all.
- **Data leakage**: information from the test set sneaks into training,
  so the score looks better than reality. A classic: clips of the *same
  player* in both training and test. The model learns to recognise the
  person, not the skill. The fix is **group splitting**: all of one
  player's clips go on the same side.
- **Cross-validation**: split the data 5 different ways, train 5 times,
  average the scores. More reliable when you have little data.

### Measuring how good a model is

| Task | Metric | In plain words |
|---|---|---|
| Regression | **MAE** (mean absolute error) | On average, how many points off are we? |
| Regression | **Correlation** (Spearman) | Do we put players in the right order? |
| Classification | **Precision** | When we say "player", how often are we right? |
| Classification | **Recall** | Of all real players, how many did we find? |
| Detection | **mAP** | Precision and recall combined over all objects and box overlaps |

Always compare with a **baseline**: the dumbest reasonable method (e.g.
"predict the average score for everyone"). If your model can't beat it,
it isn't learning anything useful.

## Families of models

| Family | How it works, roughly | Best for |
|---|---|---|
| **Linear / logistic regression** | Weighted sum of features | Simple, explainable baselines |
| **Decision trees** | A flowchart of yes/no questions | Explainable rules |
| **Gradient-boosted trees** (XGBoost, LightGBM, scikit-learn's HistGradientBoosting) | Hundreds of small trees, each fixing the previous ones' mistakes | **Tables of numbers**. Usually the best choice there |
| **Neural networks** | Layers of simple maths units, trained by gradient descent | Images, video, sound, text |
| **Convolutional networks (CNNs)** | Neural nets that scan images with small filters | Images (detectors like YOLO) |
| **Transformers** | Neural nets built on "attention" (which parts relate to which) | Language, and now images/video (Gemini, GPT, Claude) |

### Training from scratch vs reusing
Training a vision model from nothing needs millions of images and lots
of GPU time. Instead, people use **pretrained models** (trained by
someone else on a huge dataset like COCO) and, if needed, **fine-tune**
them (keep training on a small dataset of your own). This is called
**transfer learning**, and it's how almost everyone builds vision
products.

### Where labels come from
**Labelling** (or annotation) is usually the slowest, most expensive
part. Options: do it yourself, pay annotators, use tools like CVAT or
Label Studio, or get experts (coaches) to rate clips. Label quality
matters more than quantity: noisy labels teach noisy rules.

## How Tracka does it

Pep is a **pipeline** of several models and plain code, each doing one
job (chapters 06–08 go through them):

| Stage | Kind | Trained by us? |
|---|---|---|
| Find people and the ball (YOLO26) | Pretrained CNN detector | No. Pretrained on COCO, could be fine-tuned later |
| Body keypoints (YOLO26-pose) | Pretrained CNN | No |
| Follow the player over time (ByteTrack + Kalman filter) | Classic algorithm, no learning | — |
| Measurements (speed, touches…) | Plain maths | — |
| Scores 30–95 | **Norms** (statistics) at first, then a **learned scorer** | Yes, once coaches rate clips |
| Coach notes | Large language model (Gemini) | No, used as a service |

The **learned scorer** (`training/train_scorer.py`) is classic
supervised regression:
- **features**: the measurements from `pep/metrics/` plus age, sex,
  position and clip type;
- **label**: a coach's rating of the clip (collected in the Lab console's
  rating screen);
- **model**: gradient-boosted trees, because the data is a table of
  numbers and there isn't much of it;
- **monotonic constraints**: we tell the model that more speed can never
  *lower* a pace score. This stops it learning silly rules from noise;
- **GroupKFold** cross-validation by player, to avoid the leakage
  described above;
- **metrics**: MAE and Spearman correlation against coach ratings, compared
  with the norms-only baseline.

Until there are enough ratings (a few hundred clips), Pep scores with
norms only. That's a deliberate choice: an honest simple method beats a
clever model trained on 30 examples.

## Words to know
model · inference · supervised · unsupervised · classification ·
regression · feature · label · training · loss · weights ·
hyperparameter · train / validation / test set · overfitting ·
underfitting · data leakage · group split · cross-validation · MAE ·
precision · recall · baseline · gradient boosting · neural network · CNN ·
transformer · pretrained · fine-tuning · transfer learning · labelling

## Workbook 05

**Try it**
1. Open a Python notebook, make 50 fake rows (top speed, age, a "coach
   score" that rises with speed plus some noise), and fit `LinearRegression` and
   `HistGradientBoostingRegressor` on it. Compare MAE on a held-out set.
2. Leak on purpose: split clips randomly instead of by player and see how
   the score "improves". Then switch to `GroupKFold` and watch it drop.
3. Run `python training/train_scorer.py --help`, then read `MONOTONIC` and
   `FEATURES` in that file to see how the constraints are set.
4. Rate 10 clips in the Lab console (`/lab`) yourself. You've just made labels.

**Questions**

**1. Is "scoring a clip 30–95" classification or regression?**

*Answer:* Regression: the output is a number on a scale, not a category.

**2. Why split by player and not by clip?**

*Answer:* Clips of the same player look alike (same body, kit, camera).
If the same player appears in training and test, the model can score well
by recognising the player, which says nothing about new players.

**3. Why gradient-boosted trees and not a neural network for the
scorer?**

*Answer:* The input is a small table of numbers and there are few
labelled examples. Boosted trees are usually the most accurate there,
train in seconds, and are easier to inspect. Neural networks shine with
images, text, and lots of data.

**4. Why use a pretrained detector instead of training our own?**

*Answer:* Training one from scratch needs millions of labelled images and
lots of GPU time. Pretrained models already find people and balls well;
fine-tuning on a few hundred Ghanaian pitch images would be the next step
if they miss things.
