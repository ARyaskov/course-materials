#!/usr/bin/env python3
"""Отчёт по бенчмаркам: сравнение текущего прогона с базовой линией.

Зависимостей нет намеренно: скрипт должен запускаться в CI-контейнере с
голым python3, без pip install. Формат JSON:

    {
      "device": "NVIDIA GeForce RTX 2060",
      "results": [
        {"name": "dim=128 block=256", "median_ms": 1.234, "gbps": 312.0, "gflops": 980.0}
      ]
    }

Режимы:
    bench_report.py current.json --baseline baseline.json [--threshold 0.10]
    bench_report.py --from-text bench.log --output current.json
"""

import argparse
import json
import os
import re
import sys

# Строка таблицы из bench_common.cuh: имя, затем ровно пять чисел.
ROW_RE = re.compile(
    r"^(?P<name>\S.*?)\s+"
    r"(?P<min>-?\d+(?:\.\d+)?)\s+"
    r"(?P<median>-?\d+(?:\.\d+)?)\s+"
    r"(?P<mean>-?\d+(?:\.\d+)?)\s+"
    r"(?P<gbps>-?\d+(?:\.\d+)?)\s+"
    r"(?P<gflops>-?\d+(?:\.\d+)?)\s*$"
)


def parse_text(path):
    """Разбор таблицы, напечатанной микробенчмарком."""
    results = []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("-"):
                continue
            match = ROW_RE.match(line)
            if not match:
                continue
            name = match.group("name").strip()
            # Заголовок таблицы под регулярку не подходит, но подстраховка
            # от строк вида "всего 1 2 3 4 5" лишней не будет.
            if name.lower().startswith(("конфигурация", "шаг чтения", "алгоритм")):
                continue
            results.append(
                {
                    "name": name,
                    "min_ms": float(match.group("min")),
                    "median_ms": float(match.group("median")),
                    "mean_ms": float(match.group("mean")),
                    "gbps": float(match.group("gbps")),
                    "gflops": float(match.group("gflops")),
                }
            )
    return results


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    if isinstance(data, list):
        return {"device": "", "results": data}
    if "results" not in data:
        raise ValueError("в {} нет поля results".format(path))
    return data


def index_by_name(results):
    return {item["name"]: item for item in results}


def compare(current, baseline, threshold):
    """Печатает таблицу и возвращает число регрессий."""
    base_index = index_by_name(baseline.get("results", []))
    regressions = 0

    print("{:<40} {:>12} {:>12} {:>10} {:>10}".format(
        "конфигурация", "текущий, мс", "базовый, мс", "дельта", "вердикт"))
    print("-" * 90)

    for item in current.get("results", []):
        name = item["name"]
        now = item.get("median_ms", 0.0)
        base = base_index.get(name)
        if base is None:
            print("{:<40} {:>12.4f} {:>12} {:>10} {:>10}".format(name, now, "-", "-", "новый"))
            continue

        was = base.get("median_ms", 0.0)
        if was <= 0.0:
            print("{:<40} {:>12.4f} {:>12.4f} {:>10} {:>10}".format(name, now, was, "-", "?"))
            continue

        delta = (now - was) / was
        # Регрессией считается только замедление: ускорение — это то, ради
        # чего всё и затевалось.
        if delta > threshold:
            verdict = "РЕГРЕСС"
            regressions += 1
        elif delta < -threshold:
            verdict = "быстрее"
        else:
            verdict = "ок"
        print("{:<40} {:>12.4f} {:>12.4f} {:>9.1f}% {:>10}".format(
            name, now, was, delta * 100.0, verdict))

    missing = set(base_index) - {item["name"] for item in current.get("results", [])}
    for name in sorted(missing):
        print("{:<40} {:>12} {:>12.4f} {:>10} {:>10}".format(
            name, "-", base_index[name].get("median_ms", 0.0), "-", "пропал"))

    return regressions


def main():
    parser = argparse.ArgumentParser(description="сравнение бенчмарков с базовой линией")
    parser.add_argument("current", nargs="?", help="JSON текущего прогона")
    parser.add_argument("--baseline", help="JSON базовой линии")
    parser.add_argument("--threshold", type=float, default=0.10,
                        help="допустимое замедление, доля (по умолчанию 0.10)")
    parser.add_argument("--from-text", dest="from_text",
                        help="разобрать текстовый вывод бенчмарка и сохранить JSON")
    parser.add_argument("--output", help="куда писать JSON в режиме --from-text")
    parser.add_argument("--device", default="", help="имя карты для записи в JSON")
    args = parser.parse_args()

    if args.from_text:
        results = parse_text(args.from_text)
        payload = {"device": args.device, "results": results}
        text = json.dumps(payload, ensure_ascii=False, indent=2)
        if args.output:
            with open(args.output, "w", encoding="utf-8") as handle:
                handle.write(text + "\n")
            print("Разобрано строк: {} -> {}".format(len(results), args.output))
        else:
            print(text)
        return 0

    if not args.current:
        parser.error("нужен JSON текущего прогона или режим --from-text")

    current = load_json(args.current)
    if not args.baseline or not os.path.exists(args.baseline):
        # Базовой линии ещё нет: печатаем результаты и выходим успешно,
        # иначе первый же запуск CI на новой карте всегда падал бы.
        print("Базовая линия отсутствует, сравнивать не с чем. Текущий прогон:")
        print("{:<40} {:>12} {:>10} {:>10}".format("конфигурация", "мс", "ГБ/с", "GFLOP/s"))
        print("-" * 76)
        for item in current.get("results", []):
            print("{:<40} {:>12.4f} {:>10.1f} {:>10.1f}".format(
                item["name"], item.get("median_ms", 0.0), item.get("gbps", 0.0),
                item.get("gflops", 0.0)))
        return 0

    baseline = load_json(args.baseline)
    if current.get("device") and baseline.get("device") and \
            current["device"] != baseline["device"]:
        print("Внимание: базовая линия снята на другой карте ({} против {}).".format(
            baseline["device"], current["device"]))

    regressions = compare(current, baseline, args.threshold)
    print()
    if regressions:
        print("Регрессий: {} (порог {:.0f}%)".format(regressions, args.threshold * 100))
        return 1
    print("Регрессий нет (порог {:.0f}%)".format(args.threshold * 100))
    return 0


if __name__ == "__main__":
    sys.exit(main())
