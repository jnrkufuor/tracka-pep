# 12 · Cost, privacy and what's next

A clip costs about 2 US cents to analyse, and the AI-written notes are the biggest part, not the GPUs. We collect as little as possible about players, and Pep gets better through measured data, not cleverer code.

## What it costs

Cloud bills have **fixed costs** (paid every month, used or not: an always-on server, a database) and **variable costs** (growing with use: GPU seconds, AI tokens, storage). **Unit economics** asks what one unit costs (one clip, one active player a month), so you can price the product and see what happens at ten times the players.

The usual ways to cut costs: do less work (fewer frames, smaller models), scale to zero when idle, batch work, cap spending so a bug can't run up a bill, and avoid paying for downloads (egress).

**Our numbers** (list prices in US dollars, November 2026; check before budgeting):

| Item | Cost | Why |
| --- | --- | --- |
| Fixed floor (paid plans) | about $13–20 a month | Render API about $7, Render Postgres about $6; R2's first 10 GB and Cloudflare Pages are free |
| GPU per 30-second clip | about 0.5–1 cent | Modal L4 at about $0.80 an hour |
| AI notes per clip | about 1–2 cents | Gemini 3.8 Flash reading video |
| Storage per clip | tiny | About 15 MB on R2, no download fees |

At 5,000 clips a month that's about $110, or roughly 2 cents a clip. Our levers, biggest first: notes only when the player wants them (already a setting), fewer frames, smaller models (measure accuracy first), the GPU cap, and deleting raw clips after a while.

## Privacy and the law

**Personal data** is anything about an identifiable person: names, emails, faces in videos, birth dates, body measurements. Most laws say: collect only what you need (**data minimisation**), use it only for what you said, get **consent** (from a parent or guardian for children), don't keep it forever, keep it safe, and let people see, export and delete it.

In Ghana that's the **Data Protection Act, 2012 (Act 843)**, enforced by the **Data Protection Commission**, where every organisation that processes personal data must register. (General information, not legal advice.)

**What we chose and why:**

- **Show the least.** Others see a shirt name, position, age group and region; never the full name, birth date, town or contact. The player card's fields live in one function (`card_data` in `pep/players/card.py`), so there's one place to review.
- **Guardians decide for under-18s**, and can take it back instantly.
- **Share links are capability URLs**: a long random token where having the link *is* the permission. Turning it off cuts everyone off at once.
- **Download my data and delete my account** are built in. Both walk every table that points at the player, so a new feature's data is included the day it's added.
- **Coach notes off** keeps a player's video away from the AI provider.
- **Fairness checks.** Scores must not depend on region, pitch surface, phone quality or light. If players on cheaper phones score lower for the same sprint, that's **measurement bias**, and it would hurt exactly the players Tracka exists for.

Before launch: register with the Data Protection Commission, have a lawyer review the privacy policy, choose an SMS provider for guardian texts, and settle the YOLO licence (AGPL-3.0: open-source the service, buy a commercial licence, or switch to permissively licensed models). Store-specific steps are in `docs/STORE.md`.

## Making Pep better

The rule for improving any ML system: **measure, change one thing, measure again.** That needs a fixed **benchmark**: clips with known true answers. Most accuracy comes from **data**, not clever code. A **data flywheel** is when using the product produces data that makes it better, which brings more players and more data.

The roadmap, in order:

1. **Data first.** Testing days with timing gates beside the camera (true sprint times for the benchmark); 2–3 coaches rating 300+ clips in Pep Lab; saving frames where the ball or player was lost and labelling *those* (**active learning**).
2. **Vision.** Fine-tune the ball detector on our own frames; re-identification so busy clips lose players less often; pitch lines as calibration, so matches get metres without cones; recognising passes, shots and tackles.
3. **Scoring.** Replace starter norms with our own players' norms; train the learned scorer at 300+ rated clips and ship it only if it beats the rules on unseen players; check that high-confidence scores really are closer to coaches' ratings.
4. **Engineering.** Database migrations (Alembic), dashboards and alerts, resumable uploads for slow connections.
5. **Product.** The Opportunities tab, then the scout app on the same API, with new tables and roles.

## Words to know

fixed cost · variable cost · unit economics · spend cap · personal data · data minimisation · consent · retention · data controller · capability URL · measurement bias · benchmark · ground truth · data flywheel · active learning · re-identification

## Workbook 12

**Try it**

1. Look at Modal's dashboard after 10 clips: what were the real GPU seconds per clip? Redo the cost table with your numbers.
2. Download your data (Settings › Your data). Which tables are in it, and which are left out on purpose (`SKIP_TABLES` in `pep/players/account.py`)? Why would including login sessions be a problem?
3. Try posting a Pitchside caption with "call me 024 123 4567", then "follow @kofi". Both are refused. How would someone try to get around it, and what else keeps a child safe when a filter misses?
4. Plan a testing day: how many players, which drills, what equipment, and how you'll record the true times.

**Questions**

**1. What's the biggest variable cost per clip, and what's our main lever on it?**

*Answer:* The AI-written notes. Players can switch them off, and they could be limited to clips the player asks about.

**2. Why can't we tell whether a vision change helped without a benchmark?**

*Answer:* Without clips whose true answers are known, "looks better" is a guess. A fixed benchmark turns every change into a before-and-after number.

**3. Why keep the player card's fields in one function?**

*Answer:* One place to review what's shared. Spread across the code, a new field could leak without anyone noticing.

## More practice

Exercises added as features were built. Each one points at real code.

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
6. Share your card, open the link in a private browser window, then turn
   the link off and reload. Now add a field to `card_data` and write the
   test that proves it doesn't leak the player's town.
7. Settings › Your data › Download your data. Open the file: which tables
   are in it, and which are left out on purpose (`SKIP_TABLES` in
   `pep/players/account.py`)? Why would leaving `sessions` in be a problem?
8. Try posting a clip on Pitchside with the caption "call me 024 123 4567",
   then "follow @kofi". Both are refused (`has_contact_details` in
   `pep/players/pitchside.py`). Think like someone trying to get around it:
   what would you write instead ("zero two four…")? What else, besides the
   filter, keeps a child safe when a filter misses?
9. Open `docs/STORE.md` and fill in Play's Data safety form on paper for one
   new feature you'd like to add. Which rows change?
