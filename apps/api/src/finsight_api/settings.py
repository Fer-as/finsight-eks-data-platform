import json
import os
from pathlib import Path

ROOT = Path(os.environ.get("FINSIGHT_ROOT", Path(__file__).resolve().parents[3]))
DATASET = json.loads((ROOT / "config/synthetic.json").read_text(encoding="utf-8"))
DEFAULT_YEAR = DATASET["year"]
