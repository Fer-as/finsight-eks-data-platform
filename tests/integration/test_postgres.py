"""Run only against the explicit disposable test database, never the app database."""

import importlib.util
import os
from datetime import date
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient
from finsight_api.main import app
from finsight_api.reporting import pounds, report
from finsight_pipelines.etl import load_snapshot, prepare, run
from finsight_pipelines.settings import load_config
from finsight_pipelines.synthetic import generate

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        os.environ.get("FINSIGHT_INTEGRATION") != "1",
        reason="Set FINSIGHT_INTEGRATION=1 with isolated PostgreSQL",
    ),
]
ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def seeded(tmp_path):
    if os.environ.get("PGDATABASE") != "finsight_test":
        pytest.fail("Integration tests require PGDATABASE=finsight_test")
    spec = importlib.util.spec_from_file_location("migration", ROOT / "scripts/migrate.py")
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    with psycopg.connect(autocommit=True) as connection:
        migration.migrate(connection, ROOT / "warehouse/migrations")
        migration.migrate(connection, ROOT / "warehouse/migrations")
        assert connection.execute("SELECT count(*) FROM schema_migrations").fetchone()[0] == 1
    config = {**load_config(), "transactions": 200}
    generated = generate(tmp_path / "raw", config)
    run(tmp_path / "raw", tmp_path, config)
    return tmp_path, config, generated


def test_rerun_is_idempotent_and_totals_reconcile(seeded):
    directory, config, generated = seeded
    with psycopg.connect() as connection:
        before = report(connection, date(2025, 1, 1), date(2026, 1, 1), None)
    run(directory / "raw", directory, config)
    with psycopg.connect() as connection:
        after = report(connection, date(2025, 1, 1), date(2026, 1, 1), None)
        assert connection.execute("SELECT count(*) FROM curated.entries").fetchone()[0] == 288
    assert before["summary"] == after["summary"]
    assert after["summary"]["expense_budget"] == pounds(
        sum(row["amount_pence"] for row in generated["budgets"])
    )
    assert after["summary"]["revenue"] == pounds(
        sum(row["amount_pence"] for row in generated["entries"] if row["kind"] == "revenue")
    )
    assert after["risk"]["total"] == 200
    assert after["risk"]["high"] == 3


def test_failed_load_rolls_back_previous_snapshot(seeded):
    directory, config, _ = seeded
    tables, _ = prepare(directory / "raw", directory / "parquet", directory / "reject", config)
    tables["entries"][0]["department_id"] = "nonexistent"
    with psycopg.connect(autocommit=True) as connection:
        with pytest.raises(psycopg.errors.ForeignKeyViolation):
            load_snapshot(connection, tables)
        assert connection.execute("SELECT count(*) FROM curated.entries").fetchone()[0] == 288


def test_failed_etl_is_recorded_without_erasing_data(seeded):
    directory, config, _ = seeded
    (directory / "raw/entries.csv").write_text("unexpected\nbad\n", encoding="utf-8")
    with pytest.raises(ValueError, match="columns"):
        run(directory / "raw", directory, config)
    with psycopg.connect() as connection:
        assert (
            connection.execute(
                "SELECT status FROM ops.pipeline_runs ORDER BY id DESC LIMIT 1"
            ).fetchone()[0]
            == "failed"
        )
        assert connection.execute("SELECT count(*) FROM curated.entries").fetchone()[0] == 288


def test_api_returns_filtered_exact_data_and_stable_pagination(seeded):
    _, _, generated = seeded
    with TestClient(app) as client:
        assert client.get("/api/health/ready").status_code == 200
        response = client.get("/api/dashboard?start=2025-01-01&end=2025-02-01&department=retail")
        assert response.status_code == 200
        data = response.json()
        assert len(data["monthly"]) == 1
        assert len(data["departments"]) == 1
        assert data["summary"]["expense_budget"] == "65000.00"
        expected = sum(
            row["amount_pence"]
            for row in generated["entries"]
            if row["department_id"] == "retail"
            and row["kind"] == "revenue"
            and row["booked_on"].startswith("2025-01")
        )
        assert data["summary"]["revenue"] == pounds(expected)
        first = client.get("/api/transactions?limit=10").json()
        second = client.get("/api/transactions?limit=10&offset=10").json()
        assert len(first["items"]) == 10 and first["total"] == 200
        assert not ({row["id"] for row in first["items"]} & {row["id"] for row in second["items"]})
        high = client.get("/api/transactions?level=high").json()
        assert high["total"] == 3
        assert all(row["reasons"] == ["high_value", "overnight"] for row in high["items"])
        empty = client.get("/api/dashboard?start=2024-01-01&end=2024-02-01").json()
        assert empty["has_data"] is False
        assert empty["summary"]["margin_percent"] is None
