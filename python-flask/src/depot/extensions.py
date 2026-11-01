"""Объекты расширений.

Модуль не импортирует ничего из проекта: он импортируется модулями с моделями,
и обратная зависимость дала бы круговой импорт.

Объекты создаются здесь, привязка к приложению — в фабрике через `init_app`.
Двухшаговая инициализация позволяет одному набору моделей работать
с несколькими приложениями, благодаря чему каждый тест получает своё.
"""

from sqlalchemy import MetaData
from sqlalchemy.orm import DeclarativeBase

from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy

#: Имена ограничений должны быть предсказуемы: по ним миграции их удаляют,
#: а код различает ошибки целостности. Задать нужно до первой миграции.
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


db = SQLAlchemy(model_class=Base)
migrate = Migrate()
