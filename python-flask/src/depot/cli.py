"""Команды администрирования.

Команда — та же операция, что и обработчик, но с другим входом и другим
выводом: тот же сервис, тот же контекст вызова, другие обстоятельства.
Дублировать логику в командах — верный способ получить две расходящиеся
реализации одного правила.
"""

import sys
from datetime import UTC, datetime

import click
from flask import Flask
from flask.cli import with_appcontext

from depot.domain.enums import UserRole
from depot.domain.errors import DepotError


@click.command("create-admin")
@click.option("--email", required=True)
@click.option("--full-name", required=True)
@click.password_option(
    "--password",
    prompt=True,
    confirmation_prompt=True,
    # пароль не передаётся аргументом: он попадёт в историю оболочки
    # и в список процессов
    help="Запрашивается интерактивно",
)
@with_appcontext
def create_admin(email: str, full_name: str, password: str) -> None:
    """Создать администратора."""
    from werkzeug.security import generate_password_hash

    from depot.domain.models import User
    from depot.services.uow import make_uow

    with make_uow() as uow:
        user = User(
            email=email.lower(),
            password_hash=generate_password_hash(password),
            full_name=full_name,
            role=UserRole.ADMIN,
            password_changed_at=datetime.now(UTC),
        )
        uow.users.add(user)
        click.echo(f"создан администратор {user.email} (id={user.id})")


@click.command("create-station")
@click.option("--title", required=True)
@click.option("--address", required=True)
@click.option("--timezone", default="Europe/Moscow", show_default=True)
@with_appcontext
def create_station(title: str, address: str, timezone: str) -> None:
    """Добавить точку выдачи."""
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

    from depot.domain.models import Station
    from depot.services.uow import make_uow

    try:
        ZoneInfo(timezone)
    except ZoneInfoNotFoundError:
        # проверка здесь, а не при первом расчёте тарифа через месяц
        raise click.BadParameter(f"неизвестный часовой пояс: {timezone}") from None

    with make_uow() as uow:
        station = Station(title=title, address=address, timezone=timezone)
        uow.session.add(station)
        uow.flush()
        click.echo(f"создана точка {station.title} (id={station.id})")


@click.command("expire-holds")
@click.option("--limit", default=200, show_default=True)
@with_appcontext
def expire_holds(limit: int) -> None:
    """Снять просроченные удержания вручную."""
    from flask import current_app

    from depot.services.booking import BookingService
    from depot.services.uow import make_uow

    service = BookingService(
        uow_factory=make_uow,
        queue=current_app.extensions["queue"],
        clock=current_app.extensions["clock"],
        notifier=current_app.extensions["notifier"],
        payment=current_app.extensions["payment"],
    )
    click.echo(f"снято удержаний: {service.expire_stale(limit)}")


@click.command("export-openapi")
@click.option("--output", type=click.Path(dir_okay=False), default="-")
@with_appcontext
def export_openapi(output: str) -> None:
    """Выгрузить описание API.

    Отдельная команда нужна конвейеру сборки: описание проверяется на
    несовместимые изменения до выкладки, а не после.
    """
    import json

    from flask import current_app

    document = json.dumps(
        current_app.extensions["openapi"], ensure_ascii=False, indent=2
    )
    if output == "-":
        click.echo(document)
        return
    with open(output, "w", encoding="utf-8") as handle:
        handle.write(document)
    click.echo(f"описание сохранено: {output}")


@click.command("check-config")
@with_appcontext
def check_config() -> None:
    """Проверить конфигурацию и доступность зависимостей.

    Запускается на выкладке до переключения трафика: неверная строка
    подключения должна проявиться здесь, а не на первом запросе.
    """
    from sqlalchemy import text

    from depot.config import mask_dsn
    from depot.extensions import db
    from flask import current_app

    failures: list[str] = []

    click.echo(f"окружение: {current_app.config['ENV_NAME']}")
    click.echo(f"база: {mask_dsn(current_app.config['SQLALCHEMY_DATABASE_URI'])}")

    try:
        db.session.execute(text("SELECT 1"))
        click.echo("база: доступна")
    except Exception as exc:  # noqa: BLE001 — команда сообщает, а не падает
        failures.append(f"база: {exc}")

    try:
        current_app.extensions["cache"].ping()
        click.echo("кеш: доступен")
    except Exception as exc:  # noqa: BLE001
        failures.append(f"кеш: {exc}")

    for line in failures:
        click.echo(line, err=True)
    if failures:
        # ненулевой код возврата обязателен: конвейер выкладки читает его,
        # а не текст сообщения
        sys.exit(1)


def register_cli(app: Flask) -> None:
    for command in (
        create_admin,
        create_station,
        expire_holds,
        export_openapi,
        check_config,
    ):
        app.cli.add_command(command)


def main() -> None:
    """Точка входа `depot-admin`.

    Доменная ошибка печатается сообщением, а не трассировкой: пользователь
    команды не должен читать стек, чтобы понять, что адрес уже занят.
    """
    from flask.cli import FlaskGroup

    from depot import create_app

    cli = FlaskGroup(create_app=create_app)
    try:
        cli.main(standalone_mode=False)
    except DepotError as exc:
        click.echo(str(exc), err=True)
        sys.exit(1)
