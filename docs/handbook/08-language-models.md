# 08 · Large language models (LLMs)

## The idea

A **large language model** (LLM) is a neural network trained on huge
amounts of text to do one thing: **predict the next piece of text**. Do
that well enough, at a big enough scale, and it can explain, summarise,
translate, write code and give advice. **Multimodal** models (Gemini,
GPT, Claude) also accept images, audio or video as input.

Text is split into **tokens** (pieces of words, roughly ¾ of a word
each). Everything is measured in tokens: how much the model can read at
once (the **context window**), how long it takes, and what it costs.

## What LLMs are good and bad at

| Good at | Bad at |
|---|---|
| Writing clear, friendly explanations | Precise measurement and arithmetic |
| Judging things that are hard to define ("was that a good decision?") | Being consistent: ask twice, get two answers |
| Summarising lots of input | Knowing when they're wrong |
| Following a format | Facts not in the input: they may **hallucinate** (confidently invent) |

So the standard design is: **let ordinary code do what can be computed;
let the LLM do what needs language or judgement; check its output.**

## The common approaches

### Ways to make an LLM do your task

| Approach | What it is | Cost / effort |
|---|---|---|
| **Prompting** | Write instructions and examples in the request | Cheapest; try first |
| **Structured output** | Give a schema; the model must reply in JSON that fits it | Easy; makes output testable |
| **RAG** (retrieval-augmented generation) | Look up relevant documents and include them in the prompt | Medium; good for "answer from our knowledge" |
| **Tool / function calling** | The model can ask your code to run functions (search, calculate) | Medium; the basis of "agents" |
| **Fine-tuning** | Further train the model on your examples | Expensive; only with lots of good data |

### Prompt basics
- A **system prompt** sets the role and rules ("You are a youth football
  coach. Never invent numbers.").
- Give the model the **facts it needs** (here, Pep's measurements).
- Show **examples** of good answers.
- **Temperature** controls randomness: low (0–0.3) is consistent, high
  (0.8+) is creative.

### Guardrails: never trust, always check
- Validate output against the schema; reject if it doesn't fit.
- Clamp values (timestamps must lie inside the clip).
- Limit length; filter inappropriate content (players may be children).
- **Timeouts and fallbacks**: if the LLM is slow or down, the product
  must still work.
- **Evaluate**: keep a set of test clips and read the outputs regularly.
  LLM quality drifts when providers update models.

### Using one: API or self-hosted

| Option | Examples | Notes |
|---|---|---|
| **Hosted API** | Google Gemini, OpenAI, Anthropic Claude | Best quality, pay per token, nothing to run |
| **Open-weight models, self-hosted** | Llama, Qwen, Gemma | You run the GPUs; more control, more work |

## How Tracka does it

The coach notes come from **Gemini 3.8 Flash**, which can watch video
(`pep/coach/llm.py`).

- **Pep owns the numbers, the LLM writes words.** Gemini gets Pep's
  measurements and is told not to invent new ones. It writes the summary
  and **moments** ("4.2 s: great burst, you beat your man in two steps"),
  and may rate a few hard-to-measure skills (like decision-making) by
  eye.
- Those eye-ratings are labelled `source: "ai_observed"` with LOW
  confidence, and count half as much in role fit.
- **Structured output**: the reply must fit the `CoachNotes` schema
  (pydantic), so it arrives as typed data, not free text.
- **Temperature 0.4**: a little variety in wording, mostly consistent.
- **Guardrails** (`pep/coach/merge.py`): timestamps clamped to the clip,
  duplicate moments merged, text length-limited.
- **Fallback**: a timeout (`PEP_COACH_TIMEOUT_SECONDS`) or any error →
  rule-written text from the measurements (`rules_summary`). The coach
  being down never fails an analysis. Every result says which wrote it
  (`coachSource`: `gemini` or `rules`).
- **Player's choice**: the "Coach notes" setting in the app turns the LLM
  off for that player's clips (`coach_notes` in the request), saving cost
  and keeping their video away from a third party.
- **Cost**: roughly 1–2 US cents per 30-second clip at introductory
  prices (chapter 12).

## Words to know
LLM · multimodal · token · context window · hallucination · prompt ·
system prompt · temperature · structured output · schema · RAG · tool
calling · agent · fine-tuning · guardrail · fallback · open-weight model

## Workbook 08

**Try it**
1. Get a Gemini API key, set `PEP_GEMINI_API_KEY`, and analyse a clip.
   Compare the `summary` with `PEP_COACH_PROVIDER=none` (rules only).
2. Read `SYSTEM` in `pep/coach/llm.py`. Remove the "don't invent
   numbers" rule and see what happens to the summary.
3. Run the same clip three times at temperature 0.4, then 1.0. How much
   do the moments change?
4. Write five "test clips" with what a good coach would say, and score
   Gemini's notes against them by hand. That's an **eval**.

**Questions**

**1. Why doesn't Pep let Gemini produce the scores?**

*Answer:* LLMs are inconsistent and can't measure distances or speeds
precisely; they might also invent numbers. Scores must be repeatable and
explainable, so they come from measurement.

**2. What does structured output buy us?**

*Answer:* A reply that is guaranteed to have the fields and types we
expect, so it can be validated, stored and tested like any other data.

**3. Gemini is down for an hour. What do players see?**

*Answer:* Their analyses still finish, with scores and rule-written
summaries; `coachSource` is `rules`. Nothing fails.

**4. Why mark AI-observed skills LOW confidence and half-weight?**

*Answer:* They're opinions from watching, not measurements, and less
reliable. They add information but shouldn't dominate a player's profile.
