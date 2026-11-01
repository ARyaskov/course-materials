"""Окружение Alembic.

Метаданные берутся у приложения: генератор сравнивает описанные модели
с фактической схемой и потому видит ровно то, что видит SQLAlchemy.
"""

import logging
from logging.config import fileConfig

from alembic import context
from flask import current_app

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)
log = logging.getLogger("alembic.env")


def get_engine():  # type: ignore[no-untyped-def]
    return current_app.extensions["migrate"].db.engine


def get_metadata():  # type: ignore[no-untyped-def]
    return current_app.extensions["migrate"].db.metadata


#: строка подключения берётся у приложения, а не из alembic.ini: пароль
#: не должен лежать в файле репозитория
config.set_main_option(
    "sqlalchemy.url", str(get_engine().url).replace("%", "%%")
)


def run_migrations_offline() -> None:
    """Генерация SQL без подключения — для проверки на ревью."""
    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=get_metadata(),
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = get_engine()

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=get_metadata(),
            # сравнение типов включено: смена VARCHAR(50) на VARCHAR(200)
            # иначе останется незамеченной
            compare_type=True,
            # сравнение значений по умолчанию на стороне сервера
            compare_server_default=True,
            # соглашение об именах должно совпадать с метаданными, иначе
            # автогенерация будет пересоздавать ограничения на каждом прогоне
            render_as_batch=False,
            # блокировка на время миграции: два экземпляра приложения при
            # выкладке не должны применять одну ревизию одновременно
            transaction_per_migration=True,
        )

        with context.begin_transaction():
            connection.exec_driver_sql("SELECT pg_advisory_xact_lock(864213)")
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
