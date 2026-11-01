"""Хуки жизненного цикла запроса.

`before_request` вызываются в порядке регистрации, `after_request` — в обратном.
Идентификатор запроса устанавливается первым: иначе всё, что логируется
в других хуках, останется без него.
"""

import time
import uuid

from flask import Flask, Response, g, request

#: служебные пути исключаются из журнала: проверка живости вызывается
#: каждые несколько секунд и составила бы 90% записей
SILENT_PATHS = frozenset({"/healthz", "/readyz", "/metrics"})


def register_hooks(app: Flask) -> None:
    @app.before_request
    def start_request() -> None:
        # идентификатор принимается от прокси: тогда цепочка прослеживается
        # с самого края, включая фоновые задачи
        g.request_id = request.headers.get("X-Request-Id") or uuid.uuid4().hex
        g.started_at = time.perf_counter()

    @app.after_request
    def finish_request(response: Response) -> Response:
        response.headers["X-Request-Id"] = g.get("request_id", "")
        # setdefault не затирает значение, выставленное обработчиком
        response.headers.setdefault("Cache-Control", "no-store")

        if request.path in SILENT_PATHS and response.status_code < 400:
            return response

        started = g.get("started_at")
        elapsed_ms = (time.perf_counter() - started) * 1000 if started else 0.0
        actor = g.get("actor")

        app.logger.info(
            "%s %s %s %.1fms",
            request.method,
            request.path,
            response.status_code,
            elapsed_ms,
            extra={
                "endpoint": request.endpoint,
                "status": response.status_code,
                "duration_ms": round(elapsed_ms, 1),
                "user_id": actor.id if actor else None,
            },
        )
        # возврат обязателен: без него ответ станет None
        return response

    @app.teardown_request
    def cleanup(exc: BaseException | None) -> None:
        """Вызывается всегда, включая случай исключения.

        `after_request` при необработанном исключении не вызывается,
        поэтому освобождение ресурсов делается здесь.
        """
        return None
