import csv
from datetime import datetime, timezone

import pandas as pd
import pytest
from finsight_pipelines.etl import prepare, risk_indicator, source_hash, transform
from finsight_pipelines.settings import load_config
from finsight_pipelines.synthetic import generate


@pytest.fixture
def config():
    return {**load_config(), "transactions": 200}


def test_generator_is_deterministic_and_has_injected_risk(tmp_path, config):
    a, b = tmp_path / "a", tmp_path / "b"
    tables = generate(a, config)
    assert tables == generate(b, config)
    assert source_hash(a, config) == source_hash(b, config)
    assert len(tables["entries"]) == 288
    assert len(tables["budgets"]) == 36
    assert all(row["currency"] == "GBP" for row in tables["transactions"])
    assert tables["transactions"][0]["amount_pence"] >= config["high_value_pence"]


@pytest.mark.parametrize(
    "amount,hour,level,reasons",
    [
        (999999, 6, "low", ""),
        (1000000, 6, "medium", "high_value"),
        (999999, 5, "medium", "overnight"),
        (1000000, 5, "high", "high_value,overnight"),
    ],
)
def test_risk_boundaries(config, amount, hour, level, reasons):
    assert risk_indicator(amount, datetime(2025, 1, 1, hour, tzinfo=timezone.utc), config) == (
        level,
        reasons,
    )


def test_risk_normalises_timezone(config):
    timestamp = datetime.fromisoformat("2025-01-01T07:00:00+02:00")
    assert risk_indicator(100, timestamp, config) == ("medium", "overnight")


def entry():
    return dict(
        id="e1",
        booked_on="2025-01-01",
        department_id="retail",
        kind="revenue",
        amount_pence="10001",
        currency="GBP",
    )


@pytest.mark.parametrize(
    "field,value",
    [
        ("amount_pence", "10.01"),
        ("amount_pence", "-1"),
        ("amount_pence", "0"),
        ("amount_pence", "1000000000001"),
        ("currency", "USD"),
        ("booked_on", "2025-02-30"),
        ("department_id", "missing"),
        ("kind", "transfer"),
        ("id", ""),
    ],
)
def test_invalid_records_are_quarantined(config, field, value):
    clean, rejected, duplicates = transform(
        "entries", pd.DataFrame([entry(), {**entry(), "id": "bad", field: value}]), config
    )
    assert clean["amount_pence"].tolist() == [10001]
    assert len(rejected) == 1
    assert rejected[0]["reason"]
    assert duplicates == 0


def test_duplicate_policy(config):
    clean, rejected, duplicates = transform("entries", pd.DataFrame([entry(), entry()]), config)
    assert len(clean) == 1 and not rejected and duplicates == 1
    with pytest.raises(ValueError, match="conflicting duplicate"):
        transform("entries", pd.DataFrame([entry(), {**entry(), "amount_pence": "10002"}]), config)


def test_missing_column_fails(config):
    with pytest.raises(ValueError, match="columns"):
        transform("entries", pd.DataFrame([{"id": "e1"}]), config)


def test_parquet_reconciles_and_counts_rejections(tmp_path, config):
    source = tmp_path / "raw"
    generated = generate(source, config)
    with (source / "entries.csv").open("a", newline="", encoding="utf-8") as handle:
        csv.writer(handle).writerow(["bad", "2025-01-01", "retail", "revenue", "0", "GBP"])
    tables, counts = prepare(source, tmp_path / "curated", tmp_path / "rejected", config)
    assert counts["entries"] == dict(source=289, accepted=288, rejected=1, duplicates=0)
    assert sum(row["amount_pence"] for row in tables["entries"]) == sum(
        row["amount_pence"] for row in generated["entries"]
    )
    assert tables["transactions"][0]["risk_level"] == "high"
    assert "Amount outside" in (tmp_path / "rejected/entries.json").read_text()


def test_empty_source_fails_instead_of_erasing_snapshot(tmp_path, config):
    source = tmp_path / "raw"
    generate(source, config)
    (source / "entries.csv").write_text(
        "id,booked_on,department_id,kind,amount_pence,currency\n", encoding="utf-8"
    )
    with pytest.raises(ValueError, match="no valid records"):
        prepare(source, tmp_path / "curated", tmp_path / "rejected", config)


def test_naive_transaction_timestamp_is_rejected(config):
    frame = pd.DataFrame(
        [
            dict(
                id="t1",
                occurred_at="2025-01-01T03:00:00",
                department_id="retail",
                account_ref="SYN-0001",
                amount_pence="100",
                currency="GBP",
            )
        ]
    )
    clean, rejected, _ = transform("transactions", frame, config)
    assert clean.empty and "timezone" in rejected[0]["reason"]
