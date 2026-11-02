"""Aggregate the local synthetic input by service."""
import json
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "nightly-report"


def main():
    rows = json.loads((DATA_DIR / "source.json").read_text(encoding="utf-8"))
    totals = {}
    for row in rows:
        service = totals.setdefault(row["service"], {"requests": 0, "errors": 0})
        service["requests"] += row["requests"]
        service["errors"] += row["errors"]
    (DATA_DIR / "summary.json").write_text(json.dumps(totals, indent=2) + "\n", encoding="utf-8")
    print(f"aggregated {len(totals)} services")


if __name__ == "__main__":
    main()
