# The API image: FastAPI + Pep Lab, no PyTorch (~250 MB). Render builds this file.
# The GPU/CPU worker has its own file, Dockerfile.worker (Render can't choose a
# stage inside one Dockerfile, so two files keeps both platforms simple).
#
#   docker build -t pep-api .
#
# Layer caching: Docker re-runs a step only if it or something before it
# changed. We copy pyproject.toml and install dependencies BEFORE copying the
# code, so editing a .py file doesn't reinstall every package.
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
ENV PYTHONPATH=/app
# Run as a normal user, not root: if something is ever exploited, it can do less.
RUN useradd --create-home --uid 10001 pep

COPY pyproject.toml README.md ./
# Install only the dependencies first (cached layer): install with an empty package stub,
# then uninstall the stub so only the dependencies stay. Our code runs from /app (PYTHONPATH).
RUN mkdir -p pep && touch pep/__init__.py && pip install . && pip uninstall -y tracka-pep && rm -rf pep
COPY pep ./pep
COPY web ./web
RUN mkdir -p var && chown -R pep var
USER pep
EXPOSE 8000
# Render (and most platforms) tell the app which port to use in $PORT.
CMD ["sh", "-c", "uvicorn pep.api.app:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
