# 08 · Language models: how Pep writes its notes

Pep owns the numbers; the language model only writes the words. If the model is slow, down or switched off, players still get their results, with notes written by plain rules.

## The idea

A **large language model (LLM)** is a neural network trained on huge amounts of text to do one thing: predict the next piece of text. Do that well enough, at a big enough scale, and it can explain, summarise, translate and give advice. **Multimodal** models (Gemini, GPT, Claude) also take images, audio or video.

Text is split into **tokens** (roughly three quarters of a word each). Everything is measured in tokens: how much the model can read at once (the **context window**), how long it takes, and what it costs.

| Good at | Bad at |
| --- | --- |
| Clear, friendly explanations | Precise measurement and arithmetic |
| Judging things that are hard to define ("was that a good decision?") | Consistency: ask twice, get two answers |
| Summarising lots of input | Knowing when it's wrong |
| Following a format | Facts not in the input: it may **hallucinate** (confidently invent) |

So the standard design is: **let ordinary code do what can be computed, let the LLM do what needs language or judgement, and check what it returns.**

## The usual ways to do it

| Approach | What it is | Effort |
| --- | --- | --- |
| **Prompting** | Instructions and examples in the request | Cheapest; try first |
| **Structured output** | A schema the reply must fit (JSON with set fields) | Easy; makes replies testable |
| **RAG** (retrieval) | Look up relevant documents and include them | Medium; for "answer from our knowledge" |
| **Tool calling** | The model asks your code to run functions | Medium; the basis of "agents" |
| **Fine-tuning** | Further train the model on your examples | Expensive; only with lots of good data |

A **system prompt** sets the role and rules. **Temperature** sets randomness: low (0–0.3) is consistent, high (0.8+) is creative. And never trust, always check: validate the reply against the schema, clamp values, limit length, filter anything unsuitable (many users are children), and have a **fallback** for when the model is slow or down. Keep a set of test inputs and read the outputs regularly (an **eval**), because providers update models and quality drifts.

You can use a **hosted API** (Gemini, OpenAI, Anthropic: best quality, pay per token, nothing to run) or **self-host an open-weight model** (Llama, Qwen, Gemma: more control, you run the GPUs).

## What we chose and why

- **Gemini 3.8 Flash through its API**, because it can watch video, it's cheap per clip, and running our own model would mean more GPUs and more work.
- **Numbers come from measurement, never from the model.** Gemini receives Pep's measurements and is told not to invent new ones. It writes the summary and **moments** ("4.2 s: great burst, you beat your man in two steps").
- **It may rate a few things by eye** that cameras can't measure (like decision-making). Those are labelled `ai_observed`, low confidence, and count half as much.
- **Structured output.** The reply must fit a schema, so it arrives as typed data we can validate and test.
- **Pick from a list, not free text.** Each moment is tagged with a skill area from a fixed list. LLMs choose from lists reliably; free labels like "awareness" would match nothing in the app.
- **Plain code does the rest.** Drills come from our own catalogue, filtered by the kit the player has, so the model can never suggest a drill that needs a wall they don't have. Missing tips are filled by rules.
- **Fallback.** A timeout or any error means rule-written notes from the measurements. Every result says which wrote it (`coachSource`: `gemini` or `rules`).
- **The player's choice.** The "Coach notes" setting turns the model off for that player, which also keeps their video away from a third party.
- **Temperature 0.4**: some variety in wording, mostly consistent.

## How it's set up

- The model call, prompt and schema: `pep/coach/llm.py` (the system prompt is `SYSTEM`; the schema is `CoachNotes`).
- Guardrails (timestamps clamped to the clip, duplicates merged, length limits): `pep/coach/merge.py`.
- From notes to the player's review (titles, skill areas, drills): `pep/players/review.py`, drills from `pep/data/training.json`.
- The review is worked out from the stored result on every request (derived state, chapter 02), so better wording reaches every old clip for free.

## Words to know

LLM · multimodal · token · context window · hallucination · prompt · system prompt · temperature · structured output · schema · RAG · tool calling · fine-tuning · guardrail · fallback · eval · open-weight model

## Workbook 08

**Try it**

1. Set `PEP_GEMINI_API_KEY` and analyse a clip. Then compare its summary with `PEP_COACH_PROVIDER=none` (rules only).
2. Read `SYSTEM` in `pep/coach/llm.py`. Remove the "don't invent numbers" rule and see what happens.
3. Run the same clip three times at temperature 0.4, then 1.0. How much do the moments change?
4. Write five test clips with what a good coach would say, and score Gemini's notes against them by hand. That's an eval.

**Questions**

**1. Why doesn't the model produce the scores?**

*Answer:* It can't measure distances or speeds precisely, it's inconsistent, and it might invent numbers. Scores must be repeatable and explainable.

**2. Gemini is down for an hour. What do players see?**

*Answer:* Their clips still finish, with measurements, bands and rule-written notes. Nothing fails.

**3. Why does the model pick a skill area from a fixed list?**

*Answer:* So every tip lands somewhere the app can show and Pep can match a drill to. Free text would match nothing.

## More practice

Exercises added as features were built. Each one points at real code.

1. Get a Gemini API key, set `PEP_GEMINI_API_KEY`, and analyse a clip.
   Compare the `summary` with `PEP_COACH_PROVIDER=none` (rules only).
2. Read `SYSTEM` in `pep/coach/llm.py`. Remove the "don't invent
   numbers" rule and see what happens to the summary.
3. Run the same clip three times at temperature 0.4, then 1.0. How much
   do the moments change?
4. Write five "test clips" with what a good coach would say, and score
   Gemini's notes against them by hand. That's an **eval**.
5. In `tests/test_review.py`, change the kit in
   `test_drills_fit_the_kit` to `["ball", "wall"]` for `close_control`.
   Which drill does Pep pick now, and which line of `pick_drill` decides?
