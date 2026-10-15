import time
from datetime import date
from typing import Annotated, Literal

import psycopg
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from finsight_api import reporting
from finsight_api.settings import DEFAULT_YEAR

app = FastAPI(title="FinSight", version="0.1.0", description="Synthetic GBP analytics only")

# Request metrics for Prometheus (G05.4). Labelled by route template, never the raw path, so
# query strings and unknown URLs cannot create unbounded series.
REQUESTS = Counter(
    "finsight_api_requests_total",
    "API requests by method, route and status",
    ["method", "route", "status"],
)
DURATION = Histogram(
    "finsight_api_request_duration_seconds",
    "API request duration by method and route",
    ["method", "route"],
)


@app.middleware("http")
async def record_metrics(request: Request, call_next):
    started = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        path = getattr(route, "path", "unmatched")
        if path != "/metrics":
            REQUESTS.labels(request.method, path, str(status)).inc()
            DURATION.labels(request.method, path).observe(time.perf_counter() - started)


# Scraped in-cluster on the API Service. The Ingress routes only /api to the API, so this
# endpoint is not reachable from outside the cluster.
@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


def database():
    with psycopg.connect(connect_timeout=3, options="-c timezone=UTC") as connection:
        connection.execute("SET TRANSACTION READ ONLY")
        yield connection


def period(start: date = date(DEFAULT_YEAR, 1, 1), end: date = date(DEFAULT_YEAR + 1, 1, 1)):
    if start.day != 1 or end.day != 1 or end <= start:
        raise HTTPException(
            422, "Use complete months: start and exclusive end must be month starts"
        )
    if (end.year - start.year) * 12 + end.month - start.month > 60:
        raise HTTPException(422, "Maximum reporting period is 60 months")
    return start, end


Database = Annotated[psycopg.Connection, Depends(database)]
Period = Annotated[tuple, Depends(period)]
Department = Annotated[str | None, Query(max_length=40, pattern=r"^[a-z][a-z0-9_-]*$")]


@app.exception_handler(psycopg.Error)
async def database_error(_request, _error):
    return JSONResponse(
        status_code=503, content={"detail": "Database unavailable or not initialised"}
    )


@app.get("/api/health/live")
def live():
    return {"status": "ok"}


@app.get("/api/config")
def configuration():
    return {"start_month": f"{DEFAULT_YEAR}-01", "end_month": f"{DEFAULT_YEAR}-12"}


@app.get("/api/health/ready")
def ready(connection: Database):
    connection.execute("SELECT 1 FROM curated.departments LIMIT 1")
    return {"status": "ready"}


@app.get("/api/departments")
def departments(connection: Database):
    return [
        {"id": row[0], "name": row[1]}
        for row in connection.execute(
            "SELECT id,name FROM curated.departments ORDER BY name"
        ).fetchall()
    ]


@app.get("/api/dashboard")
def dashboard(window: Period, connection: Database, department: Department = None):
    return reporting.report(connection, *window, department)


@app.get("/api/transactions")
def transactions(
    window: Period,
    connection: Database,
    department: Department = None,
    level: Literal["low", "medium", "high"] | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    return reporting.transactions(connection, *window, department, level, limit, offset)
