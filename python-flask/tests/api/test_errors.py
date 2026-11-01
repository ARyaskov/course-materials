"""Форма ответа об ошибке.

Контракт ошибок проверяется отдельно от сценариев: клиент разбирает
поле code, и его изменение ломает интеграции так же, как переименование
поля в успешном ответе.
"""

import pytest

from depot.domain.errors import DomainError, NotFound


def test_unknown_route_returns_json(client) -> None:  # type: ignore[no-untyped-def]
    """404 приходит в том же формате, что и доменные ошибки.

    Без обработчика HTTPException Flask вернул бы HTML-страницу, и клиент,
    разбирающий JSON, получил бы ошибку разбора вместо понятного кода.
    """
    response = client.get("/api/v1/nope")
    assert response.status_code == 404
    assert response.is_json
    assert response.get_json()["error"]["code"] == "not_found"


def test_method_not_allowed_keeps_allow_header(client) -> None:  # type: ignore[no-untyped-def]
    response = client.delete("/api/v1/models")
    assert response.status_code == 405
    # заголовок исключения передаётся дальше: без него клиент не узнает,
    # какие методы поддерживаются
    assert "Allow" in response.headers


def test_error_body_carries_request_id(client) -> None:  # type: ignore[no-untyped-def]
    response = client.get("/api/v1/bookings")
    body = response.get_json()
    assert body["error"]["request_id"]
    # тот же идентификатор в заголовке: по нему сопоставляются жалоба
    # пользователя и строка в журнале
    assert response.headers["X-Request-Id"] == body["error"]["request_id"]


def test_internal_error_does_not_leak_details(app, client) -> None:  # type: ignore[no-untyped-def]
    @app.get("/boom")
    def boom():  # type: ignore[no-untyped-def]
        raise RuntimeError("строка подключения: postgresql://user:pass@db/depot")

    response = client.get("/boom")
    assert response.status_code == 500
    body = response.get_json()
    assert body["error"]["code"] == "internal_error"
    # подробности остаются в журнале: сообщение исключения наружу не идёт
    assert "postgresql" not in response.get_data(as_text=True)


def test_domain_error_status_comes_from_class() -> None:
    class Custom(DomainError):
        code = "custom"
        status = 418

    assert Custom("тест").status == 418
    assert NotFound("нет").status == 404


@pytest.mark.parametrize("path", ["/healthz", "/readyz", "/version"])
def test_service_routes_do_not_require_token(client, path: str) -> None:  # type: ignore[no-untyped-def]
    response = client.get(path)
    # готовность может вернуть 503 при недоступной базе, но не 401
    assert response.status_code != 401
