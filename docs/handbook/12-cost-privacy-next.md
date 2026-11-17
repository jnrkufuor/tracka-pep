# 12 · Cost, privacy and what's next

## Part 1: What it costs

### The idea
Cloud bills have two parts:
- **Fixed costs**: paid every month whether anyone uses the app (a
  server that's always on, a database).
- **Variable costs**: grow with usage (GPU seconds per clip, AI tokens,
  gigabytes stored).

**Unit economics** asks: what does *one* unit (one clip, one active
player a month) cost? If you know that, you can price the product and
see what happens at 10× the users.

### Common ways to cut cloud costs
- **Do less work**: analyse fewer frames, smaller images, skip work
  nobody asked for.
- **Use the right-sized machine**: small models, smaller instances.
- **Scale to zero** when idle; **batch** work so one warm machine handles
  many jobs.
- **Cap spending**: limits and budget alerts, so a bug or a traffic
  spike can't produce a surprise bill.
- **Avoid egress fees** for data that's downloaded a lot.

### Tracka's numbers
List prices in USD as of November 2026. They change; check before
budgeting.

**Fixed floor, about $13–20 a month**: Render API (Starter, about $7),
Render Postgres (about $6), Cloudflare R2 (first 10 GB free), Cloudflare
Pages (free), Modal (includes some free credit monthly).

**Per 30-second clip**:

| Item | Rough cost | Why |
|---|---|---|
| GPU (Modal L4, ~$0.80/hour) | ~0.5–1 cent | ~300 frames × two YOLO passes, plus start-up |
| Gemini 3.8 Flash coach notes | ~1–2 cents | Video costs a few hundred tokens a second; introductory price $0.75 / $3.75 per million input/output tokens until 31 Dec 2026 |
| R2 storage | tiny | ~15 MB a clip, $0.015/GB-month, free downloads |

**Example: 5,000 clips a month ≈ $110, about 2 cents a clip.** The AI
coach is the biggest variable cost, not the GPUs.

Levers, biggest first: coach notes only when wanted (the player setting
already does this); fewer frames (`PEP_SAMPLES_PER_SECOND=6`); smaller
models (measure accuracy first); batching (`drain()`); caps
(`max_containers=4`, Gemini budget alerts); delete raw clips after a
while (an R2 lifecycle rule).

## Part 2: Privacy, safety and the law

### The idea
**Personal data** is anything about an identifiable person: names,
emails, faces in videos, birth dates, and body measurements. Laws in most
countries say you may collect it only for a clear purpose, must keep it
safe, must let people see and delete it, and must take extra care with
children.

### The common rules
| Principle | Means |
|---|---|
| **Data minimisation** | Collect only what you need |
| **Purpose limitation** | Use it only for what you said |
| **Consent** | People agree knowingly; for children, a parent or guardian agrees |
| **Retention** | Don't keep it forever |
| **Security** | Encrypt, limit access, hash passwords |
| **Rights** | People can see, correct, export and delete their data |

Laws: Ghana's **Data Protection Act, 2012 (Act 843)**, enforced by the
**Data Protection Commission**, where data controllers must register;
the EU's GDPR; Nigeria's NDPA; and others as Tracka expands. (This is
general information, not legal advice: talk to a lawyer before launch.)

### How Tracka does it
- **Players only see their own videos**; every query filters by user ID.
- **Passwords hashed** with scrypt; tokens expire; refresh-token reuse
  revokes all sessions.
- **Under-18s** need a guardian's email and consent before uploading,
  enforced by the server.
- **Delete account** removes the profile, videos, files and analyses.
- **Coach notes off** keeps a player's video away from Gemini.
- **"Share with scouts"** is off and disabled until the scout app exists.

Still to do before launch: register with the Data Protection Commission;
a privacy policy and terms in plain English (and Twi, Ga, Ewe…); verify
guardians properly (email confirmation, not just a checkbox); a retention
rule for raw clips; data export; decide the **YOLO licence** question
(Ultralytics is AGPL-3.0: open-source the service or buy their
commercial licence; or switch to permissively licensed models like
RTMDet/RTMPose).

### Fairness
Check that scores don't depend on things unrelated to talent: region,
pitch surface (grass, astroturf, sand), phone quality, lighting. If
players filmed on cheaper phones score lower for the same sprint time,
that's **measurement bias**, and it would hurt exactly the players Tracka
wants to help.

## Part 3: Making Pep better

### The idea
The rule for improving any ML system: **measure, change one thing,
measure again.** Without a fixed **benchmark** (clips with known true
answers), you can't tell whether a change helped.

Most accuracy comes from **data**, not clever code. A **data flywheel**
is when using the product produces data that makes the product better,
which brings more users, which produces more data.

### The roadmap, in order

**1. Build the data (start now)**
- **Testing days**: film players doing the 30 m sprint drill while also
  timing them with timing gates. Each clip becomes a benchmark item with
  a true answer (`training/make_benchmark.py`, `training/evaluate.py`).
- **Coach ratings**: 2–3 coaches rate 300+ clips in the Lab, with overlap
  to measure how much coaches agree with each other.
- **Active learning**: save frames where the ball or player was lost and
  label *those*. Hard examples teach the model most.

**2. Vision**
| Upgrade | Why |
|---|---|
| Fine-tune the ball detector on Tracka frames (`training/finetune_detector.py`) | The ball is the weakest link |
| Re-identification (`PEP_TRACKER=botsort.yaml`, then a football ReID model) | Fewer lost players in busy clips |
| Pitch-line calibration | Metres without cones in match clips |
| Action recognition (pass, shot, tackle, save), e.g. trained on SoccerNet | Real passing, defending and goalkeeping scores |

**3. Scoring**
- Replace starter norms with Ghanaian players' own (`training/build_norms.py`).
- Train the learned scorer at 300+ rated clips; ship only if it beats the
  rules on held-out players.
- Check confidence is honest: HIGH-confidence scores should really be
  closer to coaches' ratings than LOW ones.

**4. Engineering (chapter 10)**
Alembic migrations, Grafana dashboards and alerts, Sentry error tracking,
a tested database restore, a load test (queue 500 jobs and find the
bottleneck), resumable uploads for slow connections.

**5. Product**
Push notifications when a clip is ready; offline queueing of uploads;
the **Opportunities** tab; then the separate **scout app** reading the
same API with new tables and roles.

## Words to know
fixed cost · variable cost · unit economics · scale to zero · spend cap ·
personal data · data minimisation · consent · retention · data controller ·
measurement bias · benchmark · ground truth · data flywheel · active
learning · re-identification · action recognition

## Workbook 12

**Try it**
1. Deploy a Modal worker, run 10 clips, and read real GPU seconds per
   clip from Modal's dashboard. Redo the cost table with your numbers.
2. Recalculate the monthly bill for 50,000 clips. Which line grows
   fastest? What would you change first?
3. Write the privacy notice a 15-year-old and their parent would read
   before signing up. One page, plain words.
4. Plan a testing day: how many players, which drills, what equipment,
   how results become benchmark items.
5. Pick one roadmap item, write a one-page plan (data needed, how you'll
   measure success, cost, risk), and do it on a branch.

**Questions**

**1. Why is the AI coach the biggest variable cost?**

*Answer:* YOLO on a GPU takes milliseconds per frame. A frontier LLM
processing thousands of video tokens is far heavier, and priced
accordingly.

**2. Why label frames the model gets wrong instead of random frames?**

*Answer:* Random frames are mostly easy cases the model already handles.
Hard frames are where it's confused, so each label there changes the model
most. That's active learning.

**3. What is measurement bias, and how could it show up in Tracka?**

*Answer:* Errors that depend on how something was measured rather than
what was measured: e.g. cheaper phones with lower frame rates making the
same sprint look slower.

**4. Why does deleting an account have to remove the video files too, not
just the database rows?**

*Answer:* The files are the most personal data of all (the player's face
and body). Leaving them in storage would break the promise of deletion and
the law's right to erasure.
