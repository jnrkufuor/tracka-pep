# 11 · The Python toolbox

A handful of Python habits show up all over Pep. Each one exists to make code easier to check, cheaper to run, or safer to change. Read one, find it in the code, and change something small to see what happens.

## Code that people and tools can check

| Habit | What it is | Why we use it | Where |
| --- | --- | --- | --- |
| **Type hints** | `def age_on(birth: date \| None) -> int \| None` says what goes in and out | **mypy** catches "text where a number was expected" before the code runs; editors autocomplete | Everywhere; checked in CI |
| **Dataclasses** | `@dataclass` writes the boring parts of a class from a list of fields | Plain bundles of data with no boilerplate | `pep/metrics/kinematics.py`, `pep/pipeline.py` |
| **Pydantic** | Models that *check and convert* incoming data | Everything from outside (requests, settings, AI replies) is validated at the door | `pep/contracts.py`, `pep/config.py`, `pep/coach/llm.py` |
| **Protocols** | "Anything that has these methods", without a shared parent class | Tests swap in a fake detector, so they run without YOLO. This is **dependency injection** | `Perceiver` in `pep/vision/perception.py` |

## Patterns that save memory and time

- **Generators (`yield`)** produce values one at a time, as asked. A 10-minute video never sits in memory: `pep/video/frames.py` yields frames as the pipeline uses them.
- **Context managers (`with`)** guarantee clean-up even when something fails. We time each pipeline stage with one, and start and stop the API with one (`lifespan`).
- **Caching (`@cache`)** remembers a result so the second call is instant: settings, norms, the database connection. The catch: a cached value doesn't notice when its source changes.
- **NumPy** does maths on whole arrays in fast C code. `speed = np.hypot(vx, vy)` computes 1,000 speeds at once instead of looping. Most of `pep/metrics/` and `pep/vision/` works this way.

## Doing several things at once

| Tool | Good for | Where |
| --- | --- | --- |
| `async` / `await` | Many slow network calls waiting at once | The web server |
| Threads | A little background work | The worker's heartbeat (`pep/worker.py`) |
| Separate processes or machines | Heavy CPU or GPU work | Pep's workers |

## The project around the code

- **`pyproject.toml`** holds the project's name, libraries and tool settings in one file. **Extras** like `.[vision]` let the API image skip PyTorch.
- **Virtual environments** (`python -m venv .venv`) give each project its own libraries.
- **Entry points**: `pep serve`, `pep worker` and `pep analyse` come from `pep/cli.py`.
- **pytest**: tests are plain `test_` functions; **fixtures** in `tests/conftest.py` set up a fresh database for each test.
- **Ruff** lints and formats; **mypy** type-checks. Both run in CI.

## Words to know

type hint · mypy · dataclass · pydantic · validation · Protocol · dependency injection · generator · context manager · cache · vectorisation · NumPy · async/await · thread · process · virtual environment · extras · entry point · fixture

## Workbook 11

**Try it**

1. In a Python shell, import `AnalysisRequest` from `pep.contracts` and build one with a missing field. Read the error. Then build one with `"1.76"` as a height: what type comes out?
2. Rewrite one loop in `pep/metrics/` as a Python `for` loop and time both versions on 10,000 positions.
3. Find a test that uses the fake perceiver. What would the test need without it?

**Questions**

**1. Why validate with pydantic at the edges rather than everywhere?**

*Answer:* Data from outside (requests, settings, AI replies) can be anything. Once it's checked at the door, the code inside can trust its types.

**2. Why does `frames.py` yield frames instead of returning a list?**

*Answer:* A long video as a list would fill memory. Yielding keeps one frame at a time.

## More practice

Exercises added as features were built. Each one points at real code.

1. Break a type on purpose (make `age_on` return `str(years)`) and run
   `mypy pep`. Read the error.
2. In a Python shell: `from pep.contracts import AnalysisRequest` and
   build one from a dict with `analysisId` and a missing `videoUrl`. Read
   the validation error.
3. Write a generator `count_up(n)` that yields 0…n−1, and use it in a
   `for` loop. Then look at `pep/video/frames.py` again.
4. Time a Python loop vs `np.hypot` for computing a million speeds
   (`%timeit` in a notebook).
5. Today a video can be renamed to an empty title. Write a test in
   `tests/test_player_api.py` that expects a 422 for that (it fails), then
   add `min_length=1` to the rename model in `pep/players/routes.py` and
   watch it pass. That's **test-driven development** in miniature.
