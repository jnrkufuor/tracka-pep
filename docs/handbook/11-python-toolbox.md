# 11 · The Python toolbox

Python features and habits that show up all over Pep, each with the
general idea first and then where to find it. Read one, find it in the
code, and change something small to see what happens.

## Writing code people (and tools) can check

### Type hints
`def age_on(birth: date | None, today: date | None = None) -> int | None:`
(in `pep/players/store.py`) says what goes in and
comes out. Python ignores hints at run time, but **mypy** checks them
before the code runs, and editors use them for autocomplete. `str | None`
means "text or nothing"; `Literal["LOW", "MEDIUM", "HIGH"]` means "only
these exact values" (`pep/contracts.py`).

### Dataclasses
`@dataclass` writes the boring parts of a class (`__init__`, `__repr__`,
`==`) from a list of fields. Use it for plain bundles of data
(`pep/metrics/kinematics.py`, `pep/pipeline.py`).

### Pydantic: validation at the edges
**Pydantic** models are like dataclasses that *check* incoming data and
convert it: a string `"1.76"` becomes a float, a missing required field
raises a clear error. Use them wherever data enters from outside (HTTP
requests, environment variables, LLM replies).
- `pep/contracts.py`: API shapes, with camelCase aliases so Python can
  say `overall_score` while JSON says `overallScore`.
- `pep/config.py`: `pydantic-settings` reads `PEP_*` environment
  variables into one typed `Settings` object.
- `pep/coach/llm.py`: `CoachNotes` is also the schema Gemini must follow.

### Protocols: "anything that can do X"
A `Protocol` describes the methods something must have, without a common
parent class. `Perceiver` in `pep/vision/perception.py` is "anything with
`observe()` and `reset()`". Tests pass a fake perceiver so they don't need
YOLO. This is **dependency injection**: hand code the parts it uses
instead of hard-wiring them, so you can swap them.

## Patterns that save memory and time

### Generators (`yield`)
A function with `yield` produces values **one at a time, as asked**. A
10-minute video never sits in memory all at once: `pep/video/frames.py`
yields frames as the pipeline consumes them.

### Context managers (`with`)
`with open(...) as f:` guarantees clean-up (closing the file) even if an
error happens. You can write your own with `@contextmanager`:
- `pep/pipeline.py` times each stage with one;
- `pep/api/app.py` uses an async one (`lifespan`) for start-up and
  shutdown;
- `contextlib.suppress(Exception)` in `pep/coach/llm.py` means "ignore
  errors here", used only for best-effort clean-up.

### Caching
`@cache` / `@lru_cache` remember a function's result so the second call
is instant. Used for things loaded once: settings (`pep/config.py`),
norms (`pep/scoring/norms.py`), the database engine (`pep/db.py`).
Caution: a cached value doesn't notice when the source changes.

### Vectorised maths with NumPy
Instead of a Python `for` loop over 1,000 positions, NumPy does the
maths on whole arrays in fast C code: `speed = np.hypot(vx, vy)` computes
1,000 speeds at once. Most of `pep/metrics/` and `pep/vision/` is written
this way.

## Running things concurrently

| Tool | Good for |
|---|---|
| `async` / `await` (asyncio) | Many slow network calls waiting at once (web servers) |
| Threads (`threading`) | A little background work, e.g. the worker's heartbeat (`pep/worker.py`) |
| Processes (`multiprocessing`, separate workers) | CPU/GPU-heavy work. Pep's workers are separate processes on separate machines |

FastAPI runs normal `def` routes in a thread pool, so slow database
calls don't block other requests.

## The project around the code

- **`pyproject.toml`**: the project's name, dependencies and tool
  settings in one file. **Extras** like `.[vision]` and `.[dev]` let the
  API image skip PyTorch.
- **Virtual environments** (`python -m venv .venv`): a separate set of
  libraries per project, so projects don't fight over versions.
- **Entry points**: `pep serve`, `pep worker`, `pep analyse` are defined
  in `pyproject.toml` and implemented in `pep/cli.py` with `argparse`.
- **pytest**: tests are plain functions starting with `test_`;
  **fixtures** (`tests/conftest.py`) set up and clean up shared things
  like the database. `@pytest.mark.slow` marks tests that need real
  models.
- **Ruff** lints and formats; **mypy** type-checks. Both run in CI.
- **Logging**: `structlog` (`pep/log.py`) writes key=value events instead
  of free-text `print`s.

## Words to know
type hint · mypy · dataclass · pydantic · validation · alias ·
environment variable · Protocol · dependency injection · generator ·
context manager · cache · vectorisation · NumPy · async/await · thread ·
process · virtual environment · extras · entry point · fixture

## Workbook 11

**Try it**
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

**Questions**

**1. Why use pydantic for requests instead of plain dicts?**

*Answer:* It validates and converts data at the boundary, so bad input is
rejected with a clear error before it reaches the logic, and the rest of
the code can trust the types.

**2. What problem do generators solve in the frame reader?**

*Answer:* Memory. Frames are produced one at a time as needed, so even
long videos use a small, constant amount of memory.

**3. Why is `Perceiver` a Protocol?**

*Answer:* So anything with the right methods can be used: the real YOLO
perceiver in production, a fake one in tests, or a different detector
later, without changing the pipeline.

**4. When would you choose processes over threads in Python?**

*Answer:* For CPU-heavy work. Python's global interpreter lock lets only
one thread run Python code at a time, so separate processes (or separate
machines, like Pep's workers) are needed for real parallel computation.
