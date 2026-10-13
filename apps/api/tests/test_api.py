from datetime import date

import psycopg
import pytest
from fastapi.testclient import TestClient
from finsight_api.main import app, database, period
from finsight_api.reporting import percent, pounds


@pytest.fixture
def client():
    app.dependency_overrides[database] = lambda: None
    with TestClient(app) as instance:
        yield instance
    app.dependency_overrides.clear()


def test_money_is_exact():
    assert pounds(10001) == "100.01"
    assert pounds(-1) == "-0.01"
    assert pounds(9007199254740993) == "90071992547409.93"
    assert percent(1, 6) == "16.67"
    assert percent(1, 0) is None
    assert percent(-1, 8) == "-12.50"


def test_liveness_never_requires_database(client):
    assert client.get("/api/health/live").json() == {"status": "ok"}


@pytest.mark.parametrize(
    "query",
    [
        "start=2025-01-02",
        "start=2026-01-01&end=2025-01-01",
        "start=not-a-date",
        "start=2020-01-01&end=2026-01-01",
        "department=retail%27%3BDELETE",
    ],
)
def test_invalid_filters_return_422(client, query):
    assert client.get(f"/api/dashboard?{query}").status_code == 422


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1", "level=critical"])
def test_transaction_validation(client, query):
    assert client.get(f"/api/transactions?{query}").status_code == 422


def test_database_failure_is_sanitised(client):
    def broken():
        raise psycopg.OperationalError("private connection details")

    app.dependency_overrides[database] = broken
    response = client.get("/api/health/ready")
    assert response.status_code == 503
    assert "private" not in response.text
    assert client.get("/api/health/live").status_code == 200


def test_period_uses_exclusive_month_boundary():
    assert period(date(2025, 12, 1), date(2026, 1, 1)) == (date(2025, 12, 1), date(2026, 1, 1))
