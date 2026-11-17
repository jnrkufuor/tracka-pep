# CLAUDE.md

Guidance for AI coding assistants working in this repo.

- **What this is**: the Tracka player app (`app/`, Flutter: Android, iOS,
  web) and its API + AI coach Pep (`pep/`). Players only for now: profile,
  uploads, video library, Pep's scores and tips, settings. Scouts and
  opportunities come later as a separate app on the same API, so keep new
  work extensible (new tables that point at `users`, not changes to them).
- **The app's API** is `/v1` in `pep/players/`. Every query is filtered by
  the logged-in user; keep `tests/test_player_api.py` covering that. Don't
  break `/v1` for installed apps: add fields, don't rename them.
- **The old outside-coach contract** with tracka-api is `pep/contracts.py`
  and must stay compatible with tracka-api's `coachResultSchema`. Run
  `tests/test_contracts.py` after any change there.
- **The owner is learning AI and SRE with this project.** Keep the
  teaching-style docstrings: explain *why*, name the concept, and point to
  the handbook chapter. When adding a feature, add a workbook exercise to
  the matching `docs/handbook/` chapter.
- **Map**: `docs/CODEMAP.md`. Pipeline entry point: `pep/pipeline.py`.
- **Checks before committing**: `ruff check pep tests scripts training deploy`,
  `ruff format --check …`, `mypy pep`, `pytest`; `pytest -m slow` for vision changes.
  App: `cd app && flutter analyze && flutter test` (CI runs these in `app.yml`).
- **Handbook style**: each chapter explains the general concept first, like
  to a first-year student, then common approaches, then how Tracka does it,
  then words to know and a workbook with answers.
- **Versioning**: bump `MODEL_VERSION` in `pep/__init__.py` when
  measurements, norms or scoring change. Run `training/evaluate.py` on the
  benchmark and report the before/after numbers.
- **Numbers come from measurement, never from the LLM.** The coach adds
  words, moments and `ai_observed` skills only.
- **Brand**: edit `scripts/build_brand.py`, then run it. Don't hand-edit
  generated files in `web/assets/brand`, `web/assets/icons`, `icons.js`,
  `app/assets/brand` or `app/lib/widgets/loopy_icons.g.dart`.
- **No secrets in git.** Settings come from env vars (`pep/config.py`).
