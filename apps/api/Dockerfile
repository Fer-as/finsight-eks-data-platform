# Python images for FinSight. Targets:
#   api     - production FastAPI image (ECR repository "api")
#   etl     - production ETL image (ECR repository "etl")
#   runtime - local Compose image that runs migrate, generate, ETL and the API
#   test    - lint and tests
# The base image is pinned by digest so builds are reproducible; update the digest deliberately.
FROM python:3.12-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1 AS python-os
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1 FINSIGHT_ROOT=/app
RUN useradd --create-home --uid 10001 finsight
COPY requirements.lock .

FROM python-os AS python-base
RUN pip install --no-cache-dir -r requirements.lock

FROM python-base AS runtime
ENV PYTHONPATH=/app/apps/api/src:/app/pipelines/src
COPY apps/api/src apps/api/src
COPY pipelines/src pipelines/src
COPY config config
COPY warehouse/migrations warehouse/migrations
COPY scripts scripts
RUN mkdir -p /app/data && chown -R finsight:finsight /app/data
USER finsight
EXPOSE 8000
CMD ["uvicorn", "finsight_api.main:app", "--host", "0.0.0.0", "--port", "8000"]

# Production API: only the API code and the one configuration file it reads. Database settings
# come from the standard PG* environment variables at run time; nothing is baked in.
FROM python-os AS api
# Only the API's own dependencies (no pandas/numpy/pyarrow), at the versions pinned in the lock.
RUN pip install --no-cache-dir -c requirements.lock fastapi uvicorn psycopg psycopg-binary
ENV PYTHONPATH=/app/apps/api/src
COPY config/synthetic.json config/synthetic.json
COPY apps/api/src apps/api/src
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health/live', timeout=4)"]
CMD ["uvicorn", "finsight_api.main:app", "--host", "0.0.0.0", "--port", "8000"]

# Production ETL: pipeline code, migrations and configuration. A batch job, so no health check.
# It reads raw files under /app/data (mount a volume) and writes to PostgreSQL via PG* variables.
FROM python-base AS etl
ENV PYTHONPATH=/app/pipelines/src
COPY config config
COPY pipelines/src pipelines/src
COPY warehouse/migrations warehouse/migrations
COPY scripts/migrate.py scripts/migrate.py
RUN mkdir -p /app/data && chown finsight:finsight /app/data
USER 10001
HEALTHCHECK NONE
CMD ["python", "-m", "finsight_pipelines.etl"]

FROM runtime AS test
USER root
COPY requirements-dev.lock .
RUN pip install --no-cache-dir -r requirements-dev.lock
COPY pyproject.toml .
COPY apps/api/tests apps/api/tests
COPY pipelines/tests pipelines/tests
COPY tests tests
USER finsight
CMD ["sh", "-c", "ruff check --no-cache . && ruff format --check --no-cache . && pytest -q -p no:cacheprovider"]
