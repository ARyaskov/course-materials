# Depot

API сети пунктов проката профессионального съёмочного оборудования: камеры,
оптика, свет, звук. Проект курса «Python 3.15 + Flask 3: руководство для
backend-разработчика» — он растёт от первого маршрута до системы с базой,
очередью, кешем, платёжным шлюзом и наблюдаемостью.

## Что внутри

| Слой | Каталог | Отвечает за |
| --- | --- | --- |
| Домен | `src/depot/domain` | сущности, правила аренды, доступ, цены |
| Репозитории | `src/depot/repositories` | запросы к базе, перевод ошибок драйвера |
| Сервисы | `src/depot/services` | сценарии, границы транзакций, протоколы зависимостей |
| Инфраструктура | `src/depot/infrastructure` | Redis, RQ, S3, SMTP, платёжный шлюз |
| HTTP | `src/depot/api` | схемы, обработчики, ошибки, OpenAPI |
| Задачи | `src/depot/jobs` | фоновая работа и расписание |

Зависимости направлены внутрь: домен не знает ни про Flask, ни про
SQLAlchemy-сессию. Инфраструктура реализует протоколы, объявленные
в `services/protocols.py`, а не наоборот.

## Что появляется в какой главе

Проект собирается по ходу курса. Таблица нужна, чтобы после любой главы
было понятно, какие файлы к ней относятся.

| Глава | Тема | Файлы |
| --- | --- | --- |
| 1–2 | окружение, структура проекта | `check_env.py`, `wsgi_min.py`, `pyproject.toml` |
| 3–4 | язык и стандартная библиотека | `depot.toml`, `common/clock.py`, `common/money.py` |
| 5 | типизация, dataclasses, enum | `domain/ids.py`, `domain/enums.py`, `domain/money.py`, `domain/period.py` |
| 6 | контракт HTTP | `docs/api-intro.md` |
| 7 | первое приложение Flask | `wsgi.py`, первые маршруты |
| 8 | фабрика, blueprint, конфигурация | `__init__.py`, `config.py`, `extensions.py`, `api/hooks.py` |
| 9 | схемы запросов и ответов | `api/v1/schemas/` |
| 10–11 | база, модели, миграции | `domain/models.py`, `migrations/`, `scripts/` |
| 12 | слои и единица работы | `repositories/`, `services/`, `container.py`, `api/deps.py` |
| 13 | аутентификация и права | `services/tokens.py`, `services/auth.py`, `domain/access.py`, `domain/permissions.py` |
| 14 | ошибки, журналы, устойчивость | `domain/errors.py`, `api/errors.py`, `observability/logs.py`, `infrastructure/resilience.py` |
| 15 | фоновые задачи и расписание | `jobs/` |
| 16 | кеш, файлы, внешние API | `infrastructure/cache_redis.py`, `infrastructure/storage.py`, `infrastructure/payment.py` |
| 17 | тесты | `tests/` |
| 18 | документация API | `api/docs/` |
| 19 | сборка и выкладка | `Dockerfile`, `gunicorn.conf.py`, `docker-compose*.yml`, `deploy/` |
| 20 | сборка проекта целиком | `docs/domain.md`, `docs/decisions.md`, `docs/runbook.md` |

## Стек

Python 3.15, Flask 3.1, SQLAlchemy 2.0, Alembic, Pydantic 2, PostgreSQL 18,
Redis 8, RQ 2, PyJWT, httpx, boto3, pytest 8, ruff, mypy, Gunicorn 23,
Docker 28.

## Запуск

```bash
cp .env.example .env
# ключ подписи: python -c "import secrets; print(secrets.token_urlsafe(48))"
docker compose up -d --build
docker compose exec api flask db upgrade
docker compose exec api flask create-admin --email admin@example.com --full-name "Администратор"
```

Описание API: `http://localhost:8000/api/v1/docs`.

Без Docker:

```bash
python -m pip install -e ".[dev]"
flask --app depot:create_app db upgrade
flask --app depot:create_app run --debug
```

### Обновление зависимостей Docker-образа

`requirements.lock.txt` фиксирует прямые и транзитивные зависимости с SHA-256
для Python 3.15 и Linux. Dockerfile проверяет хеши при установке и запускает
`pip check` после установки приложения. Перегенерация из этой папки с `uv`:

```bash
uv pip compile pyproject.toml --python-version 3.15 \
  --python-platform x86_64-unknown-linux-gnu --only-binary :all: \
  --generate-hashes --no-header --output-file requirements.lock.txt
```

## Проверки

```bash
make check
```

Это стиль (`ruff`), типы (`mypy`) и тесты (`pytest`) — тот же набор, что
выполняет конвейер сборки. Быстрая часть без базы: `make test-fast`.

## Конфигурация

Обязательные переменные не имеют значений по умолчанию: приложение падает
при старте, если их нет. Это осознанно — сервис, молча поднявшийся
с подставленным умолчанием, обнаруживается позже и дороже.

Полный список — в `.env.example`. Настоящий `.env` в репозиторий не
попадает и в образ не копируется.

## Что важно знать при чтении кода

- Пересечение броней запрещает ограничение исключения PostgreSQL
  (`migrations/versions/0005_booking_overlap.py`), а не проверка перед
  вставкой: две одновременные брони проходят проверку обе.
- Границы транзакций задаёт единица работы (`services/uow.py`);
  репозитории не вызывают `commit`.
- Постановка задач в очередь происходит после фиксации транзакции.
  Потерянную постановку восстанавливает периодическая задача из данных.
- Чужой объект даёт 404, а не 403: ответ не подтверждает его существование.
- Денежные суммы — `Decimal` и строки в JSON. Ни одного `float`.

Подробности решений — в `docs/decisions.md`, эксплуатация — в
`docs/runbook.md`.
