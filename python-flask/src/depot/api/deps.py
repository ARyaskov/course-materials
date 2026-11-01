"""Сборка зависимостей для обработчиков.

Контейнера здесь нет: список зависимостей обозрим, а функция-фабрика
читается лучше, чем конфигурация контейнера. Компоненты без состояния
живут в `app.extensions` и создаются один раз при старте; сервисы дёшевы
и собираются на вызов — они хранят только ссылки.
"""

from typing import Any

from flask import current_app

from depot.services.uow import make_uow


def component(name: str) -> Any:
    """Единая точка обращения к общим компонентам.

    Пропущенный компонент проявляется понятной ошибкой на первом же запросе,
    а не KeyError из середины сервиса.
    """
    try:
        return current_app.extensions[name]
    except KeyError:
        raise RuntimeError(
            f"компонент {name!r} не зарегистрирован; проверьте build_components"
        ) from None


def clock() -> Any:
    return component("clock")


def cache() -> Any:
    return component("cache")


def queue() -> Any:
    return component("queue")


def storage() -> Any:
    return component("storage")


def notifier() -> Any:
    return component("notifier")


def payment() -> Any:
    return component("payment")


def token_service() -> Any:
    return component("tokens")


def user_repository() -> Any:
    """Репозиторий вне сценария — только для чтения профиля.

    Единица работы здесь своя и закрывается вместе с транзакцией чтения:
    смешивать её с транзакцией сценария не нужно.
    """
    return make_uow().users


def booking_service() -> Any:
    from depot.services.booking import BookingService

    # передаётся фабрика, а не готовая единица работы: каждая операция
    # открывает собственную транзакцию
    return BookingService(
        uow_factory=make_uow,
        queue=queue(),
        clock=clock(),
        notifier=notifier(),
        payment=payment(),
    )


def rental_service() -> Any:
    from depot.services.rental import RentalService

    return RentalService(
        uow_factory=make_uow,
        queue=queue(),
        clock=clock(),
        storage=storage(),
        payment=payment(),
    )


def catalog_service() -> Any:
    from depot.services.catalog import CatalogService

    return CatalogService(uow_factory=make_uow, clock=clock(), cache=cache())


def auth_service() -> Any:
    from depot.services.auth import AuthService

    return AuthService(
        uow_factory=make_uow,
        clock=clock(),
        tokens=token_service(),
        cache=cache(),
        notifier=notifier(),
    )


def billing_service() -> Any:
    from depot.services.billing import BillingService

    return BillingService(uow_factory=make_uow, clock=clock(), payment=payment())


def import_service() -> Any:
    from depot.services.import_catalog import ImportService

    return ImportService(
        uow_factory=make_uow, clock=clock(), queue=queue(), storage=storage()
    )
