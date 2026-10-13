import json
import os
from pathlib import Path

ROOT = Path(os.environ.get("FINSIGHT_ROOT", Path(__file__).resolve().parents[3]))


def load_config(path: Path | None = None) -> dict:
    config = json.loads((path or ROOT / "config/synthetic.json").read_text(encoding="utf-8"))
    departments = config["departments"]
    ids = [d["id"] for d in departments]
    if config["currency"] != "GBP" or not departments or len(ids) != len(set(ids)):
        raise ValueError("Expected GBP and unique, non-empty departments")
    if config["transactions"] < 2 or config["high_value_pence"] <= 0:
        raise ValueError("Expected at least two transactions and a positive risk threshold")
    if not 1 <= config["overnight_before_hour_utc"] <= 23:
        raise ValueError("Invalid overnight hour")
    return config
