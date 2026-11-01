# Короткие команды для повседневной работы. Ценность не в экономии букв,
# а в том, что у всех участников проекта и у конвейера сборки они одни и те же.

.DEFAULT_GOAL := help
.PHONY: help install dev lint format type test test-fast cov check run worker scheduler migrate revision up down logs shell openapi

PYTHON ?= python
COMPOSE ?= docker compose

help:  ## Список команд
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

install:  ## Установить проект с зависимостями разработки
	$(PYTHON) -m pip install -e ".[dev]"

lint:  ## Проверить стиль
	ruff check src tests

format:  ## Отформатировать и починить импорты
	ruff format src tests
	ruff check --fix src tests

type:  ## Проверить типы
	mypy src

test:  ## Прогнать все тесты
	pytest

test-fast:  ## Только быстрые тесты, без базы
	pytest -m "not integration" -q

cov:  ## Тесты с отчётом о покрытии
	pytest --cov=depot --cov-report=term-missing --cov-report=html

check: lint type test  ## Полная проверка — то же, что делает конвейер

run:  ## Запустить приложение для разработки
	flask --app depot:create_app run --debug

worker:  ## Запустить обработчик очереди
	rq worker --url $${DEPOT_REDIS_URL:-redis://localhost:6379/0} default

scheduler:  ## Запустить планировщик регламентных задач
	$(PYTHON) -c "from depot.jobs.scheduler import run_forever; run_forever()"

migrate:  ## Применить миграции
	flask --app depot:create_app db upgrade

revision:  ## Создать миграцию: make revision m="описание"
	flask --app depot:create_app db migrate -m "$(m)"

openapi:  ## Выгрузить описание API в файл
	flask --app depot:create_app export-openapi --output openapi.json

up:  ## Поднять окружение разработки
	$(COMPOSE) up -d --build

down:  ## Остановить окружение; данные в томе сохраняются
	$(COMPOSE) down

logs:  ## Журнал приложения
	$(COMPOSE) logs -f api

shell:  ## Оболочка внутри контейнера приложения
	$(COMPOSE) exec api /bin/bash
