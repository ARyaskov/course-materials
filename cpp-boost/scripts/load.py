"""Write a demo report locally instead of connecting to a real warehouse."""
import json
import os
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "nightly-report"


def main():
    services = json.loads((DATA_DIR / "summary.json").read_text(encoding="utf-8"))
    report = {"target": os.environ.get("TARGET", "warehouse"), "services": services,
              "total_requests": sum(value["requests"] for value in services.values()),
              "total_errors": sum(value["errors"] for value in services.values())}
    (DATA_DIR / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"saved demo report: requests={report['total_requests']}, errors={report['total_errors']}")


if __name__ == "__main__":
    main()
