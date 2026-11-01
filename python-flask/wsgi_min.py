"""Приложение WSGI без фреймворка.

Пример из второй главы: он показывает, с чем на самом деле работает Flask.
Приложение WSGI — это вызываемый объект двух аргументов: словаря окружения
и функции, которой сообщают статус и заголовки. Всё остальное —
маршрутизация, разбор тела, объект запроса — надстройка над этим.

Запуск: python wsgi_min.py, затем http://127.0.0.1:8001/
"""

import json
from collections.abc import Callable, Iterable

#: тип функции обратного вызова, через которую отдаются статус и заголовки
StartResponse = Callable[[str, list[tuple[str, str]]], object]


def application(
    environ: dict[str, object], start_response: StartResponse
) -> Iterable[bytes]:
    """Точка входа WSGI.

    Обратите внимание, чего здесь нет: разбора пути в параметры, разбора
    JSON, объекта запроса, обработки ошибок. Ключи environ — это то, что
    сервер вычитал из сокета, и не более того.
    """
    path = str(environ.get("PATH_INFO", "/"))
    method = str(environ.get("REQUEST_METHOD", "GET"))

    if path == "/health" and method == "GET":
        body = json.dumps({"status": "ok"}).encode("utf-8")
        start_response(
            "200 OK",
            [
                ("Content-Type", "application/json"),
                # длину считает приложение: сервер её не подставит
                ("Content-Length", str(len(body))),
            ],
        )
        # возвращается итерируемое байтов, а не строка: строка была бы
        # отдана по одному символу за раз
        return [body]

    body = json.dumps({"error": "not found", "path": path}).encode("utf-8")
    start_response(
        "404 Not Found",
        [("Content-Type", "application/json"), ("Content-Length", str(len(body)))],
    )
    return [body]


if __name__ == "__main__":
    from wsgiref.simple_server import make_server

    # Сервер из стандартной библиотеки: однопоточный, без ограничений
    # на размер запроса. Он годится ровно для этого примера.
    with make_server("127.0.0.1", 8001, application) as server:
        print("http://127.0.0.1:8001/health")
        server.serve_forever()
