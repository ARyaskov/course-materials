# HelpDesk API — сквозной проект курса PHP 8.5 / Yii3

Backend системы поддержки: заявки, комментарии, вложения, роли, SLA. Проект собран из
листингов 128 уроков курса — урок остаётся источником истины, каталог `project`
его материализацией.

## Быстрый старт

```bash
cp .env.example .env          # заполнить пароли и APP_SECRET
docker compose up -d --build
docker compose exec app composer install
docker compose exec app php yii migrate:up --interactive=0
curl -i http://localhost:8080/api/v1/health
```

`compose.override.yaml` подхватывается автоматически и переводит стенд в режим разработки:
исходники монтируются томами, `opcache.validate_timestamps` включён, поднимается заглушка
внешнего справочника и три тестовые базы для параллельного прогона PHPUnit.
