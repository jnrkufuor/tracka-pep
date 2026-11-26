# 05 · Machine learning from zero

Pep is a chain of models and plain code, each doing one job. We reuse models others trained for seeing players, and train our own only where we have our own data: coaches' ratings of clips.

## The idea

Normal programming: you write the rules. "If speed > 8 m/s, say fast."

**Machine learning (ML)**: you show the computer lots of **examples** with the right answers, and it learns the rules itself. Show it 10,000 photos labelled "player" or "not player" and it learns what a player looks like, including rules you could never write by hand. The trained result is a **model**; using it on new data is **inference**.

| Kind of learning | Learns from | Example |
| --- | --- | --- |
| **Supervised** | Examples with answers (**labels**) | Clips rated by a coach |
| **Unsupervised** | Examples without answers; finds structure | Grouping players into styles |
| **Reinforcement** | Trial, error and rewards | A robot learning to kick |
| **Self-supervised** | Hides part of the data and predicts it | How language models learn from text |

Supervised tasks are either **classification** (pick a category: "is this a player?") or **regression** (predict a number: "what would a coach score this?").

Vocabulary you'll meet everywhere: **features** (the measurements you feed in: top speed, age), the **label** (the answer to predict), **training** (adjusting the model until its predictions match the labels), **loss** (how wrong it is), **weights** (the numbers training adjusts) and **hyperparameters** (settings you choose).

## The golden rule: test on data the model hasn't seen

A student who memorises last year's exam answers isn't necessarily good at the subject. Same with models. So you split the data: a **training set** (\~70%) to learn from, a **validation set** (\~15%) to choose settings, and a **test set** (\~15%) for one honest final score.

- **Overfitting**: the model memorised the training data and fails on new data.
- **Underfitting**: the model is too simple to learn the pattern.
- **Data leakage**: test information sneaks into training, so the score looks better than reality. The classic: clips of the *same player* in both training and test, so the model learns to recognise the person, not the skill. The fix is a **group split**: all of one player's clips go on the same side.
- **Cross-validation**: split five different ways, train five times, average. More reliable with little data.

How good is it? For numbers, **MAE** (on average, how many points off?) and **correlation** (are players in the right order?). For categories, **precision** (when we say "player", how often are we right?) and **recall** (of all players, how many did we find?). Always compare with a **baseline**, the simplest reasonable method. If you can't beat it, the model learned nothing useful.

## The usual ways to do it

| Model family | How it works, roughly | Best for |
| --- | --- | --- |
| **Linear regression** | A weighted sum of features | Simple, explainable baselines |
| **Decision trees** | A flowchart of yes/no questions | Explainable rules |
| **Gradient-boosted trees** (XGBoost, LightGBM, scikit-learn) | Hundreds of small trees, each fixing the last ones' mistakes | Tables of numbers; usually the best choice there |
| **Neural networks** | Layers of simple maths units | Images, video, sound, text |
| **CNNs** (convolutional networks) | Neural nets that scan images with small filters | Images; detectors like YOLO |
| **Transformers** | Neural nets built on "attention" | Language, and now images and video (Gemini, GPT, Claude) |

Training a vision model from nothing needs millions of images and lots of GPU time. So almost everyone starts from a **pretrained model** (trained by someone else on a huge public dataset) and, if needed, **fine-tunes** it on a small dataset of their own. That's **transfer learning**.

Labels are usually the slowest, most expensive part. Quality matters more than quantity: noisy labels teach noisy rules.

## What we chose and why

| Stage | Kind | Trained by us? |
| --- | --- | --- |
| Find people and the ball (YOLO26) | Pretrained CNN detector | No; could be fine-tuned on our pitches later |
| Body joints (YOLO26-pose) | Pretrained CNN | No |
| Follow the player over time | Classic algorithm, no learning | — |
| Measurements (speed, touches) | Plain maths | — |
| Scores | **Norms** (statistics) first, then a **learned scorer** | Yes, once coaches rate clips |
| Coach notes | A large language model (Gemini) | No; used as a service |

- **Reuse what others trained for seeing.** Finding people in video is a solved, general problem; training our own detector would cost far more for no gain.
- **Learn only what's ours.** What a *coach* values in a young Ghanaian player isn't in any public dataset. That's what our learned scorer learns, from coaches' ratings collected in Pep Lab.
- **Gradient-boosted trees for the scorer**, because the input is a small table of numbers and we have few labels. They're usually the most accurate there, train in seconds, and are easy to inspect.
- **Monotonic constraints**: we tell the model more speed can never *lower* a pace score, so it can't learn silly rules from noise.
- **Honest simple method first.** Until there are a few hundred rated clips, Pep scores with norms only. An honest simple method beats a clever model trained on 30 examples.

## How it's set up

- The learned scorer: `training/train_scorer.py` (features in `FEATURES`, constraints in `MONOTONIC`), loaded by `pep/scoring/learned.py`.
- Cross-validation is grouped by player (`GroupKFold`), and results are compared with the norms-only baseline using MAE and Spearman correlation.
- Coaches rate clips in Pep Lab (`/lab`); those ratings are the labels.

## Words to know

model · inference · supervised · classification · regression · feature · label · training · loss · weights · hyperparameter · training, validation and test set · overfitting · data leakage · group split · cross-validation · MAE · precision · recall · baseline · gradient boosting · neural network · CNN · transformer · pretrained · fine-tuning · transfer learning

## Workbook 05

**Try it**

1. In a notebook, make 50 fake rows (top speed, age, a coach score that rises with speed plus noise). Fit `LinearRegression` and `HistGradientBoostingRegressor` and compare MAE on held-out rows.
2. Leak on purpose: split clips randomly instead of by player and watch the score "improve". Switch to `GroupKFold` and watch it drop.
3. Rate 10 clips in Pep Lab yourself. You've just made labels.

**Questions**

**1. Is scoring a clip 30–95 classification or regression?**

*Answer:* Regression: the output is a number on a scale, not a category.

**2. Why split by player and not by clip?**

*Answer:* Clips of the same player look alike. If one player is in both training and test, the model can score well by recognising them, which says nothing about new players.

**3. Why use a pretrained detector instead of training our own?**

*Answer:* Training one from scratch needs millions of labelled images and lots of GPU time. Pretrained models already find people and balls well; fine-tuning on a few hundred of our own frames is the next step if they miss things.

## More practice

Exercises added as features were built. Each one points at real code.

1. Open a Python notebook, make 50 fake rows (top speed, age, a "coach
   score" that rises with speed plus some noise), and fit `LinearRegression` and
   `HistGradientBoostingRegressor` on it. Compare MAE on a held-out set.
2. Leak on purpose: split clips randomly instead of by player and see how
   the score "improves". Then switch to `GroupKFold` and watch it drop.
3. Run `python training/train_scorer.py --help`, then read `MONOTONIC` and
   `FEATURES` in that file to see how the constraints are set.
4. Rate 10 clips in the Lab console (`/lab`) yourself. You've just made labels.
