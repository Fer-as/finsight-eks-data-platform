FROM python:3.12-slim AS runtime
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/apps/api/src:/app/pipelines/src FINSIGHT_ROOT=/app
COPY requirements.lock .
RUN pip install --no-cache-dir -r requirements.lock \
    && useradd --create-home --uid 10001 finsight
COPY apps/api/src apps/api/src
COPY pipelines/src pipelines/src
COPY config config
COPY warehouse/migrations warehouse/migrations
COPY scripts scripts
RUN mkdir -p /app/data && chown -R finsight:finsight /app/data
USER finsight
EXPOSE 8000
CMD ["uvicorn", "finsight_api.main:app", "--host", "0.0.0.0", "--port", "8000"]

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
