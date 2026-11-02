"""Create synthetic usage data for the teaching pipeline; no external service is used."""
import json
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "nightly-report"


def main():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    rows = [
        {"service": "api", "requests": 120, "errors": 2},
        {"service": "web", "requests": 80, "errors": 1},
        {"service": "api", "requests": 60, "errors": 0},
    ]
    (DATA_DIR / "source.json").write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
    print(f"extracted {len(rows)} synthetic usage rows")


if __name__ == "__main__":
    main()
