"""Проверка окружения перед началом работы над проектом.

Скрипт из первой главы. Он не импортирует depot и ничего не требует
установленным: его задача — сказать, чего не хватает, до того как об этом
скажет непонятная ошибка импорта.

Запуск: python check_env.py
"""

import importlib.metadata
import platform
import shutil
import sys

MIN_PYTHON = (3, 15)

#: минимальные версии, объявленные контрактом курса
REQUIRED_PACKAGES: dict[str, str] = {
    "flask": "3.1",
    "sqlalchemy": "2.0",
    "pydantic": "2.9",
    "alembic": "1.14",
    "psycopg": "3.2",
}

#: внешние программы: их отсутствие проявится позже и менее внятно
REQUIRED_TOOLS = ("docker", "git")


def version_tuple(raw: str) -> tuple[int, ...]:
    """Разбор версии для сравнения.

    Сравнение строк здесь не работает: "3.10" меньше "3.9" лексикографически.
    """
    parts: list[int] = []
    for chunk in raw.split(".")[:3]:
        digits = "".join(c for c in chunk if c.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts)


def check_python() -> bool:
    actual = sys.version_info[:2]
    ok = actual >= MIN_PYTHON
    mark = "ok" if ok else "нужна версия не ниже " + ".".join(map(str, MIN_PYTHON))
    print(f"Python {platform.python_version()} — {mark}")
    return ok


def check_packages() -> bool:
    ok = True
    for name, minimum in REQUIRED_PACKAGES.items():
        try:
            installed = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            print(f"{name} — не установлен")
            ok = False
            continue

        if version_tuple(installed) < version_tuple(minimum):
            print(f"{name} {installed} — нужна версия не ниже {minimum}")
            ok = False
        else:
            print(f"{name} {installed} — ok")
    return ok


def check_tools() -> bool:
    ok = True
    for tool in REQUIRED_TOOLS:
        path = shutil.which(tool)
        if path is None:
            print(f"{tool} — не найден в PATH")
            ok = False
        else:
            print(f"{tool} — {path}")
    return ok


def main() -> int:
    print("Проверка окружения\n")
    results = [check_python(), check_packages(), check_tools()]
    print()
    if all(results):
        print("Окружение готово.")
        return 0
    print("Окружение не готово: устраните замечания выше.")
    # ненулевой код возврата: скрипт можно поставить в конвейер сборки
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
