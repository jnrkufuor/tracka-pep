# 07 · Python toolbox: the good stuff used in Pep

Each item: what it is, where Pep uses it, and why it's worth knowing.

## Generators (`yield`): process big data one piece at a time
```python
def sample_frames(path, ...):            # pep/video/frames.py
    while True:
        ...
        yield Frame(index, t, image, scale)
```
A function with `yield` returns an iterator that produces values **lazily**.
A 3-minute clip never sits in memory all at once: the pipeline pulls one
frame, analyses it, drops it, and pulls the next. The `try/finally` around
the loop releases the video decoder even if the caller stops early.

## Context managers: setup and cleanup that can't be forgotten
```python
@contextmanager                           # pep/pipeline.py
def stage(self, name):
    start = time.perf_counter()
    try:
        yield
    finally:
        self.timings[name] = time.perf_counter() - start

with timer.stage("perception"):
    ...
```
Also used: `with engine().begin() as c:` (commit on success, roll back on
error), `tempfile.TemporaryDirectory()` (always deleted), and
`contextlib.suppress(Exception)` for best-effort cleanup.

## `typing.Protocol`: interfaces without inheritance
```python
class Perceiver(Protocol):                # pep/vision/perception.py
    def observe(self, image: np.ndarray) -> tuple[list[Person], Box | None]: ...
    def reset(self) -> None: ...
```
Anything with those methods *is* a `Perceiver` ("structural typing", or
duck typing that mypy can check). The tests pass a `FakePerceiver` with no
PyTorch at all. Swapping YOLO for another model only needs a new class.

## Dataclasses: classes for data, without boilerplate
`@dataclass` writes `__init__`, `__repr__` and `__eq__` for you
(`Box`, `Frame`, `TargetSample`, `Kinematics`). `frozen=True` makes
instances immutable (`VideoInfo`). `field(default_factory=list)` avoids
the classic shared-mutable-default bug.

## Pydantic: validation at the edges
`pep/contracts.py`: types + constraints (`Field(ge=0, le=100)`,
`max_length`) are checked when data *enters* the system. FastAPI uses
them to validate requests and generate `/docs`. `alias_generator=to_camel`
gives camelCase JSON and snake_case Python. `pydantic-settings` reads env
vars into typed settings (`pep/config.py`).

## Caching: `functools.cache` / `lru_cache`
`settings()`, `engine()`, `norms()`, `roles()`: computed once, then reused.
A cheap, safe singleton. Tests call `.cache_clear()` when they need a fresh
one.

## The walrus operator `:=`
```python
while chunk := await video.read(1 << 20):   # pep/api/app.py: read until empty
    ...
```
Assign and test in one expression. `1 << 20` is 1 MiB (bit shift).

## Structured logging with context variables
`structlog.contextvars.bind_contextvars(request_id=...)` attaches a field
to every log line in the current request, even deep inside other modules,
without passing it around. Context variables are like thread-locals that
also work with `async`.

## Threads and events: the heartbeat
```python
stop = threading.Event()                         # pep/worker.py
threading.Thread(target=self._heartbeat, args=(job_id, stop), daemon=True).start()
...
while not stop.wait(every):   # sleeps `every` seconds, or wakes instantly when stop.set()
    db.heartbeat(...)
```
`Event.wait(timeout)` is an interruptible sleep: perfect for loops that
must stop quickly. `daemon=True` means the thread won't keep the process
alive.

## Signal handling: graceful shutdown
```python
signal.signal(signal.SIGTERM, lambda *_: self.stop())
```
Platforms stop containers with SIGTERM, then SIGKILL. Catching SIGTERM
lets the worker finish its clip.

## NumPy patterns
- **Boolean masks**: `speed[ok] > JOG_MS`, then `np.mean(mask)` gives a share.
- **NaN-aware maths**: `np.nanmax`, `np.nansum`, `np.isfinite`. Missing
  frames are `NaN`, not zero (zero would mean "standing still").
- **Angle wrapping with complex numbers**:
  `np.abs(np.angle(np.exp(1j * (a - b))))` gives the smallest angle
  between headings, handling the 359° → 1° wrap-around in one line.
- **Homogeneous coordinates**: stack `[0, 0, 1]` under a 2×3 affine to get
  3×3 and compose transforms by matrix multiplication (`camera._h`).
- **`np.linalg.inv`, `@`**: the Kalman filter is about 15 lines of matrix
  algebra.

## `zip(..., strict=True)`
Raises if the iterables have different lengths, instead of silently
truncating. A whole class of bugs, gone.

## f-string formatting
`f"{speed * 3.6:.1f} km/h"`, `f"{share:.0%}"` (formats 0.42 as "42%"),
`f"{name:<16}"` (left-align in 16 characters).

## `argparse` sub-commands
`pep analyse | worker | drain | serve` (`pep/cli.py`), registered as a
console script in `pyproject.toml` (`[project.scripts]`).

## Testing patterns (`tests/`)
- **Fixtures** (`conftest.py`) give each test fresh resources (an empty
  database, a blank video, a fake perceiver).
- **`monkeypatch`** swaps settings or `sys.argv` for one test.
- **`httpx.MockTransport`** fakes Tracka's callback endpoint: no network.
- **Known-answer tests**: synthetic trajectories and clips where we know
  the truth.
- **Markers**: `@pytest.mark.slow` separates real-model tests.

---

## Workbook 07

1. Rewrite `sample_frames` to also yield every Nth frame as a JPEG
   thumbnail without changing its callers. (Hint: a second generator that
   wraps the first.)
2. Write a context manager `timed_log(name)` that logs
   `stage.done seconds=…` with structlog, and use it in `worker.process`.
3. Implement a `SlowPerceiver(Protocol)` adapter that wraps any perceiver
   and skips every other frame. Run the pipeline with it. How does
   top speed change?
4. Replace the `for` loop in `segments()` with a vectorised NumPy version
   (`np.diff`, `np.flatnonzero`). Keep the tests green.

<details><summary>Why do missing frames use NaN instead of 0?</summary>

0 is a real value (standing still, or ball at the feet). NaN says "unknown",
and NaN-aware functions skip it. Using 0 would invent stillness and drag
averages down.
</details>
