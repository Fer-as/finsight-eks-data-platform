"""No wall-clock time, random UUIDs, real identities or external data sources."""

import csv
import random
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from finsight_pipelines.settings import ROOT, load_config


def write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def generate(directory: Path, config: dict) -> dict[str, list[dict]]:
    rng = random.Random(config["seed"])
    year = config["year"]
    currency = config["currency"]
    departments = [{"id": d["id"], "name": d["name"]} for d in config["departments"]]
    entries, budgets, transactions = [], [], []
    for month in range(1, 13):
        for department in config["departments"]:
            dep = department["id"]
            budget = department["monthly_budget_pence"]
            budgets.append(
                dict(
                    month=f"{year}-{month:02}-01",
                    department_id=dep,
                    amount_pence=budget,
                    currency=currency,
                )
            )
            # Four entries of each kind per department/month: realistic join fan-out fixture.
            for kind, low, high in [("revenue", 30, 43), ("expense", 20, 30)]:
                for part in range(4):
                    entries.append(
                        dict(
                            id=f"entry-{month:02}-{dep}-{kind}-{part}",
                            booked_on=f"{year}-{month:02}-{(part + 1) * 6:02}",
                            department_id=dep,
                            kind=kind,
                            amount_pence=budget * rng.randint(low, high) // 100,
                            currency=currency,
                        )
                    )
    start = datetime(year, 1, 1, tzinfo=timezone.utc)
    seconds = (date(year + 1, 1, 1) - date(year, 1, 1)).days * 86400
    for index in range(config["transactions"]):
        timestamp = start + timedelta(seconds=rng.randrange(seconds))
        amount = rng.randint(100, config["high_value_pence"] - 1)
        # Known cases; no label is supplied to the detector.
        if index % 97 == 0:
            amount = config["high_value_pence"] + rng.randint(0, 2000000)
            timestamp = timestamp.replace(hour=2)
        transactions.append(
            dict(
                id=f"txn-{index:06}",
                occurred_at=timestamp.isoformat(),
                department_id=departments[index % len(departments)]["id"],
                account_ref=f"SYN-{index % 200:04}",
                amount_pence=amount,
                currency=currency,
            )
        )
    tables = dict(
        departments=departments, entries=entries, budgets=budgets, transactions=transactions
    )
    directory.mkdir(parents=True, exist_ok=True)
    for name, rows in tables.items():
        write_csv(directory / f"{name}.csv", rows)
    return tables


if __name__ == "__main__":
    tables = generate(ROOT / "data/raw", load_config())
    print({name: len(rows) for name, rows in tables.items()})
