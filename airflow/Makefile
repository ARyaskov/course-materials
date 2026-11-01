# Удобные команды для локального стенда (требуется GNU Make).
# Используем '>' как префикс рецептов, чтобы не зависеть от символов табуляции.
.RECIPEPREFIX = >
.PHONY: build init up down logs ps test

build:
> docker compose build

init:
> docker compose up airflow-init

up:
> docker compose up -d

down:
> docker compose down

logs:
> docker compose logs -f airflow-scheduler

ps:
> docker compose ps

test:
> docker compose exec airflow-scheduler pytest -q
