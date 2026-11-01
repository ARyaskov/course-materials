"""Версия 1 публичного API.

Blueprint собирает разделы в один префикс и даёт единое место для хуков,
общих для всех защищённых маршрутов. Версия зашита в префикс, а не
в заголовок: путь виден в журналах прокси, в метриках и в кеше.
"""

from flask import Blueprint, g, request

from depot.api.auth import authenticate

bp = Blueprint("v1", __name__)

#: маршруты, доступные без токена; сравнение по имени обработчика, а не по
#: пути — путь меняется при переносе, имя остаётся
PUBLIC_ENDPOINTS = frozenset(
    {
        "v1.register",
        "v1.login",
        "v1.refresh",
        "v1.list_models",
        "v1.get_model",
        "v1.list_stations",
    }
)


@bp.before_request
def resolve_actor() -> None:
    """Аутентификация до любого обработчика раздела.

    Список исключений, а не список защищённых: забытый в списке маршрут
    останется закрытым, а не откроется наружу.
    """
    if request.method == "OPTIONS":
        return
    if request.endpoint in PUBLIC_ENDPOINTS:
        # анонимный доступ разрешён, но токен, если он есть, всё равно
        # разбирается: выдача может зависеть от роли
        from depot.api.auth import extract_bearer_token

        if extract_bearer_token(request) is None:
            g.actor = None
            return
    g.actor = authenticate(request)


@bp.teardown_request
def drop_request_cache(exc: BaseException | None) -> None:
    """Сброс кеша запроса.

    Сессию базы снимает Flask-SQLAlchemy своим teardown; здесь снимается
    только то, что положил слой HTTP.
    """
    g.pop("_current_user", None)


# импорт разделов внизу: каждый модуль обращается к bp, объявленному выше
from depot.api.v1 import auth as _auth  # noqa: E402,F401
from depot.api.v1 import bookings as _bookings  # noqa: E402,F401
from depot.api.v1 import catalog as _catalog  # noqa: E402,F401
from depot.api.v1 import imports as _imports  # noqa: E402,F401
from depot.api.v1 import invoices as _invoices  # noqa: E402,F401
from depot.api.v1 import rentals as _rentals  # noqa: E402,F401
