"""
Structured logging.

Instead of `print("job 42 failed after 3.1s")`, we log events with fields:

    log.info("job.failed", job_id=42, seconds=3.1)

In production each line comes out as JSON:

    {"event": "job.failed", "job_id": 42, "seconds": 3.1, "level": "info", "timestamp": "..."}

Log platforms (Render's log view, Grafana Loki, Datadog...) can then filter
and graph by field: "every failed job this week", "p95 seconds". Locally the
same events print in colour for humans.

`bind_contextvars(job_id=...)` attaches a field to every log line written in
the current request/job without passing it around: that is how you follow
one job through many modules.
"""

from __future__ import annotations

import logging
import sys

import structlog

from .config import settings


def setup_logging() -> None:
    level = getattr(logging, settings().log_level.upper(), logging.INFO)
    renderer = (
        structlog.processors.JSONRenderer()
        if settings().env == "prod"
        else structlog.dev.ConsoleRenderer(colors=sys.stderr.isatty())
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(level),
        logger_factory=structlog.PrintLoggerFactory(file=sys.stderr),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str) -> structlog.typing.FilteringBoundLogger:
    return structlog.get_logger(name)
