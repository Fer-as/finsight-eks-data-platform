"""Extract CSV, transform with Pandas, persist Parquet, then load PostgreSQL."""

import argparse
import hashlib
import json
import re
from datetime import date, datetime, timezone
from pathlib import Path

import pandas as pd
import psycopg
from psycopg import sql
from psycopg.types.json import Jsonb

from finsight_pipelines.settings import ROOT, load_config

COLUMNS = {
    "departments": ["id", "name"],
    "entries": ["id", "booked_on", "department_id", "kind", "amount_pence", "currency"],
    "budgets": ["month", "department_id", "amount_pence", "currency"],
    "transactions": [
        "id",
        "occurred_at",
        "department_id",
        "account_ref",
        "amount_pence",
        "currency",
    ],
}


def risk_indicator(amount_pence: int, occurred_at: datetime, config: dict) -> tuple[str, str]:
    reasons = []
    if amount_pence >= config["high_value_pence"]:
        reasons.append("high_value")
    if occurred_at.astimezone(timezone.utc).hour < config["overnight_before_hour_utc"]:
        reasons.append("overnight")
    return ("high" if len(reasons) == 2 else "medium" if reasons else "low", ",".join(reasons))


def transform(name: str, frame: pd.DataFrame, config: dict) -> tuple[pd.DataFrame, list, int]:
    if set(frame.columns) != set(COLUMNS[name]):
        raise ValueError(f"{name}: unexpected or missing columns")
    accepted, rejected, seen = [], [], {}
    duplicates = 0
    departments = {d["id"] for d in config["departments"]}
    for source in frame.to_dict(orient="records"):
        row = dict(source)
        try:
            if any(not isinstance(value, str) or not value.strip() for value in row.values()):
                raise ValueError("Missing value")
            if name == "departments":
                if row["id"] not in departments:
                    raise ValueError("Unknown department")
            else:
                if row["department_id"] not in departments or row["currency"] != "GBP":
                    raise ValueError("Unknown department or non-GBP currency")
                if not re.fullmatch(r"[0-9]+", row["amount_pence"]):
                    raise ValueError("Amount must be integer pence")
                row["amount_pence"] = int(row["amount_pence"])
                if not 0 < row["amount_pence"] <= 1_000_000_000_000:
                    raise ValueError("Amount outside supported range")
                if name == "entries":
                    row["booked_on"] = date.fromisoformat(row["booked_on"])
                    if row["kind"] not in {"revenue", "expense"}:
                        raise ValueError("Unknown entry kind")
                elif name == "budgets":
                    row["month"] = date.fromisoformat(row["month"])
                    if row["month"].day != 1:
                        raise ValueError("Budget must start on the first of the month")
                else:
                    timestamp = datetime.fromisoformat(row["occurred_at"])
                    if timestamp.tzinfo is None:
                        raise ValueError("Timestamp must include timezone")
                    row["occurred_at"] = timestamp.astimezone(timezone.utc)
                    if not re.fullmatch(r"SYN-[0-9]{4}", row["account_ref"]):
                        raise ValueError("Expected synthetic account reference")
                    row["risk_level"], row["risk_reasons"] = risk_indicator(
                        row["amount_pence"], row["occurred_at"], config
                    )
        except (ValueError, TypeError, OverflowError) as error:
            rejected.append({"row": source, "reason": str(error)})
            continue
        key = (row["month"], row["department_id"]) if name == "budgets" else row["id"]
        if key in seen:
            if seen[key] != row:
                raise ValueError(f"{name}: conflicting duplicate key {key}")
            duplicates += 1
            continue
        seen[key] = row
        accepted.append(row)
    extra = ["risk_level", "risk_reasons"] if name == "transactions" else []
    return pd.DataFrame(accepted, columns=COLUMNS[name] + extra), rejected, duplicates


def source_hash(directory: Path, config: dict) -> str:
    digest = hashlib.sha256(json.dumps(config, sort_keys=True).encode())
    for name in COLUMNS:
        digest.update(name.encode())
        digest.update((directory / f"{name}.csv").read_bytes())
    return digest.hexdigest()


def prepare(source: Path, output: Path, rejected_dir: Path, config: dict) -> tuple[dict, dict]:
    output.mkdir(parents=True, exist_ok=True)
    rejected_dir.mkdir(parents=True, exist_ok=True)
    tables, counts = {}, {}
    for name in COLUMNS:
        frame = pd.read_csv(source / f"{name}.csv", dtype=str, keep_default_na=False)
        clean, rejected, duplicates = transform(name, frame, config)
        (rejected_dir / f"{name}.json").write_text(json.dumps(rejected, indent=2), encoding="utf-8")
        if clean.empty:
            raise ValueError(f"{name}: no valid records; previous database snapshot retained")
        clean.to_parquet(output / f"{name}.parquet", index=False)
        # PostgreSQL receives the actual Parquet output, not a separate in-memory branch.
        tables[name] = pd.read_parquet(output / f"{name}.parquet").to_dict(orient="records")
        counts[name] = dict(
            source=len(frame), accepted=len(clean), rejected=len(rejected), duplicates=duplicates
        )
    return tables, counts


def load_snapshot(connection, tables: dict) -> None:
    """One small full snapshot per run. All tables roll back on any load failure."""
    with connection.transaction():
        connection.execute("SELECT pg_advisory_xact_lock(731002)")
        connection.execute("""TRUNCATE curated.transactions, curated.entries,
                           curated.budgets, curated.departments""")
        for name, rows in tables.items():
            columns = list(rows[0])
            statement = sql.SQL("INSERT INTO curated.{} ({}) VALUES ({})").format(
                sql.Identifier(name),
                sql.SQL(",").join(map(sql.Identifier, columns)),
                sql.SQL(",").join(sql.Placeholder() for _ in columns),
            )
            with connection.cursor() as cursor:
                cursor.executemany(
                    statement, [tuple(row[column] for column in columns) for row in rows]
                )


def run(source: Path, data_dir: Path, config: dict) -> dict:
    fingerprint = source_hash(source, config)
    with psycopg.connect(connect_timeout=5, autocommit=True) as connection:
        run_id = connection.execute(
            "INSERT INTO ops.pipeline_runs(status, source_sha256) VALUES ('running', %s) "
            "RETURNING id",
            (fingerprint,),
        ).fetchone()[0]
        try:
            tables, counts = prepare(
                source,
                data_dir / "curated" / fingerprint,
                data_dir / "rejected" / fingerprint,
                config,
            )
            with connection.transaction():
                load_snapshot(connection, tables)
                connection.execute(
                    "UPDATE ops.pipeline_runs SET status='succeeded', finished_at=now(), "
                    "counts=%s WHERE id=%s",
                    (Jsonb(counts), run_id),
                )
        except Exception as error:
            connection.execute(
                "UPDATE ops.pipeline_runs SET status='failed', finished_at=now(), error=%s "
                "WHERE id=%s",
                (type(error).__name__, run_id),
            )
            raise
    result = dict(run_id=run_id, source_sha256=fingerprint, counts=counts)
    print(json.dumps(result, indent=2))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "data/raw")
    args = parser.parse_args()
    run(args.source, ROOT / "data", load_config())
