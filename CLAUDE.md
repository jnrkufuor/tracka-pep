# CLAUDE.md

Guidance for AI coding assistants working in this repo.

- **What this is**: Pep, Tracka's outside coach model. The contract with
  tracka-api is in `pep/contracts.py` and must stay compatible with
  tracka-api's `coachResultSchema` (src/services/coach.ts). Run
  `tests/test_contracts.py` after any change there.
- **The owner is learning AI and SRE with this project.** Keep the
  teaching-style docstrings: explain *why*, name the concept, and point to
  the handbook chapter. When adding a feature, add a workbook exercise to
  the matching `docs/handbook/` chapter.
- **Map**: `docs/CODEMAP.md`. Pipeline entry point: `pep/pipeline.py`.
- **Checks before committing**: `ruff check pep tests scripts training deploy`,
  `ruff format --check …`, `mypy pep`, `pytest`; `pytest -m slow` for vision changes.
- **Versioning**: bump `MODEL_VERSION` in `pep/__init__.py` when
  measurements, norms or scoring change. Run `training/evaluate.py` on the
  benchmark and report the before/after numbers.
- **Numbers come from measurement, never from the LLM.** The coach adds
  words, moments and `ai_observed` skills only.
- **Brand**: edit `scripts/build_brand.py`, then run it. Don't hand-edit
  generated files in `web/assets/brand`, `web/assets/icons` or `icons.js`.
- **No secrets in git.** Settings come from env vars (`pep/config.py`).
